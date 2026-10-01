<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Provenance for the Milky2018/wasmoon parser vendored by MoonHostABI. -->

# Vendored wasm_core parser

`src/internal/wasm_parser` contains the 12 production parser source files from
`Milky2018/wasm_core@0.14.0`, with the reviewed singleton-reference and iterative
expression fixes. It is an internal MoonHostABI implementation package, not a
supported API for consumers. The single module entrypoint is `parse_module`.

The parser returns the existing `Milky2018/wasm_core/types.Module` type from the
pinned **0.14.0** dependency. Its only package imports are
`Milky2018/wasm_core/types` and `moonbitlang/core/debug`. The original
`ParserError` variants, diagnostic messages and Show extensions are retained;
the error type now belongs to this internal package.

## Source and license

- Upstream project: [Milky2018/wasmoon](https://github.com/Milky2018/wasmoon).
- Original archive: [wasm_core 0.14.0](https://download.mooncakes.io/user/Milky2018%2Fwasm_core%2F0.14.0.zip).
- Verified archive SHA-256:
  `3de253ae7c9889566363a0f8615d2ad6763f60c355f7a33059261ee020421c2a`.
- [LICENSE](LICENSE) is a byte-for-byte copy of the Apache-2.0 license from
  [upstream commit 74a02453](https://raw.githubusercontent.com/Milky2018/wasmoon/74a02453afefbb5ba9c9476838ac0a0ba349e84a/LICENSE).
  The package archive contains neither a LICENSE nor a NOTICE file.
- [provenance.json](provenance.json) records every original source path, original,
  reviewed and vendored hash, exact modifications, and pinned upstream references.

All 12 source files and `moon.pkg` carry SPDX/provenance comments. Existing
upstream headers remain beneath those comments. The two files with implementation
changes carry prominent modification notices at the top.

The source list is `basic_types.mbt`, `elem_segment.mbt`, `error.mbt`,
`func_type_vec.mbt`, `instructions.mbt`, `leb128.mbt`,
`rec_group_types.mbt`, `sections.mbt`, `state.mbt`,
`table_memory_types.mbt`, `trait_extensions.mbt` and `value_types.mbt`.
The comments-only `parser.mbt`, upstream tests and generated `.mbti` are
excluded. No encoder, WAT, validator or types implementation is copied.

## Local modifications

The package manifest also removes the debug import that moonc 0.10.14 reports
as unused. Its changed body and hash are recorded separately from the sources.

1. **`rec_group_types.mbt`**: in the implicit singleton branch, pre-scan the
   composite kind without resolving references, reserve a placeholder in the type
   table, parse the subtype, then replace that reserved slot. This permits typed
   self-references and preserves the existing explicit-rec-group behavior.
2. **`instructions.mbt`**: replace recursive structured-expression parsing with
   an `ExprFrame` stack for block, loop, if/else and try_table. Frames retain
   parent bodies, block types, then bodies and catch handlers, reconstructing the
   complete AST without a parser depth limit. Remove `read_if_then_body` and
   the recursive structured cases in `read_instruction`. Non-control opcodes,
   immediates, catch-handler decoding and diagnostics retain their reviewed
   behavior. Unmatched/repeated else raises `UnknownOpcode(0x05)`, end closes
   the current frame or expression, and truncation raises
   `UnexpectedEndOfInput`.
   Ref.null heaptypes use the shared nullable resolver, preserving the existing
   abstract and typed AST constructors and invalid-heap-type diagnostics.
3. Remove the reviewed cache's `parse_module_iterative` capability wrapper;
   retain the original `parse_module` in `sections.mbt`. Keep the implementation-only
   `ExprFrame` enum private so first-party warning checks pass.
4. Add license/provenance comments and normalize CRLF/CR to LF. The other ten
   production source bodies and both package imports are unchanged.

The reviewed source hashes identify the exact fixed cache input. The original
hashes identify the unmodified archive members; vendored hashes include the new
comments and wrapper removal. Hash normalization decodes UTF-8, converts CRLF
and CR to LF, and preserves all other whitespace and final newlines. Archive
and LICENSE hashes instead cover the raw downloaded bytes.

## Upstream source references and publication

- [f0b01bd9](https://github.com/Milky2018/wasmoon/commit/f0b01bd9b23ce6d3d3e36e978df37bc85f5ab980),
  committed September 18, 2026 at 05:39:08 UTC, fixes singleton self-references.
  It refactors both rec-group branches; this vendor retains the narrower
  reviewed 0.14.0 singleton-branch patch.
- [ff98fb9b](https://github.com/Milky2018/wasmoon/commit/ff98fb9bd0e732059e7f8a4f151f5739a57e45c7),
  committed September 18, 2026 at 06:32:57 UTC, introduces iterative expression
  frames upstream. This is a source reference; the vendored implementation is
  the reviewed local 0.14.0 `ExprFrame` version with inline catch decoding.

On September 29, 2026, the [Mooncakes manifest](https://mooncakes.io/api-new/v0/manifest/Milky2018/wasm_core@0.16.0)
lists 0.16.0 as latest, published September 16 at 03:59:19 UTC, before both
source fixes. No later published replacement is listed. The dependency remains
0.14.0; these source commits do not establish availability in a published package.

## Verify provenance

Run this from the repository root. It verifies the original archive, all source
and manifest hashes, the two changed source bodies, and the pinned LICENSE copy.

```powershell
@'
import hashlib, io, json, pathlib, urllib.request, zipfile
p = json.loads(pathlib.Path("third_party/wasm_core_parser/provenance.json").read_text(encoding="utf-8"))
def digest(data):
    return hashlib.sha256(data).hexdigest()
def normalize(data):
    return data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
u = p["upstream"]
archive = urllib.request.urlopen(u["archive_url"], timeout=45).read()
assert digest(archive) == u["archive_sha256"]
z = zipfile.ZipFile(io.BytesIO(archive))
changed = []
for f in p["source_files"] + [p["package_manifest"]]:
    original = normalize(z.read(f["source_path"]))
    vendored = normalize(pathlib.Path(f["vendored_path"]).read_bytes())
    assert digest(original) == f["original_normalized_sha256"], f["source_path"]
    assert digest(vendored) == f["vendored_sha256"], f["vendored_path"]
    body = vendored.split(b"\n\n", 1)[1]
    if "implementation_changed_from_archive" in f:
        assert (body != original) == f["implementation_changed_from_archive"]
        if body != original and f["source_path"].endswith(".mbt"):
            changed.append(f["source_path"])
    else:
        assert body == original
assert changed == p["implementation_changed_files"]
license_bytes = urllib.request.urlopen(u["license_source_url"], timeout=45).read()
assert digest(license_bytes) == u["license_sha256"]
assert pathlib.Path(u["license_vendored_path"]).read_bytes() == license_bytes
print("Verified archive, 12 sources, package imports, two changed bodies and LICENSE.")
'@ | python -
```
