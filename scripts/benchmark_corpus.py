"""Generate deterministic Wasm and measure an already-built native CLI.

Only the Python standard library is used. wasm-tools validates the generated
bytes independently before any measured process is launched.
"""

import argparse
import ctypes
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


HEADER = b"\0asm\x01\0\0\0"
CORPUS_VERSION = 1
GENERATED_FILES = {"adapter.ts", "moonhostabi.contract.json", "moonhostabi.manifest.json"}


@dataclass(frozen=True)
class Case:
    name: str
    axis: str
    value: int
    data: bytes
    operation: str = "inspect"


def uleb(value):
    if not 0 <= value < 2 ** 32:
        raise ValueError("unsigned LEB128 value must fit u32")
    encoded = bytearray()
    while True:
        byte = value & 127
        value >>= 7
        encoded.append(byte | (128 if value else 0))
        if not value:
            return bytes(encoded)


def section(section_id, payload):
    return bytes([section_id]) + uleb(len(payload)) + payload


def name(value):
    encoded = value.encode("utf-8")
    return uleb(len(encoded)) + encoded


def function_module(export_count=1, type_count=1):
    # The empty type is followed by distinct fixed-width base-4 signatures.
    # Even 512 types declare fewer than 3,100 type/parameter entries.
    scalar_types = (0x7F, 0x7E, 0x7D, 0x7C)
    types = [b"\x60\x00\x00"]
    for index in range(type_count - 1):
        params = bytes(scalar_types[(index >> (2 * digit)) & 3] for digit in range(5))
        types.append(b"\x60\x05" + params + b"\x00")
    exports = b"".join(name(f"f{index:06d}") + b"\x00\x00"
                       for index in range(export_count))
    return (HEADER + section(1, uleb(type_count) + b"".join(types))
            + section(3, b"\x01\x00")
            + section(7, uleb(export_count) + exports)
            + section(10, b"\x01\x02\x00\x0b"))


def memory_module(export_count):
    # One defined memory (min 0, max 1 page), exported under distinct names.
    exports = b"".join(name(f"memory{index:06d}") + b"\x02\x00"
                       for index in range(export_count))
    return HEADER + section(5, b"\x01\x01\x00\x01") + section(7, uleb(export_count) + exports)


def corpus_cases():
    cases = []
    base = function_module()
    for size in (64 * 1024, 1024 * 1024, 8 * 1024 * 1024):
        data = base + section(0, name("benchmark-payload") + b"x" * size)
        cases.append(Case(f"custom-{size}", "customPayloadBytes", size, data))
    for count in (32, 128, 512, 2048):
        cases.append(Case(f"exports-{count}", "functionExports", count,
                          function_module(export_count=count)))
    for count in (32, 128, 256, 512):
        cases.append(Case(f"types-{count}", "distinctTypes", count,
                          function_module(type_count=count)))
    for count in (32, 128, 512):
        cases.append(Case(f"resources-{count}", "memoryExports", count,
                          memory_module(count), "resource-verify"))
    return cases


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, document):
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_corpus(directory, cases):
    directory.mkdir(parents=True, exist_ok=True)
    entries = []
    for case in cases:
        filename = case.name + ".wasm"
        (directory / filename).write_bytes(case.data)
        entries.append({"name": case.name, "axis": case.axis, "value": case.value,
                        "operation": case.operation, "file": filename,
                        "byteLength": len(case.data), "sha256": sha256(case.data)})
    identity = {"version": CORPUS_VERSION, "cases": entries}
    corpus_hash = sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode())
    manifest = dict(identity, corpusSha256=corpus_hash)
    write_json(directory / "manifest.json", manifest)
    return manifest


def summarize(samples):
    ordered = sorted(samples)
    return {"medianMs": statistics.median(ordered),
            "p95Ms": ordered[math.ceil(0.95 * len(ordered)) - 1],
            "minMs": ordered[0], "maxMs": ordered[-1]}


def validate_inspect(stdout, export_count=None):
    document = json.loads(stdout)
    if document.get("schemaVersion") != 1:
        raise ValueError("inspect response must have schemaVersion 1")
    for field in ("imports", "exports", "types", "features"):
        if not isinstance(document.get(field), list):
            raise ValueError(f"inspect response must contain {field} array")
    if export_count is not None:
        expected = [{"module": None, "name": f"f{index:06d}", "params": [], "results": []}
                    for index in range(export_count)]
        if (document["exports"] != expected or document["imports"] or document["types"]
                or document["features"]):
            raise ValueError("inspect response does not match the generated function surface")


