"""Check bundled parser inventory, provenance and license without modifying files."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def normalized(data: bytes) -> bytes:
    return data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def verify(root: Path, upstream_archive: Path | None = None) -> dict:
    provenance = json.loads((root / "third_party/wasm_core_parser/provenance.json").read_text(encoding="utf-8"))
    require(provenance["schema_version"] == 1, "unsupported provenance version")
    sources = provenance["source_files"]
    names = [entry["vendored_path"] for entry in sources]
    actual = {p.relative_to(root).as_posix() for p in (root / "src/internal/wasm_parser").glob("*.mbt")}
    require(len(names) == len(set(names)) == 12 and set(names) == actual, "parser source inventory mismatch")
    changed = [entry["source_path"] for entry in sources if entry["implementation_changed_from_archive"]]
    require(changed == provenance["implementation_changed_files"], "modified-file inventory mismatch")
    for entry in sources + [provenance["package_manifest"]]:
        data = normalized((root / entry["vendored_path"]).read_bytes())
        require(digest(data) == entry["vendored_sha256"], f"vendored hash mismatch: {entry['vendored_path']}")
        require(data.startswith(b"// SPDX-License-Identifier: Apache-2.0\n"), "missing source license notice")
    upstream = provenance["upstream"]
    license_bytes = (root / upstream["license_vendored_path"]).read_bytes()
    require(digest(license_bytes) == upstream["license_sha256"], "license hash mismatch")
    if upstream_archive is not None:
        require(digest(upstream_archive.read_bytes()) == upstream["archive_sha256"], "upstream archive hash mismatch")
        with zipfile.ZipFile(upstream_archive) as archive:
            for entry in sources + [provenance["package_manifest"]]:
                original = normalized(archive.read(entry["source_path"]))
                require(digest(original) == entry["original_normalized_sha256"], "original source hash mismatch")
                vendored = normalized((root / entry["vendored_path"]).read_bytes())
                body = vendored.split(b"\n\n", 1)[1]
                require((body != original) == entry.get("implementation_changed_from_archive", False),
                        f"undocumented implementation change: {entry['source_path']}")
    return {"source_files": len(sources), "modified_files": changed,
            "upstream_archive_checked": upstream_archive is not None}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream-archive", type=Path, help="optionally verify original source bodies against the pinned ZIP")
    args = parser.parse_args()
    print(json.dumps(verify(ROOT, args.upstream_archive), sort_keys=True))
    print("VENDORED_PARSER_PROVENANCE=GO")


if __name__ == "__main__":
    main()
