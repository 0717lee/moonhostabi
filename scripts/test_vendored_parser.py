"""Provenance checks reject drift; use isolated copies of real bundled files."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("vendor_check", ROOT / "scripts/verify-vendored-parser.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="moonhostabi-provenance-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for directory in ("src/internal/wasm_parser", "third_party/wasm_core_parser"):
            shutil.copytree(ROOT / directory, self.root / directory)

    def test_real_inventory_passes_with_platform_source_newlines(self):
        source = self.root / "src/internal/wasm_parser/instructions.mbt"
        source.write_bytes(CHECK.normalized(source.read_bytes()).replace(b"\n", b"\r\n"))
        self.assertEqual(CHECK.verify(self.root)["source_files"], 12)

    def test_modified_parser_is_rejected(self):
        source = self.root / "src/internal/wasm_parser/instructions.mbt"
        source.write_bytes(source.read_bytes().replace(b"priv enum ExprFrame", b"enum ExprFrame"))
        with self.assertRaisesRegex(ValueError, "vendored hash mismatch"):
            CHECK.verify(self.root)

    def test_missing_and_unlisted_sources_are_rejected(self):
        source = self.root / "src/internal/wasm_parser/error.mbt"
        data = source.read_bytes()
        source.unlink()
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            CHECK.verify(self.root)
        source.write_bytes(data)
        (source.parent / "unexpected.mbt").write_bytes(b"// unrecorded implementation\n")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            CHECK.verify(self.root)

    def test_altered_license_is_rejected(self):
        license_file = self.root / "third_party/wasm_core_parser/LICENSE"
        license_file.write_bytes(license_file.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "license hash mismatch"):
            CHECK.verify(self.root)


if __name__ == "__main__":
    unittest.main()