def validate_resource(stdout):
    document = json.loads(stdout)
    if (document.get("schemaVersion") != 1 or document.get("classification") != "compatible"
            or document.get("exitCode") != 0 or document.get("compatible") is not True
            or document.get("changes") != []):
        raise ValueError("resource-verify must report an unchanged compatible surface")


def process_peak_memory(process):
    observation = {"peakMemoryBytes": None, "method": "unavailable", "reason": None}
    if os.name != "nt":
        observation["reason"] = "per-process OS peak counter is not implemented on this platform"
        return observation
    observation["method"] = "GetProcessMemoryInfo.PeakWorkingSetSize"
    try:
        from ctypes import wintypes

        class ProcessMemoryCounters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
                (field, ctypes.c_size_t) for field in (
                    "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                    "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                    "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")]

        counters = ProcessMemoryCounters()
        counters.cb = ctypes.sizeof(counters)
        query = ctypes.WinDLL("psapi", use_last_error=True).GetProcessMemoryInfo
        query.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessMemoryCounters), wintypes.DWORD]
        query.restype = wintypes.BOOL
        # Popen retains the Windows process handle after communicate reaps it.
        if not query(wintypes.HANDLE(int(process._handle)), ctypes.byref(counters), counters.cb):
            raise ctypes.WinError(ctypes.get_last_error())
        if counters.PeakWorkingSetSize > 0:
            observation["peakMemoryBytes"] = int(counters.PeakWorkingSetSize)
        else:
            observation["reason"] = "OS counter returned zero; no usable peak observation"
    except (OSError, AttributeError) as error:
        observation["reason"] = str(error)
    return observation


def invoke(command, timeout):
    started = time.perf_counter_ns()
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        try:
            stdout_bytes, stderr_bytes = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            process.kill()
            process.communicate()
            raise RuntimeError(f"process exceeded {timeout}s and was killed: {command[0]}") from error
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        memory = process_peak_memory(process)
        exit_code = process.returncode
    stdout = stdout_bytes.decode("utf-8")
    stderr = stderr_bytes.decode("utf-8")
    if exit_code != 0 or stderr.strip():
        raise RuntimeError(f"expected exit 0 and empty stderr; got exit {exit_code}: "
                           f"{command!r}\nstdout={stdout[:4000]}\nstderr={stderr[:4000]}")
    return stdout, elapsed_ms, memory


def validate_generated(directory, stdout):
    paths = list(directory.iterdir())
    if ({path.name for path in paths} != GENERATED_FILES
            or any(not path.is_file() or path.is_symlink() for path in paths)):
        raise ValueError("generated output must contain exactly the three expected regular files")
    hashes = {path.name: sha256(path.read_bytes()) for path in paths}
    response = json.loads(stdout)
    manifest = json.loads((directory / "moonhostabi.manifest.json").read_text(encoding="utf-8"))
    contract = json.loads((directory / "moonhostabi.contract.json").read_text(encoding="utf-8"))
    expected_hashes = {key: value for key, value in hashes.items() if key != "moonhostabi.manifest.json"}
    abi_hash = response.get("abiSha256", "")
    if (len(abi_hash) != 64 or any(char not in "0123456789abcdef" for char in abi_hash)
            or set(response.get("files", [])) != GENERATED_FILES
            or len(response["files"]) != 3 or manifest.get("schemaVersion") != 1
            or manifest.get("abiSha256") != abi_hash or manifest.get("files") != expected_hashes
            or manifest.get("contractSha256") != hashes["moonhostabi.contract.json"]
            or contract.get("schemaVersion") != 2 or contract.get("abiSha256") != abi_hash
            or contract.get("imports") != [] or contract.get("externrefs") != {}
            or (directory / "adapter.ts").stat().st_size == 0):
        raise ValueError("generated response, manifest, contract, or file hashes do not agree")
    return hashes


def remove_generated_output(directory, parent):
    if not directory.exists():
        return
    if (directory.is_symlink() or directory.resolve().parent != parent.resolve()
            or getattr(directory.lstat(), "st_file_attributes", 0) & 0x400):
        raise ValueError("refusing cleanup outside the owned generation directory")
    children = list(directory.iterdir())
    if any(child.name not in GENERATED_FILES or not child.is_file() or child.is_symlink()
           for child in children):
        raise ValueError("refusing cleanup of unexpected generation contents")
    for child in children:
        child.unlink()
    directory.rmdir()


