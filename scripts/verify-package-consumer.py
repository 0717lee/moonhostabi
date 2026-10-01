#!/usr/bin/env python3
"""Exercise a real package through a private, disposable Mooncakes registry.

Python standard library only. Exit 0 means the local candidate passed; exit 1
means NO_GO (including an expected pre-vendoring RED). No public publication.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import http.server
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile


ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = "0717lee/moonhostabi"
# SHA-256 values from the official registry index, not from local source trees.
DEPENDENCIES = {
    "Milky2018/wasm_core": ("0.14.0", "3de253ae7c9889566363a0f8615d2ad6763f60c355f7a33059261ee020421c2a"),
    "moonbitlang/x": ("0.5.1", "cdceed523974dbd2833930f70e7e7ee087b77220659c55f87ab678197976aeae"),
}
OFFICIAL_SOURCE = "https://raw.githubusercontent.com/moonbitlang/moon/914d7da/"
CLIENT_SOURCES = [
    "crates/moonutil/src/mooncakes.rs",
    "crates/moonutil/src/moon_dir.rs",
    "crates/mooncake/src/registry/client.rs",
]
MAX_ZIP_BYTES = 128 * 1024 * 1024
MAX_UNPACKED_BYTES = 256 * 1024 * 1024
SMOKE_MARKERS = (
    "PACKAGE_CONSUMER_RECURSIVE=GO",
    "PACKAGE_CONSUMER_DEPTH_256=GO",
    "PACKAGE_CONSUMER_OWNED_ERRORS=GO",
    "PACKAGE_CONSUMER_LOCK_VERIFY=GO",
    "PACKAGE_CONSUMER_SMOKE=GO",
)


class GateError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def checked_archive(data: bytes, checksum: str) -> dict[str, bytes]:
    """Validate every member before the normal Moon client extracts this ZIP."""
    if len(data) > MAX_ZIP_BYTES or sha256(data) != checksum:
        raise GateError("archive size or SHA-256 mismatch")
    files: dict[str, bytes] = {}
    seen: set[str] = set()
    total = 0
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            name = member.orig_filename
            parts = name.rstrip("/").split("/")
            mode = member.external_attr >> 16
            if (not name or name.startswith("/") or "\\" in name or ":" in name
                    or "\0" in name or any(p in ("", ".", "..") for p in parts)
                    or any(p.endswith((".", " ")) for p in parts)
                    or any(p.split(".")[0].upper() in {"CON", "PRN", "AUX", "NUL", *[f"COM{i}" for i in range(1, 10)], *[f"LPT{i}" for i in range(1, 10)]} for p in parts)
                    or stat.S_ISLNK(mode) or stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)):
                raise GateError(f"unsafe archive member: {name!r}")
            key = name.rstrip("/").casefold()
            if key in seen:
                raise GateError(f"duplicate archive member: {name}")
            seen.add(key)
            total += member.file_size
            if total > MAX_UNPACKED_BYTES or len(seen) > 30000:
                raise GateError("archive expansion limit exceeded")
            if not member.is_dir():
                files[name] = archive.read(member)  # Also verifies ZIP CRC.
    file_names = {p.casefold() for p in files}
    for name in files:
        if any(str(parent).casefold() in file_names
               for parent in PurePosixPath(name).parents if str(parent) != "."):
            raise GateError(f"archive file/directory collision: {name}")
    return files


def manifest(files: dict[str, bytes]) -> dict:
    if "moon.mod.json" in files:
        result = json.loads(files["moon.mod.json"])
        if any(isinstance(value, dict) and ("path" in value or "git" in value)
               for value in result.get("deps", {}).values()):
            raise GateError("path/git dependency in archive manifest")
        return result
    text = files["moon.mod"].decode("utf-8")
    text = re.sub(r"(?m)^\s*//.*$", "", text)
    result = {}
    for key in ("name", "version"):
        match = re.search(rf'(?m)^\s*{key}\s*=\s*"([^"\n]+)"', text)
        if not match:
            raise GateError(f"missing manifest {key}")
        result[key] = match[1]
    match = re.search(r"\bimport\s*\{([^}]*)\}", text)
    result["deps"] = {}
    if match:
        block = match[1]
        entries = re.findall(r'"([^"\n]+)"', block)
        if re.sub(r'"[^"\n]+"|[\s,]', "", block):
            raise GateError("unsupported dependency syntax; expected ordinary registry imports")
        for entry in entries:
            name, version = entry.rsplit("@", 1)
            result["deps"][name] = version
    if re.search(r"\b(?:scripts|pre_build|postadd|bin_deps)\b", text):
        raise GateError("package hooks or binary dependencies require explicit gate support")
    return result


def archive_route(name: str, version: str) -> str:
    return "/user/" + urllib.parse.quote(f"{name}/{version}", safe="") + ".zip"


def isolated_env(base: dict[str, str], home: Path, toolchain: Path) -> dict[str, str]:
    # Do not inherit registry, workspace, core, dependency or build overrides.
    env = {k: v for k, v in base.items() if not k.upper().startswith(("MOON", "GIT_"))}
    env.update(MOON_HOME=str(home), MOON_TOOLCHAIN_ROOT=str(toolchain),
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(home / "empty.gitconfig"),
               GIT_TERMINAL_PROMPT="0", NO_PROXY="127.0.0.1,localhost",
               no_proxy="127.0.0.1,localhost")
    return env


def registry_config(home: Path, index: Path, url: str) -> dict:
    if urllib.parse.urlsplit(url).hostname != "127.0.0.1":
        raise GateError("registry must bind loopback")
    home.mkdir(parents=True, exist_ok=False)
    config = {"registry": url, "index": index.resolve().as_uri()}
    write_json(home / "config.json", config)
    (home / "empty.gitconfig").write_text("", encoding="utf-8")
    return config


@contextlib.contextmanager
def registry_server(archives: dict[str, bytes], events: list[dict]):
    """Serve exact preverified paths from memory. No filesystem or proxy fallback."""
    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def do_GET(self):
            payload = archives.get(self.path)
            code = 200 if payload is not None else 404
            event = {"method": "GET", "path": self.path, "status": code,
                     "bytes": len(payload) if payload is not None else 0,
                     "sha256": sha256(payload) if payload is not None else None}
            events.append(event)
            self.send_response(code)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(event["bytes"]))
            self.end_headers()
            if payload is not None:
                self.wfile.write(payload)

        def log_message(self, *_args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def run_process(command: list[str], cwd: Path, env: dict, timeout: int,
                report: dict, output: Path, label: str, required: bool = True) -> str:
    stdout_path = output / f"{label}.stdout.txt"
    stderr_path = output / f"{label}.stderr.txt"
    step = {"label": label, "command": command, "cwd": str(cwd),
            "stdout": stdout_path.name, "stderr": stderr_path.name}
    report["steps"].append(step)
    started = time.monotonic()
    options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
    with stdout_path.open("wb") as out, stderr_path.open("wb") as err:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=out, stderr=err, **options)
        try:
            step["exit_code"] = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            step["timed_out"] = True
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
                               creationflags=subprocess.CREATE_NO_WINDOW)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.kill()
            process.wait(timeout=10)
            step["exit_code"] = process.returncode
        finally:
            step["seconds"] = round(time.monotonic() - started, 3)
    text = stdout_path.read_text(encoding="utf-8", errors="replace")
    combined = text + stderr_path.read_text(encoding="utf-8", errors="replace")
    print(f"PACKAGE_CONSUMER_STEP={label} EXIT={step['exit_code']}", flush=True)
    if step.get("timed_out") or (required and step["exit_code"] != 0):
        raise GateError(f"{label} failed; see {stdout_path.name} and {stderr_path.name}")
    return combined


def fetch_worker(url: str, destination: Path) -> None:
    allowed = {"https://download.mooncakes.io" + archive_route(name, version)
               for name, (version, _checksum) in DEPENDENCIES.items()}
    if url not in allowed:
        raise GateError("URL outside fixed official download allowlist")
    class OfficialRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            # The official download endpoint currently redirects to this CDN.
            # Permit only the identical allowlisted object, never arbitrary hosts.
            expected = "https://d15l9c1mnzh3r.cloudfront.net" + urllib.parse.urlsplit(url).path
            if not url.startswith("https://download.mooncakes.io/") or newurl != expected:
                raise GateError("unexpected redirect from pinned download endpoint")
            return super().redirect_request(req, fp, code, msg, headers, newurl)
    with urllib.request.build_opener(OfficialRedirect).open(url, timeout=20) as response:
        data = response.read(MAX_ZIP_BYTES + 1)
        print(json.dumps({"requested_url": url, "final_url": response.url, "sha256": sha256(data)}))
    if len(data) > MAX_ZIP_BYTES:
        raise GateError("download size limit exceeded")
    destination.write_bytes(data)


def snapshot(root: Path, expected: dict[str, bytes]) -> dict[str, str]:
    hashes = {}
    for relative, payload in expected.items():
        path = root / relative
        if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink():
            raise GateError(f"installed source escaped package root: {relative}")
        actual = sha256(path.read_bytes())
        if actual != sha256(payload):
            raise GateError(f"installed bytes differ from archive: {relative}")
        hashes[relative] = actual
    # Generated interfaces/build outputs are not source mutations. Extra source is.
    expected_sources = {n for n in expected if n.endswith((".mbt", ".c", ".h"))}
    actual_sources = {p.relative_to(root).as_posix() for p in root.rglob("*")
                      if p.is_file() and p.suffix in (".mbt", ".c", ".h")
                      and "_build" not in p.relative_to(root).parts}
    if actual_sources != expected_sources:
        raise GateError(f"installed source set changed: {sorted(actual_sources ^ expected_sources)[:5]}")
    return hashes


def production_issues(files: dict[str, bytes]) -> list[str]:
    issues = []
    parser = [n for n in files if n.startswith("src/internal/wasm_parser/")
              and n.endswith(".mbt") and not n.endswith(("_test.mbt", "_wbtest.mbt"))]
    if not parser:
        issues.append("archive lacks src/internal/wasm_parser production sources")
    local = ROOT / "src/internal/wasm_parser"
    if local.is_dir():
        for path in local.rglob("*"):
            if path.is_file() and (path.name in ("moon.pkg", "moon.pkg.json") or
                                  (path.suffix == ".mbt" and not path.name.endswith(("_test.mbt", "_wbtest.mbt")))):
                relative = path.relative_to(ROOT).as_posix()
                if files.get(relative) != path.read_bytes():
                    issues.append(f"production parser missing or changed in archive: {relative}")
    for name in ("LICENSE", "README.md", "provenance.json"):
        relative = "third_party/wasm_core_parser/" + name
        if files.get(relative) != (ROOT / relative).read_bytes():
            issues.append(f"parser license/provenance missing or changed in archive: {relative}")
    if any(PurePosixPath(n).name.startswith("moon.work") for n in files):
        issues.append("archive includes workspace override")
    return issues


def source_plan(text: str, consumer: Path, installed: dict[str, Path]) -> list[str]:
    paths = []
    normalized = text.replace("\\", "/")
    for line in normalized.splitlines():
        for token in shlex.split(line, posix=True):
            if token.endswith(".mbt"):
                path = Path(token)
                if not path.is_absolute():
                    path = consumer / path
                resolved = path.resolve()
                if not resolved.is_relative_to(consumer.resolve()):
                    raise GateError(f"compiler source outside fresh consumer: {path}")
                if not resolved.is_file():
                    raise GateError(f"missing source-plan input: {path}")
                paths.append(str(resolved))
    if not paths:
        raise GateError("no compiler sources found in dry-run plan")
    for name, root in installed.items():
        if not any(Path(p).is_relative_to(root.resolve()) for p in paths):
            raise GateError(f"source plan does not prove registry resolution for {name}")
    return sorted(set(paths))


def cleanup_owned(root: Path, token: str) -> None:
    expected = f"moonhostabi-package-consumer-{token}"
    if (root.name != expected or root.is_symlink() or root.resolve() != root.absolute()
            or root.parent.resolve() != Path(tempfile.gettempdir()).resolve()
            or (root / ".owner").read_text(encoding="utf-8") != token):
        raise GateError(f"refusing cleanup of unowned temporary path: {root}")
    # Never traverse reparse points during recursive cleanup on Windows.
    for path in root.rglob("*"):
        if path.is_symlink() or getattr(path, "is_junction", lambda: False)():
            raise GateError(f"refusing cleanup through link: {path}")
    def remove_readonly(function, path, exc_info):
        # Git marks object files read-only on Windows. Clear that bit only on
        # already checked files inside this owned directory, then retry once.
        target = Path(path)
        if not isinstance(exc_info[1], PermissionError) or not target.resolve().is_relative_to(root.resolve()):
            raise exc_info[1]
        target.chmod(stat.S_IWRITE | stat.S_IREAD)
        function(path)
    shutil.rmtree(root, onerror=remove_readonly)


def execute(args) -> int:
    token = uuid.uuid4().hex
    output = ROOT / "_build/package-consumer" / (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + token[:8])
    output.mkdir(parents=True)
    temporary = Path(tempfile.gettempdir()).resolve() / f"moonhostabi-package-consumer-{token}"
    temporary.mkdir()
    (temporary / ".owner").write_text(token, encoding="utf-8")
    report = {"schema_version": 1, "status": "NO_GO", "public_release": False,
              "evidence": str(output), "temporary": str(temporary), "steps": [],
              "http_fetches": [], "archives": {}, "test_counts": {}, "policy_issues": []}
    print(f"PACKAGE_CONSUMER_EVIDENCE={output}", flush=True)
    try:
        moon_name = shutil.which("moon")
        if not moon_name:
            raise GateError("moon not on PATH")
        moon = Path(moon_name).resolve()
        toolchain = Path(args.toolchain_root).resolve() if args.toolchain_root else moon.parent.parent
        if not (toolchain / "include").is_dir() or not (toolchain / "lib/core").is_dir():
            raise GateError("--toolchain-root must name the actual toolchain, with include and lib/core")
        consumer = temporary / "consumer"
        shutil.copytree(ROOT / "examples/package-consumer", consumer)
        initial = manifest({"moon.mod": (consumer / "moon.mod").read_bytes()})
        if initial["deps"] or (consumer / ".mooncakes").exists():
            raise GateError("consumer template must have no module imports or installed dependencies")
        for parent in (consumer, *consumer.parents):
            if (parent / "moon.work").exists() or (parent / "moon.work.json").exists():
                raise GateError(f"workspace override above consumer: {parent}")
        home = consumer / ".moon-home"
        index = temporary / "local-git-index"
        index.mkdir()
        env = isolated_env(dict(os.environ), home, toolchain)
        git = args.git or shutil.which("git")
        if not git or not Path(git).is_file():
            raise GateError("git not found; provide --git with an existing Git executable")
        git = str(Path(git).resolve())
        env["PATH"] = str(Path(git).parent) + os.pathsep + env.get("PATH", "")
        report["git"] = git
        archives: dict[str, bytes] = {}
        with registry_server(archives, report["http_fetches"]) as url:
            report["config"] = registry_config(home, index, url)
            report["environment"] = {"MOON_HOME": str(home), "MOON_TOOLCHAIN_ROOT": str(toolchain),
                                     "MOONCAKES_REGISTRY": None}
            def run(command, label, cwd=consumer, required=True, timeout=None):
                return run_process([str(x) for x in command], cwd, env, timeout or args.timeout,
                                   report, output, label, required)
            versions = run([moon, "version", "--all"], "toolchain")
            if not re.search(r"(?m)^moon 0\.1\.20260920 \(914d7da 2026-09-20\)", versions) or not re.search(r"(?m)^moonc v0\.10\.14\+7d59c7ec9 \(2026-09-18\)", versions):
                raise GateError("expected pinned moon 914d7da / moonc 0.10.14 toolchain")
            # Design references only; exercising the installed client does not
            # require GitHub to serve its implementation on every gate run.
            report["official_client_source_references"] = [OFFICIAL_SOURCE + source for source in CLIENT_SOURCES]
            packages = {}
            for name, (dep_version, checksum) in DEPENDENCIES.items():
                destination = output / (name.replace("/", "-") + "-" + dep_version + ".zip")
                download_url = "https://download.mooncakes.io" + archive_route(name, dep_version)
                run([sys.executable, __file__, "--fetch", download_url, str(destination)],
                    "download-" + name.replace("/", "-"), timeout=90)
                data = destination.read_bytes()
                files = checked_archive(data, checksum)
                info = manifest(files)
                if info["name"] != name or info["version"] != dep_version or info.get("deps"):
                    raise GateError(f"unexpected dependency identity/transitive imports: {name}")
                packages[name] = (dep_version, data, files, info)
            def add_entry(name, package):
                pkg_version, data, files, info = package
                route = archive_route(name, pkg_version)
                archives[route] = data
                entry = {"name": name, "version": pkg_version, "deps": info.get("deps", {}),
                         "checksum": sha256(data), "yanked": False}
                owner, module = name.split("/", 1)
                entry_path = index / "user" / owner / (module + ".index")
                entry_path.parent.mkdir(parents=True, exist_ok=True)
                entry_path.write_text(json.dumps(entry) + "\n", encoding="utf-8")
                report["archives"][name] = {"version": pkg_version, "sha256": sha256(data),
                                           "file_count": len(files), "route": route}
            for name, package in packages.items():
                add_entry(name, package)
            run([git, "init", "--initial-branch=main", index], "index-init")
            run([git, "-C", index, "add", "user"], "index-add")
            run([git, "-C", index, "-c", "user.name=Package Consumer Test", "-c", "user.email=package-consumer@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + str(temporary / "no-hooks"), "commit", "-m", "Local registry fixture"], "index-commit")
            # Packaging runs a check even with --frozen. Seed only registry metadata
            # via the real client; do not modify the project's installed sources.
            run([moon, "update"], "index-bootstrap")
            package_dir = output / "package"
            if args.candidate_archive:
                # Replay an unchanged archive produced by a previous real moon
                # package (e.g. retain pre-wiring RED after concurrent edits).
                package_dir.mkdir()
                supplied = Path(args.candidate_archive).resolve()
                shutil.copyfile(supplied, package_dir / supplied.name)
                report["replayed_archive"] = str(supplied)
            else:
                run([moon, "package", "--frozen", "--target-dir", package_dir], "package", cwd=ROOT)
            candidates = list(package_dir.rglob("*.zip"))
            if len(candidates) != 1:
                raise GateError(f"expected exactly one moon package ZIP, found {len(candidates)}")
            candidate_data = candidates[0].read_bytes()
            candidate_files = checked_archive(candidate_data, sha256(candidate_data))
            candidate_manifest = manifest(candidate_files)
            version = candidate_manifest["version"]
            if candidate_manifest["name"] != CANDIDATE:
                raise GateError("wrong candidate module name")
            if candidate_manifest.get("deps", {}) != {n: v for n, (v, _h) in DEPENDENCIES.items()}:
                raise GateError("candidate dependency set differs from the narrow registry allowlist")
            report["candidate_version"] = version
            report["policy_issues"] = production_issues(candidate_files)
            packages[CANDIDATE] = (version, candidate_data, candidate_files, candidate_manifest)
            add_entry(CANDIDATE, packages[CANDIDATE])
            run([git, "-C", index, "add", "user"], "candidate-index-add")
            run([git, "-C", index, "-c", "user.name=Package Consumer Test", "-c", "user.email=package-consumer@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + str(temporary / "no-hooks"), "commit", "-m", "Local candidate fixture"], "candidate-index-commit")
            run([moon, "update"], "candidate-index-update")
            (output / "consumer.initial.moon.mod").write_bytes((consumer / "moon.mod").read_bytes())
            run([moon, "add", f"{CANDIDATE}@{version}"], "add")
            (output / "consumer.added.moon.mod").write_bytes((consumer / "moon.mod").read_bytes())
            installed = {}
            for name, (_v, _data, files, _info) in packages.items():
                owner, module = name.split("/", 1)
                matches = [p.parent for p in consumer.rglob("moon.mod*")
                           if p.name in ("moon.mod", "moon.mod.json") and p.parent.name == module
                           and p.parent.parent.name == owner]
                if len(matches) != 1:
                    raise GateError(f"expected one installed {name}, found {matches}")
                installed[name] = matches[0]
            before = {name: snapshot(root, packages[name][2]) for name, root in installed.items()}
            write_json(output / "installed.before.json", before)
            report["installed_roots"] = {name: str(root) for name, root in installed.items()}
            try:
                plan = run([moon, "check", "--target", "native", "--dry-run"], "source-plan")
                paths = source_plan(plan, consumer, installed)
                write_json(output / "source-paths.json", paths)
                report["source_plan_count"] = len(paths)
                for target in ("native", "js", "wasm-gc"):
                    checked = run([moon, "check", "--target", target], "check-" + target, required=False)
                    if report["steps"][-1]["exit_code"]:
                        report["red_missing_parse_module_iterative"] = "parse_module_iterative" in checked and ("not found" in checked or "unbound" in checked.lower())
                        raise GateError(f"clean consumer check failed for {target}")
                    tests = run([moon, "test", "--target", target], "test-" + target)
                    counts = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", tests)
                    if not counts or int(counts[1]) < 4 or counts[1] != counts[2] or int(counts[3]) != 0:
                        raise GateError(f"missing successful consumer test count for {target}")
                    report["test_counts"][target] = int(counts[1])
                    smoke = run([moon, "run", ".", "--target", target], "run-" + target)
                    if any(marker not in smoke.splitlines() for marker in SMOKE_MARKERS):
                        raise GateError(f"missing runtime assertion marker for {target}")
            finally:
                after = {name: snapshot(root, packages[name][2]) for name, root in installed.items()}
                write_json(output / "installed.after.json", after)
                report["installed_bytes_unchanged"] = before == after
                if before != after:
                    raise GateError("dependency bytes changed during consumer checks")
            fetched = {e["path"] for e in report["http_fetches"] if e["status"] == 200}
            if fetched != set(archives) or any(e["status"] != 200 for e in report["http_fetches"]):
                raise GateError("real HTTP fetches differ from exact registry allowlist")
            if report["policy_issues"]:
                raise GateError("; ".join(report["policy_issues"]))
            report["status"] = "GO"
    except (GateError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        report["error"] = str(error)
        print(f"PACKAGE_CONSUMER_ERROR={error}", flush=True)
    finally:
        try:
            cleanup_owned(temporary, token)
            report["temporary_cleanup"] = "GO"
        except (GateError, OSError) as error:
            report["status"] = "NO_GO"
            report["cleanup_error"] = str(error)
        write_json(output / "http-fetches.json", report["http_fetches"])
        write_json(output / "report.json", report)
        print(f"MOONHOSTABI_PACKAGE_CONSUMER_STATUS={report['status']}", flush=True)
    return 0 if report["status"] == "GO" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain-root", help="Actual MoonBit installation root (default: moon executable's parent parent)")
    parser.add_argument("--timeout", type=int, default=180, help="Per moon/git command timeout in seconds (default: 180)")
    parser.add_argument("--candidate-archive", help="Replay an unchanged ZIP from an earlier real moon package; recorded in evidence")
    parser.add_argument("--git", help="Existing Git executable (default: git on PATH)")
    parser.add_argument("--fetch", nargs=2, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.fetch:
        fetch_worker(args.fetch[0], Path(args.fetch[1]))
        return 0
    if not 1 <= args.timeout <= 1800:
        parser.error("--timeout must be between 1 and 1800 seconds")
    return execute(args)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
