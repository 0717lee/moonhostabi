"""Offline standard-library selftests for the registry consumer gate."""

import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "package_consumer", Path(__file__).with_name("verify-package-consumer.py")
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def archive(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as output:
        for name, payload in entries:
            if isinstance(name, str):
                # ZipInfo normalizes backslashes on Windows. Preserve malicious
                # names to exercise archives authored on another operating system.
                original = name
                name = zipfile.ZipInfo(name)
                name.filename = original
            output.writestr(name, payload)
    return buffer.getvalue()


class ArchiveTests(unittest.TestCase):
    def test_verified_archive_preserves_source_bytes(self):
        entries = [("moon.mod", b'name = "test/module"\nversion = "1.0.0"'),
                   ("src/a.mbt", b"// source\n")]
        data = archive(entries)
        self.assertEqual(gate.checked_archive(data, gate.sha256(data)), dict(entries))

    def test_checksum_mismatch_is_rejected_before_zip_parse(self):
        with self.assertRaisesRegex(gate.GateError, "SHA-256 mismatch"):
            gate.checked_archive(b"not a ZIP", "0" * 64)

    def test_path_traversal_and_windows_aliases_are_rejected(self):
        for path in ("../outside", "/absolute", "a/../../outside", "C:/outside", "a\\b",
                     "a//b", "a/./b", "NUL.txt", "a/file.", "a/file ", "a:stream"):
            with self.subTest(path=path):
                data = archive([(path, b"bad")])
                with self.assertRaisesRegex(gate.GateError, "unsafe"):
                    gate.checked_archive(data, gate.sha256(data))

    def test_case_collisions_are_rejected(self):
        data = archive([("A.mbt", b"a"), ("a.mbt", b"b")])
        with self.assertRaisesRegex(gate.GateError, "duplicate"):
            gate.checked_archive(data, gate.sha256(data))

    def test_file_directory_collision_is_rejected(self):
        data = archive([("src", b"file"), ("src/a.mbt", b"source")])
        with self.assertRaisesRegex(gate.GateError, "collision"):
            gate.checked_archive(data, gate.sha256(data))

    def test_symlinks_are_rejected(self):
        member = zipfile.ZipInfo("link")
        member.create_system = 3
        member.external_attr = (stat.S_IFLNK | 0o777) << 16
        data = archive([(member, b"../../outside")])
        with self.assertRaisesRegex(gate.GateError, "unsafe"):
            gate.checked_archive(data, gate.sha256(data))

    def test_expansion_budget_is_enforced(self):
        data = archive([("a", b"12345"), ("b", b"67890")])
        with patch.object(gate, "MAX_UNPACKED_BYTES", 9):
            with self.assertRaisesRegex(gate.GateError, "expansion"):
                gate.checked_archive(data, gate.sha256(data))

    def test_manifest_does_not_treat_commented_imports_as_dependencies(self):
        data = b'// import { "ignored/module@1.0.0" }\nname = "a/b"\nversion = "1.0.0"\nimport { "real/module@2.0.0", }'
        self.assertEqual(gate.manifest({"moon.mod": data})["deps"], {"real/module": "2.0.0"})

    def test_path_override_manifest_is_rejected(self):
        data = json.dumps({"name": "a/b", "version": "1.0.0", "deps": {"x/y": {"path": "../y"}}}).encode()
        with self.assertRaisesRegex(gate.GateError, "path/git"):
            gate.manifest({"moon.mod.json": data})


class RegistryTests(unittest.TestCase):
    def test_exact_route_serves_verified_bytes_and_records_fetch(self):
        data = archive([("moon.mod", b"name = \"a/b\"")])
        route = gate.archive_route("a/b", "1.0.0")
        events = []
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with gate.registry_server({route: data}, events) as url:
            with opener.open(url + route, timeout=5) as response:
                self.assertEqual(response.read(), data)
        self.assertEqual(events, [{"method": "GET", "path": "/user/a%2Fb%2F1.0.0.zip",
                                  "status": 200, "bytes": len(data), "sha256": gate.sha256(data)}])

    def test_unknown_encoded_traversal_and_proxy_urls_are_denied(self):
        events = []
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        route = gate.archive_route("a/b", "1.0.0")
        with gate.registry_server({route: b"zip"}, events) as url:
            for path in ("/", "/user/other.zip", "/../secret", "/%2e%2e/secret",
                         route + "?forward=https://example.com", "/https://example.com"):
                with self.subTest(path=path):
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        opener.open(url + path, timeout=5)
                    self.assertEqual(caught.exception.code, 404)
            with self.assertRaises(urllib.error.HTTPError) as caught:
                opener.open(urllib.request.Request(url + route, method="POST", data=b"data"), timeout=5)
            self.assertEqual(caught.exception.code, 501)
        self.assertEqual(len(events), 6)
        self.assertTrue(all(event["status"] == 404 for event in events))

    def test_fetch_worker_rejects_nonallowlisted_url_without_network(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(urllib.request, "build_opener", side_effect=AssertionError("network")):
                with self.assertRaisesRegex(gate.GateError, "allowlist"):
                    gate.fetch_worker("https://example.com/package.zip", Path(temp) / "out")


class IsolationAndEvidenceTests(unittest.TestCase):
    def test_environment_is_copied_and_overrides_scrubbed(self):
        original = {"PATH": "tools", "MOON_HOME": "user-home", "MOONCAKES_REGISTRY": "remote",
                    "MOON_CORE_OVERRIDE": "patched", "MOON_DEP_CACHE": "global",
                    "moon_build_cache": "other", "GIT_DIR": "project/.git"}
        before = original.copy()
        env = gate.isolated_env(original, Path("fresh"), Path("toolchain"))
        self.assertEqual(original, before)
        self.assertEqual(env["MOON_HOME"], "fresh")
        self.assertEqual(env["MOON_TOOLCHAIN_ROOT"], "toolchain")
        self.assertEqual(env["PATH"], "tools")
        for key in ("MOONCAKES_REGISTRY", "MOON_CORE_OVERRIDE", "MOON_DEP_CACHE", "moon_build_cache", "GIT_DIR"):
            self.assertNotIn(key, env)

    def test_fresh_config_has_only_registry_and_index(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            existing = root / "user-config.json"
            existing.write_bytes(b"keep existing user config")
            config = gate.registry_config(root / "fresh", root / "index with spaces", "http://127.0.0.1:12345")
            self.assertEqual(set(config), {"registry", "index"})
            self.assertEqual(config["index"], (root / "index with spaces").resolve().as_uri())
            self.assertEqual(json.loads((root / "fresh/config.json").read_text()), config)
            self.assertEqual(existing.read_bytes(), b"keep existing user config")
            with self.assertRaises(FileExistsError):
                gate.registry_config(root / "fresh", root / "index", "http://127.0.0.1:12345")

    def test_source_hashes_detect_mutation_and_additional_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            expected = {"main.mbt": b"original\n", "moon.mod": b"manifest"}
            for name, content in expected.items():
                (root / name).write_bytes(content)
            before = gate.snapshot(root, expected)
            self.assertEqual(before["main.mbt"], gate.sha256(b"original\n"))
            (root / "main.mbt").write_bytes(b"patched\n")
            with self.assertRaisesRegex(gate.GateError, "differ from archive"):
                gate.snapshot(root, expected)
            (root / "main.mbt").write_bytes(expected["main.mbt"])
            (root / "extra.mbt").write_bytes(b"unexpected")
            with self.assertRaisesRegex(gate.GateError, "source set changed"):
                gate.snapshot(root, expected)

    def test_plan_rejects_sources_outside_consumer(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            consumer = root / "consumer"
            consumer.mkdir()
            outside = root / "outside.mbt"
            outside.write_bytes(b"source")
            with self.assertRaisesRegex(gate.GateError, "outside fresh consumer"):
                gate.source_plan(f'moonc check "{outside}"', consumer, {})

    def test_plan_requires_each_registry_dependency(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "main.mbt"
            source.write_bytes(b"source")
            with self.assertRaisesRegex(gate.GateError, "does not prove"):
                gate.source_plan(f'moonc check "{source}"', root, {"a/b": root / "dependency"})

    def test_cleanup_refuses_unowned_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "keep").write_bytes(b"safe")
            with self.assertRaisesRegex(gate.GateError, "refusing cleanup"):
                gate.cleanup_owned(root, "not-owned")
            self.assertEqual((root / "keep").read_bytes(), b"safe")

    def test_command_timeout_is_reported_and_process_stopped(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            report = {"steps": []}
            with self.assertRaisesRegex(gate.GateError, "failed"):
                gate.run_process([sys.executable, "-c", "import time; time.sleep(60)"],
                                 root, dict(os.environ), 1, report, root, "timeout")
            self.assertTrue(report["steps"][0]["timed_out"])
            self.assertNotEqual(report["steps"][0]["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()