def validate_resource_lock(path, export_count):
    document = json.loads(path.read_text(encoding="utf-8"))
    abi = document.get("abi", {})
    memories = abi.get("memories", [])
    if (document.get("lockfileVersion") != 4 or abi.get("schemaVersion") != 4
            or len(memories) != export_count
            or {entry.get("name") for entry in memories}
            != {f"memory{index:06d}" for index in range(export_count)}):
        raise ValueError("resource lock must preserve all generated memory export names")
    for entry in memories:
        if entry.get("minimumPages") != 0 or entry.get("maximumPages") != 1:
            raise ValueError("resource lock lost generated memory bounds")


def resolve_validator(explicit):
    if explicit:
        candidate = Path(explicit).resolve()
        if candidate.is_file():
            return candidate
        raise ValueError(f"wasm-tools not found: {candidate}")
    installed = shutil.which("wasm-tools")
    if installed:
        return Path(installed).resolve()
    bundled = list((Path(__file__).resolve().parent.parent / ".tools" / "wasm-tools").glob(
        "**/wasm-tools.exe" if os.name == "nt" else "**/wasm-tools"))
    if len(bundled) == 1:
        return bundled[0].resolve()
    raise ValueError("independent validation requires --wasm-tools-path or wasm-tools on PATH")


def validate_output_directory(directory):
    allowed = (Path(__file__).resolve().parent.parent / "_build", Path(tempfile.gettempdir()))
    if not any(directory.is_relative_to(root.resolve()) and directory != root.resolve()
               for root in allowed):
        raise ValueError("output directory must be a child of repository _build or system temp")


