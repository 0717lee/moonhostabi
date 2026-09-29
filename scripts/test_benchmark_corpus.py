"""Deterministic corpus and runner checks; no third-party dependencies."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import benchmark_corpus as benchmark


def read_unsigned(data, offset):
    value = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7
        if shift >= 35:
            raise ValueError("invalid u32")


def read_sections(data):
    if data[:8] != b"\0asm\x01\0\0\0":
        raise ValueError("invalid header")
    sections = []
    offset = 8
    while offset < len(data):
        section_id = data[offset]
        size, offset = read_unsigned(data, offset + 1)
        payload = data[offset:offset + size]
        if len(payload) != size:
            raise ValueError("truncated section")
        sections.append((section_id, payload))
        offset += size
    return sections


class CorpusTests(unittest.TestCase):
    def test_unsigned_boundaries(self):
        for number, encoded in [(0, b"\0"), (127, b"\x7f"), (128, b"\x80\x01"),
                                (65536, b"\x80\x80\x04")]:
            self.assertEqual(benchmark.uleb(number), encoded)
        for invalid in [-1, 2 ** 32]:
            with self.assertRaises(ValueError):
                benchmark.uleb(invalid)

    def test_corpus_is_reproducible_with_independent_dimensions(self):
        cases = benchmark.corpus_cases()
        self.assertEqual(len(cases), 14)
        self.assertEqual([(case.name, case.data) for case in cases],
                         [(case.name, case.data) for case in benchmark.corpus_cases()])
        self.assertEqual(len({case.name for case in cases}), len(cases))
        for case in cases:
            with self.subTest(case=case.name):
                sections = dict(read_sections(case.data))
                if case.axis == "customPayloadBytes":
                    name_size, start = read_unsigned(sections[0], 0)
                    self.assertEqual(len(sections[0]) - start - name_size, case.value)
                    self.assertEqual(read_unsigned(sections[7], 0)[0], 1)
                elif case.axis == "functionExports":
                    self.assertEqual(read_unsigned(sections[7], 0)[0], case.value)
                    self.assertEqual(sections[3], b"\x01\x00")
                    self.assertEqual(sections[10], b"\x01\x02\x00\x0b")
                elif case.axis == "distinctTypes":
                    count, offset = read_unsigned(sections[1], 0)
                    signatures = []
                    parameter_count = 0
                    for _ in range(count):
                        self.assertEqual(sections[1][offset], 0x60)
                        count_params, start = read_unsigned(sections[1], offset + 1)
                        end = start + count_params
                        signatures.append(sections[1][start:end])
                        parameter_count += count_params
                        count_results, offset = read_unsigned(sections[1], end)
                        self.assertEqual(count_results, 0)
                    self.assertEqual(count, case.value)
                    self.assertEqual(len(set(signatures)), count)
                    self.assertEqual(offset, len(sections[1]))
                    self.assertLess(parameter_count + count, 65536)
                    self.assertEqual(sections[10], b"\x01\x02\x00\x0b")
                else:
                    self.assertEqual(case.axis, "memoryExports")
                    self.assertEqual(sections[5], b"\x01\x01\x00\x01")
                    self.assertEqual(read_unsigned(sections[7], 0)[0], case.value)
                    self.assertEqual(case.operation, "resource-verify")

    def test_manifest_records_exact_bytes_and_stable_identity(self):
        cases = benchmark.corpus_cases()
        with tempfile.TemporaryDirectory() as directory:
            first = benchmark.write_corpus(Path(directory), cases)
            second = benchmark.write_corpus(Path(directory), cases)
            self.assertEqual(first, second)
            self.assertEqual(first["corpusSha256"],
                             "95e68e4c437828c6065827e8d1dd3286783116cf691a8b92b4bbeb83a188e43e")
            for entry in first["cases"]:
                content = (Path(directory) / entry["file"]).read_bytes()
                self.assertEqual(entry["byteLength"], len(content))
                self.assertEqual(entry["sha256"], hashlib.sha256(content).hexdigest())
            stored = json.loads((Path(directory) / "manifest.json").read_text())
            self.assertEqual(stored, first)


class ResultTests(unittest.TestCase):
    def test_median_and_p95_use_documented_nearest_rank(self):
        result = benchmark.summarize(list(range(1, 21)))
        self.assertEqual(result["medianMs"], 10.5)
        self.assertEqual(result["p95Ms"], 19)
        self.assertEqual(benchmark.summarize([4])["p95Ms"], 4)

    def test_inspect_validates_export_count_and_signature(self):
        expected = {"schemaVersion": 1, "imports": [], "exports": [
            {"module": None, "name": "f000000", "params": [], "results": []}],
            "types": [], "features": []}
        benchmark.validate_inspect(json.dumps(expected), 1)
        expected["exports"][0]["params"] = ["i32"]
        with self.assertRaises(ValueError):
            benchmark.validate_inspect(json.dumps(expected), 1)
        with self.assertRaises(ValueError):
            benchmark.validate_inspect("{}", 1)

    def test_resource_report_must_be_unchanged_and_compatible(self):
        valid = {"schemaVersion": 1, "classification": "compatible", "exitCode": 0,
                 "compatible": True, "changes": []}
        benchmark.validate_resource(json.dumps(valid))
        for key, value in [("changes", [{}]), ("compatible", False),
                           ("classification", "unknown"), ("exitCode", 3)]:
            invalid = dict(valid, **{key: value})
            with self.subTest(key=key), self.assertRaises(ValueError):
                benchmark.validate_resource(json.dumps(invalid))

    def test_resource_lock_rejects_missing_export_and_changed_limits(self):
        document = {"lockfileVersion": 4, "abi": {"schemaVersion": 4, "memories": [
            {"name": "memory000000", "minimumPages": 0, "maximumPages": 1}]}}
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "lock.json"
            lock.write_text(json.dumps(document), encoding="utf-8")
            benchmark.validate_resource_lock(lock, 1)
            with self.assertRaises(ValueError):
                benchmark.validate_resource_lock(lock, 2)
            document["abi"]["memories"][0]["maximumPages"] = 2
            lock.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(ValueError):
                benchmark.validate_resource_lock(lock, 1)

    def test_process_exit_and_stderr_fail_closed(self):
        stdout, elapsed, memory = benchmark.invoke([sys.executable, "-c", "print('ok')"], 5)
        self.assertEqual(stdout.strip(), "ok")
        self.assertGreater(elapsed, 0)
        self.assertIn("peakMemoryBytes", memory)
        for program in ("raise SystemExit(7)", "import sys; print('error', file=sys.stderr)"):
            with self.subTest(program=program), self.assertRaises(RuntimeError):
                benchmark.invoke([sys.executable, "-c", program], 5)

    def test_process_timeout_is_bounded(self):
        started = time.monotonic()
        with self.assertRaisesRegex(RuntimeError, "was killed"):
            benchmark.invoke([sys.executable, "-c", "import time; time.sleep(10)"], 0.1)
        self.assertLess(time.monotonic() - started, 5)

    @unittest.skipUnless(os.name == "nt", "Windows process counters required")
    def test_windows_peak_memory_observes_known_allocation(self):
        _, _, memory = benchmark.invoke(
            [sys.executable, "-c", "allocation = bytearray(32 * 1024 * 1024)"], 5)
        self.assertEqual(memory["method"], "GetProcessMemoryInfo.PeakWorkingSetSize")
        self.assertIsNone(memory["reason"])
        self.assertGreaterEqual(memory["peakMemoryBytes"], 32 * 1024 * 1024)

    @unittest.skipUnless(os.name == "nt", "Windows process counters required")
    def test_windows_counter_failure_is_null_with_reason(self):
        with mock.patch.object(benchmark.ctypes, "WinDLL", side_effect=OSError("counter unavailable")):
            observation = benchmark.process_peak_memory(object())
        self.assertIsNone(observation["peakMemoryBytes"])
        self.assertEqual(observation["reason"], "counter unavailable")

    def test_generated_bundle_checks_contract_file_set_and_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "iteration-0"
            output.mkdir()
            abi_hash = "a" * 64
            adapter = output / "adapter.ts"
            adapter.write_text("export const result = 1;\n", encoding="utf-8")
            contract = output / "moonhostabi.contract.json"
            contract.write_text(json.dumps({"schemaVersion": 2, "abiSha256": abi_hash,
                                            "externrefs": {}, "imports": []}), encoding="utf-8")
            hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (adapter, contract)}
            manifest = {"schemaVersion": 1, "abiSha256": abi_hash,
                        "contractSha256": hashes[contract.name], "files": hashes}
            (output / "moonhostabi.manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            response = json.dumps({"abiSha256": abi_hash,
                                   "files": sorted(path.name for path in output.iterdir())})
            first = benchmark.validate_generated(output, response)
            self.assertEqual(first, benchmark.validate_generated(output, response))
            adapter.write_text("changed", encoding="utf-8")
            with self.assertRaises(ValueError):
                benchmark.validate_generated(output, response)
            adapter.write_text("export const result = 1;\n", encoding="utf-8")
            unexpected = output / "unexpected.txt"
            unexpected.write_text("unexpected", encoding="utf-8")
            with self.assertRaises(ValueError):
                benchmark.validate_generated(output, response)
            with self.assertRaises(ValueError):
                benchmark.remove_generated_output(output, Path(directory))
            unexpected.unlink()
            benchmark.remove_generated_output(output, Path(directory))
            self.assertFalse(output.exists())

    def test_report_preserves_each_executed_warmup_and_sample_argv(self):
        executed = []
        case = benchmark.Case("exports-512", "functionExports", 512,
                              benchmark.function_module(export_count=512))
        memory = {"peakMemoryBytes": None, "method": "test", "reason": "test double"}

        def record_invocation(command, timeout):
            executed.append(list(command))
            operation = command[1]
            if operation == "inspect":
                document = {"schemaVersion": 1, "imports": [], "types": [], "features": [],
                            "exports": [{"module": None, "name": f"f{index:06d}",
                                         "params": [], "results": []} for index in range(512)]}
            elif operation == "resource-contract":
                document = {"schemaVersion": 5, "memories": [], "tables": [],
                            "globals": [], "tags": [], "unsupported": []}
                benchmark.write_json(Path(command[-1]), document)
            elif operation == "generate":
                output = Path(command[-1])
                output.mkdir()
                abi_hash = "b" * 64
                (output / "adapter.ts").write_text("export {};\n", encoding="utf-8")
                benchmark.write_json(output / "moonhostabi.contract.json",
                                     {"schemaVersion": 2, "abiSha256": abi_hash,
                                      "externrefs": {}, "imports": []})
                hashes = {path.name: benchmark.sha256(path.read_bytes()) for path in output.iterdir()}
                benchmark.write_json(output / "moonhostabi.manifest.json",
                                     {"schemaVersion": 1, "abiSha256": abi_hash,
                                      "contractSha256": hashes["moonhostabi.contract.json"], "files": hashes})
                document = {"abiSha256": abi_hash, "files": sorted(benchmark.GENERATED_FILES)}
            else:
                return "test version" if operation == "--version" else "", 1.0, memory
            return json.dumps(document), 1.0, memory

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "results with spaces"
            args = argparse.Namespace(cli_path=sys.executable, wasm_tools_path=sys.executable,
                                      output_directory=str(output), artifact_path=None,
                                      warmups=1, samples=2, timeout_seconds=5)
            with mock.patch.object(benchmark, "corpus_cases", return_value=[case]), \
                    mock.patch.object(benchmark, "invoke", side_effect=record_invocation), \
                    mock.patch("builtins.print"):
                benchmark.run_benchmark(args)
            report = json.loads((output / "results.json").read_text(encoding="utf-8"))
            recorded = [run for result in report["cases"] for run in result["runs"]]
            workloads = [command for command in executed if command[1] in ("inspect", "generate")]
            self.assertEqual([run["argv"] for run in recorded], workloads)
            self.assertEqual([run["phase"] for run in recorded],
                             ["warmup", "sample", "sample"] * 2)
            self.assertEqual([run["iteration"] for run in recorded], [0, 1, 2] * 2)
            generated_paths = [Path(command[-1]) for command in workloads if command[1] == "generate"]
            self.assertEqual(len(set(generated_paths)), 3)
            self.assertTrue(all(path.is_absolute() and not path.exists() for path in generated_paths))


class PairedBenchmarkTests(unittest.TestCase):
    def run_pair(self, directory, mismatch=None, mutate_baseline=False, resource_case=False,
                 selected=None):
        root = Path(directory)
        candidate = root / "candidate.exe"
        baseline = root / "baseline.exe"
        candidate.write_bytes(b"candidate executable")
        baseline.write_bytes(b"baseline executable")
        case = benchmark.Case("exports-512", "functionExports", 512,
                              benchmark.function_module(export_count=512))
        if resource_case:
            case = benchmark.Case("resources-512", "memoryExports", 512,
                                  benchmark.memory_module(512), "resource-verify")
        executed = []
        memory = {"peakMemoryBytes": 4096, "method": "test", "reason": None}

        def invoke(command, timeout):
            executed.append(list(command))
            operation = command[1]
            is_baseline = Path(command[0]) == baseline
            if operation == "inspect":
                document = {"schemaVersion": 1, "imports": [], "types": [], "features": [],
                            "exports": [{"module": None, "name": f"f{index:06d}",
                                         "params": [], "results": []} for index in range(512)]}
                if mismatch == "response" and is_baseline:
                    document["extra"] = "different valid output"
            elif operation == "resource-contract":
                document = {"schemaVersion": 5, "memories": [], "tables": [],
                            "globals": [], "tags": [], "unsupported": []}
                benchmark.write_json(Path(command[-1]), document)
            elif operation == "resource-lock-v4":
                document = {"lockfileVersion": 4, "abi": {"schemaVersion": 4, "memories": [
                    {"name": f"memory{index:06d}", "minimumPages": 0, "maximumPages": 1}
                    for index in range(512)]}}
                benchmark.write_json(Path(command[-1]), document)
            elif operation == "resource-verify":
                document = {"schemaVersion": 1, "classification": "compatible", "exitCode": 0,
                            "compatible": True, "changes": []}
            elif operation == "generate":
                output = Path(command[-1])
                output.mkdir()
                abi_hash = "b" * 64
                adapter = "export const changed = 1;\n" if mismatch == "files" and is_baseline else "export {};\n"
                (output / "adapter.ts").write_text(adapter, encoding="utf-8")
                benchmark.write_json(output / "moonhostabi.contract.json",
                                     {"schemaVersion": 2, "abiSha256": abi_hash,
                                      "externrefs": {}, "imports": []})
                hashes = {path.name: benchmark.sha256(path.read_bytes()) for path in output.iterdir()}
                benchmark.write_json(output / "moonhostabi.manifest.json",
                                     {"schemaVersion": 1, "abiSha256": abi_hash,
                                      "contractSha256": hashes["moonhostabi.contract.json"], "files": hashes})
                document = {"abiSha256": abi_hash, "files": sorted(benchmark.GENERATED_FILES)}
                if mutate_baseline:
                    baseline.write_bytes(b"changed during measurement")
            else:
                return "test version" if operation == "--version" else "", 1.0, memory
            return json.dumps(document), 2.0 if is_baseline else 1.0, memory

        output = root / "output"
        args = argparse.Namespace(cli_path=str(candidate), baseline_cli_path=str(baseline),
                                  wasm_tools_path=sys.executable, output_directory=str(output),
                                  artifact_path=None, warmups=1, samples=3, timeout_seconds=5,
                                  case=selected)
        with mock.patch.object(benchmark, "corpus_cases", return_value=[case]), \
                mock.patch.object(benchmark, "invoke", side_effect=invoke), \
                mock.patch("builtins.print"):
            benchmark.run_benchmark(args)
        return json.loads((output / "results.json").read_text(encoding="utf-8")), executed

    def test_paired_samples_alternate_and_preserve_side_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            report, executed = self.run_pair(directory)
            self.assertEqual(report["baselineCli"]["sha256"], benchmark.sha256(b"baseline executable"))
            self.assertEqual(report["cli"]["sha256"], benchmark.sha256(b"candidate executable"))
            for result in report["cases"]:
                operation = "generate" if result["operation"] == "generate-resource-aware" else "inspect"
                actual = [command for command in executed if command[1] == operation]
                sides = ["baseline" if Path(command[0]).name == "baseline.exe" else "candidate"
                         for command in actual]
                self.assertEqual(sides, ["baseline", "candidate", "candidate", "baseline"] * 2)
                self.assertEqual(result["sampleMs"], [1.0] * 3)
                self.assertEqual(result["baseline"]["sampleMs"], [2.0] * 3)
                self.assertEqual(result["baseline"]["p95Ms"], 2.0)
                self.assertEqual(result["baseline"]["peakMemoryBytes"], 4096)
                self.assertEqual(result["responseSha256"], result["baseline"]["responseSha256"])
                recorded = result["runs"] + result["baseline"]["runs"]
                self.assertCountEqual([run["argv"] for run in recorded], actual)
                pairs = result["comparison"]["pairs"]
                self.assertEqual([pair["order"] for pair in pairs],
                                 [["candidate", "baseline"], ["baseline", "candidate"], ["candidate", "baseline"]])
                self.assertEqual(result["comparison"]["medianPairedDeltaMs"], -1.0)
                self.assertEqual(result["comparison"]["medianPairedChangePercent"], -50.0)
            generated = report["cases"][1]
            self.assertEqual(generated["generatedFileSha256"], generated["baseline"]["generatedFileSha256"])
            paths = [Path(command[-1]) for command in executed if command[1] == "generate"]
            self.assertEqual(len(set(paths)), 8)
            self.assertTrue(all(not path.exists() for path in paths))
            contracts = [command[-1] for command in executed if command[1] == "resource-contract"]
            self.assertEqual(len(contracts), 1)
            self.assertTrue(all(command[command.index("--resource-contract") + 1] == contracts[0]
                                for command in executed if command[1] == "generate"))

    def test_cross_binary_output_mismatch_fails_closed(self):
        for mismatch in ("response", "files"):
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, "between baseline and candidate"):
                    self.run_pair(directory, mismatch=mismatch)
                report = json.loads((Path(directory) / "output" / "results.json").read_text())
                self.assertEqual(report["status"], "failed")

    def test_changed_baseline_binary_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "baseline CLI executable changed"):
                self.run_pair(directory, mutate_baseline=True)

    def test_resource_pair_consumes_one_identical_baseline_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            report, executed = self.run_pair(directory, resource_case=True)
            locks = [command for command in executed if command[1] == "resource-lock-v4"]
            self.assertEqual(len(locks), 1)
            self.assertEqual(Path(locks[0][0]).name, "baseline.exe")
            expected_path = locks[0][-1]
            verifies = [command for command in executed if command[1] == "resource-verify"]
            self.assertEqual(len(verifies), 8)
            self.assertTrue(all(command[command.index("--against") + 1] == expected_path
                                for command in verifies))
            result = report["cases"][0]
            expected_hash = benchmark.sha256(Path(expected_path).read_bytes())
            self.assertEqual(result["resourceLockSha256"], expected_hash)
            self.assertEqual(result["baseline"]["resourceLockSha256"], expected_hash)

    def test_case_filter_selects_only_requested_workload(self):
        with tempfile.TemporaryDirectory() as directory:
            report, executed = self.run_pair(directory, selected=["generate-exports-512"])
            self.assertEqual([result["name"] for result in report["cases"]], ["generate-exports-512"])
            self.assertFalse(any(command[1] == "inspect" for command in executed))
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "unknown benchmark case"):
                self.run_pair(directory, selected=["missing-case"])


class WrapperTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 required")
    def test_relative_paths_follow_powershell_location(self):
        wrapper = Path(__file__).resolve().parent / "benchmark-hostabi.ps1"

        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"

        with tempfile.TemporaryDirectory() as directory:
            process_directory = Path(directory) / "process directory"
            shell_directory = Path(directory) / "PowerShell location"
            process_directory.mkdir()
            shell_directory.mkdir()
            cli = shell_directory / "cli marker.exe"
            cli.write_bytes(b"argument capture only; never executed")
            baseline = shell_directory / "baseline marker.exe"
            baseline.write_bytes(b"baseline argument capture only; never executed")
            command = "\n".join([
                "$ErrorActionPreference = 'Stop'",
                "function Capture-BenchmarkArgs { $args | ConvertTo-Json -Compress; $global:LASTEXITCODE = 0 }",
                f"Set-Location -LiteralPath {quote(shell_directory)}",
                f"[Environment]::CurrentDirectory = {quote(process_directory)}",
                f"& {quote(wrapper)} -CliPath './cli marker.exe' "
                "-BaselineCliPath './baseline marker.exe' -Case resources-512,types-512 "
                "-OutputDirectory './benchmark results' -PythonPath Capture-BenchmarkArgs",
            ])
            completed = subprocess.run([shutil.which("pwsh"), "-NoProfile", "-Command", command],
                                       cwd=process_directory, capture_output=True, text=True,
                                       encoding="utf-8", timeout=10, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            argv = json.loads(completed.stdout)
            self.assertEqual(Path(argv[argv.index("--cli-path") + 1]), cli.resolve())
            self.assertEqual(Path(argv[argv.index("--baseline-cli-path") + 1]), baseline.resolve())
            self.assertEqual([argv[index + 1] for index, value in enumerate(argv) if value == "--case"],
                             ["resources-512", "types-512"])
            self.assertEqual(Path(argv[argv.index("--output-directory") + 1]),
                             shell_directory.resolve() / "benchmark results")


if __name__ == "__main__":
    unittest.main()