def run_benchmark(args):
    cli = Path(args.cli_path).resolve(strict=True)
    if not cli.is_file():
        raise ValueError("--cli-path must point to the already-built native executable")
    baseline_path = getattr(args, "baseline_cli_path", None)
    baseline_cli = Path(baseline_path).resolve(strict=True) if baseline_path else None
    if baseline_cli is not None and not baseline_cli.is_file():
        raise ValueError("--baseline-cli-path must point to an already-built native executable")
    validator = resolve_validator(args.wasm_tools_path)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    output = (Path(args.output_directory).resolve() if args.output_directory else
              Path(__file__).resolve().parent.parent / "_build" / "benchmarks" / stamp)
    validate_output_directory(output)
    output.mkdir(parents=True, exist_ok=False)
    cases = corpus_cases()
    manifest = write_corpus(output / "corpus", cases)
    cli_hash = sha256(cli.read_bytes())
    baseline_hash = sha256(baseline_cli.read_bytes()) if baseline_cli else None
    version, _, _ = invoke([str(cli), "--version"], args.timeout_seconds)
    validator_version, _, _ = invoke([str(validator), "--version"], args.timeout_seconds)
    report = {
        "schemaVersion": 1, "suiteVersion": 2, "status": "running", "startedAtUtc": stamp,
        "cli": {"path": str(cli), "sha256": cli_hash, "version": version.strip()},
        "environment": {"os": platform.platform(), "machine": platform.machine(),
                        "processor": platform.processor(), "logicalCpuCount": os.cpu_count(),
                        "python": platform.python_version()},
        "methodology": {"warmups": args.warmups, "samples": args.samples,
                        "timeoutSeconds": args.timeout_seconds,
                        "timing": "wall clock per native CLI process, including startup and pipe capture",
                        "percentile": "nearest rank: sorted[ceil(0.95 * sampleCount) - 1]",
                        "memoryMeasurement": "Windows OS PeakWorkingSetSize per process; unavailable platforms/errors are null with reason",
                        "memoryAggregation": "maximum available OS peak among measured samples; warmups excluded"},
        "independentValidator": {"path": str(validator), "version": validator_version.strip(),
                                 "sha256": sha256(validator.read_bytes())},
        "corpus": manifest, "cases": [],
    }
    if baseline_cli:
        baseline_version, _, _ = invoke([str(baseline_cli), "--version"], args.timeout_seconds)
        report["baselineCli"] = {"path": str(baseline_cli), "sha256": baseline_hash,
                                 "version": baseline_version.strip()}
        report["methodology"]["comparison"] = (
            "paired native processes; baseline/candidate then candidate/baseline on alternating iterations; "
            "warmups participate in ordering but not statistics; identical shared artifact, lock, and contract; "
            "responses and generated file bytes must match across both executables")
    work = [(case, output / "corpus" / entry["file"], entry)
            for case, entry in zip(cases, manifest["cases"])]
    for case, artifact, entry in list(work):
        if case.name in ("exports-512", "resources-128"):
            work.append((case, artifact, dict(entry, name="generate-" + case.name,
                                             operation="generate-resource-aware", sourceCorpusCase=case.name)))
    if args.artifact_path:
        artifact = Path(args.artifact_path).resolve(strict=True)
        artifact_data = artifact.read_bytes()
        entry = {"name": "real-artifact", "axis": "realArtifact", "value": None,
                 "operation": "inspect", "file": str(artifact), "byteLength": len(artifact_data),
                 "sha256": sha256(artifact_data), "source": "user-supplied compiled artifact"}
        work.append((None, artifact, entry))
        report["realArtifact"] = entry
    result_path = output / "results.json"
    try:
        selected = getattr(args, "case", None)
        if selected:
            unknown = set(selected) - {entry["name"] for _, _, entry in work}
            if unknown:
                raise ValueError(f"unknown benchmark case(s): {', '.join(sorted(unknown))}")
            work = [item for item in work if item[2]["name"] in selected]
            report["selectedCases"] = list(selected)
        # Validate every byte stream before starting any timed workload.
        for artifact in dict.fromkeys(artifact for _, artifact, _ in work):
            invoke([str(validator), "validate", str(artifact)], args.timeout_seconds)
        for case_index, (case, artifact, entry) in enumerate(work):
            generation = entry["operation"] == "generate-resource-aware"
            contract_hash = None
            lock_hash = None
            setup_cli = baseline_cli or cli
            if generation:
                contract = output / (case.name + ".contract.json")
                invoke([str(setup_cli), "resource-contract", str(artifact), "--out", str(contract)],
                       args.timeout_seconds)
                resource_contract = json.loads(contract.read_text(encoding="utf-8"))
                expected_memories = case.value if case.axis == "memoryExports" else 0
                if (resource_contract.get("schemaVersion") != 5
                        or len(resource_contract.get("memories", [])) != expected_memories
                        or any(resource_contract.get(field) != []
                               for field in ("tables", "globals", "tags", "unsupported"))):
                    raise ValueError("resource contract does not match generation corpus")
                contract_hash = sha256(contract.read_bytes())
                arguments = ["generate", str(artifact), "--resource-contract", str(contract)]
                generated_parent = output / "generated"
                generated_parent.mkdir(exist_ok=True)
            elif case is not None and case.operation == "resource-verify":
                lock = output / (case.name + ".lock.json")
                invoke([str(setup_cli), "resource-lock-v4", str(artifact), "--out", str(lock)],
                       args.timeout_seconds)
                validate_resource_lock(lock, case.value)
                lock_hash = sha256(lock.read_bytes())
                arguments = ["resource-verify", str(artifact), "--against", str(lock), "--format", "json"]
                validate = validate_resource
            else:
                arguments = ["inspect", str(artifact), "--format", "json"]
                count = (case.value if case.axis == "functionExports" else 1) if case else None
                validate = lambda stdout, count=count: validate_inspect(stdout, count)
            binaries = {"candidate": cli}
            if baseline_cli:
                binaries["baseline"] = baseline_cli
            measurements = {side: {"sampleMs": [], "memorySamples": [], "runs": [],
                                   "responseSha256": None} for side in binaries}
            pairs = []
            for iteration in range(args.warmups + args.samples):
                order = (["baseline", "candidate"] if iteration % 2 == 0 else ["candidate", "baseline"]) \
                    if baseline_cli else ["candidate"]
                durations = {}
                for side in order:
                    measured = measurements[side]
                    if generation:
                        # Leave room for the CLI's sibling staging suffix on Windows.
                        generated = generated_parent / f"g{case_index:02d}-{iteration:04d}{side[0]}"
                        if generated.exists():
                            raise ValueError(f"generation output already exists: {generated}")
                        command = [str(binaries[side]), *arguments, "--out", str(generated)]
                        try:
                            stdout, elapsed, memory = invoke(command, args.timeout_seconds)
                            current_files = validate_generated(generated, stdout)
                            if ("generatedFileSha256" in measured
                                    and current_files != measured["generatedFileSha256"]):
                                raise ValueError(f"non-deterministic generated files for {entry['name']} ({side})")
                            measured["generatedFileSha256"] = current_files
                        finally:
                            # Exact known child/files only; validation and cleanup are outside the timer.
                            remove_generated_output(generated, generated_parent)
                    else:
                        command = [str(binaries[side]), *arguments]
                        stdout, elapsed, memory = invoke(command, args.timeout_seconds)
                        validate(stdout)
                    current_hash = sha256(stdout.encode("utf-8"))
                    if measured["responseSha256"] is not None and current_hash != measured["responseSha256"]:
                        raise ValueError(f"non-deterministic response for {entry['name']} ({side})")
                    measured["responseSha256"] = current_hash
                    measured["runs"].append({"iteration": iteration,
                                             "phase": "warmup" if iteration < args.warmups else "sample",
                                             "argv": command})
                    durations[side] = elapsed
                    if iteration >= args.warmups:
                        measured["sampleMs"].append(elapsed)
                        measured["memorySamples"].append(memory)
                if baseline_cli:
                    for field in ("responseSha256", "generatedFileSha256") if generation else ("responseSha256",):
                        if measurements["candidate"][field] != measurements["baseline"][field]:
                            raise ValueError(f"{field} differs between baseline and candidate for {entry['name']}")
                    if iteration >= args.warmups:
                        delta = durations["candidate"] - durations["baseline"]
                        pairs.append({"iteration": iteration, "order": order,
                                      "baselineMs": durations["baseline"], "candidateMs": durations["candidate"],
                                      "deltaMs": delta, "changePercent": 100 * delta / durations["baseline"]})
            if sha256(artifact.read_bytes()) != entry["sha256"]:
                raise ValueError(f"artifact changed during measurement: {artifact}")
            if generation and sha256(contract.read_bytes()) != contract_hash:
                raise ValueError("resource contract changed during measurement")
            if lock_hash is not None and sha256(lock.read_bytes()) != lock_hash:
                raise ValueError("resource lock changed during measurement")
            recorded_arguments = arguments + ["--out", "<fresh generated child per iteration>"] if generation else arguments
            for measured in measurements.values():
                peaks = [sample["peakMemoryBytes"] for sample in measured["memorySamples"]
                         if sample["peakMemoryBytes"] is not None]
                measured.update(arguments=recorded_arguments, expectedExitCode=0,
                                peakMemoryBytes=max(peaks) if peaks else None,
                                memorySamplesAvailable=len(peaks), **summarize(measured["sampleMs"]))
                if generation:
                    measured["resourceContractSha256"] = contract_hash
                if lock_hash is not None:
                    measured["resourceLockSha256"] = lock_hash
            result = dict(entry, **measurements["candidate"])
            if baseline_cli:
                result["baseline"] = measurements["baseline"]
                result["comparison"] = {"pairs": pairs,
                                        "medianPairedDeltaMs": statistics.median(pair["deltaMs"] for pair in pairs),
                                        "medianPairedChangePercent": statistics.median(pair["changePercent"] for pair in pairs)}
            report["cases"].append(result)
            print(f"{entry['name']}: median={result['medianMs']:.3f}ms "
                  f"P95={result['p95Ms']:.3f}ms", flush=True)
        if sha256(cli.read_bytes()) != cli_hash:
            raise ValueError("CLI executable changed during measurement")
        if baseline_cli and sha256(baseline_cli.read_bytes()) != baseline_hash:
            raise ValueError("baseline CLI executable changed during measurement")
        report["status"] = "complete"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        write_json(result_path, report)
        print(f"BENCHMARK_RESULTS={result_path}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    generate = subparsers.add_parser("generate")
    generate.add_argument("--output-directory", required=True)
    run = subparsers.add_parser("run")
    run.add_argument("--cli-path", required=True)
    run.add_argument("--baseline-cli-path")
    run.add_argument("--case", action="append", help="run only a named workload; repeat to select multiple")
    run.add_argument("--wasm-tools-path")
    run.add_argument("--artifact-path")
    run.add_argument("--output-directory")
    run.add_argument("--warmups", type=int, default=3)
    run.add_argument("--samples", type=int, default=20)
    run.add_argument("--timeout-seconds", type=float, default=30)
    args = parser.parse_args()
    try:
        if args.command == "generate":
            directory = Path(args.output_directory).resolve()
            validate_output_directory(directory)
            print(json.dumps(write_corpus(directory, corpus_cases()), indent=2))
        else:
            if args.warmups < 0 or args.samples < 1 or not 0 < args.timeout_seconds <= 30:
                parser.error("warmups >= 0, samples >= 1, and 0 < timeout-seconds <= 30 are required")
            run_benchmark(args)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"benchmark failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
