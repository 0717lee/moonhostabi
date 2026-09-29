# Historical parser patches

MoonHostABI `0.6.0` bundles its parser in `src/internal/wasm_parser`.
Both public parsing entrypoints use it. Normal dependency setup is
`moon update` followed by `moon check`; consumers do not patch `.mooncakes`.
The application script has been retired. The two `.patch` files in this
directory are retained as historical diffs and are not applied by source,
package, or CI setup. Version `0.5.1` does not contain this change.

The bundled source's [provenance, modifications, and Apache-2.0 license](../third_party/wasm_core_parser/README.md)
are the current distribution record. It contains 12 production parser source
files and reuses the pinned `wasm_core@0.14.0` types; the parser is adapted
third-party code, distinct from MoonHostABI's own ABI implementation.

Both historical patches modify `Milky2018/wasm_core@0.14.0`, from the
[Milky2018/wasmoon project](https://github.com/Milky2018/wasmoon). The upstream
package declares the Apache-2.0 license; these downstream modifications retain
that license and attribution to the upstream contributors. Original source
headers are preserved.

## `wasm_core-0.14.0-singleton-rec.patch`

MoonBit 0.10.11 emits a self-recursive struct as an implicit singleton recursive
type. The artifact is valid according to `wasm-tools 1.258.0`, but
`Milky2018/wasm_core@0.14.0` resolves the field's typed self-reference before
inserting the current type into its parser table and raises `invalid heap type`.

The patch applies the placeholder strategy already used by `wasm_core` for an
explicit `rec` group to the implicit singleton branch. The bundled parser now
contains this reviewed change; the standalone diff records its history.

The regression is exercised with the compiler-produced
`fixtures/artifacts/recursive.wasm`:

```powershell
moon test src/projector --target native
moon test src/wasm_adapter --target native
```

These tests exercise the bundled parser without changing the dependency cache.

## `wasm_core-0.14.0-iterative-expr.patch`

Structured expressions previously recursed through `read_expr`,
`read_instruction`, and `read_if_then_body`, consuming the native call stack
for each nested block. This patch replaces that recursion with an explicit
heap stack of `Block`, `Loop`, `IfThen`, `IfElse`, and `TryTable` frames. Each
frame retains its parent body, block type, and any then body or catch handlers;
closing a frame appends the complete structured instruction to its parent.

The same `read_expr` entry point serves function bodies, global and table
initializers, element expressions and offsets, and data offsets. Non-control
opcode and immediate parsing remains upstream code, including GC, SIMD, and
atomic instructions. Catch-handler decoding and its errors are unchanged.
An unmatched or repeated `else` still raises `UnknownOpcode(0x05)`; an `end`
closes the current frame, or returns the expression when no frame remains.
Truncated input still raises `UnexpectedEndOfInput`. The unused
`read_if_then_body` and recursive structured cases in `read_instruction` are
removed. This patch retains the full AST and introduces no expression-depth
limit.

## Historical guarded application

Before bundling, the retired application script accepted only version `0.14.0`
and validated both target sources before applying either patch. Each source
had to match its original or patched SHA-256 below. This section records that
earlier setup; it is not an installation step for `0.6.0`.

Hashes use UTF-8 source with CRLF/CR converted to LF. Other whitespace,
including the final newline, is preserved during hashing; the former guard
rejected all other source drift.

| Target under `parser/` | Original SHA-256 | Patched SHA-256 |
| --- | --- | --- |
| `rec_group_types.mbt` | `d2d70401532ce13ed844ce2e70f64702ff6591bd9188848f85b8ea2115807417` | `a835b9e5a47587c4f5d1e6792313f59b2ebfc149156de5b388903007662397d0` |
| `instructions.mbt` | `b80083580f7b12847500c4836ab3f2b6c09494bb87868d249b88e31f148dfcac` | `33cd63aa4a69fc410c9e600cc7e84cee048abc6cd756cfd11aa36232ff0468e8` |

The earlier checked API used a patch-only `parse_module_iterative` entrypoint
as a compile-time guard. The bundled parser now has one internal `parse_module`
entrypoint, shared by raw and checked parsing. The raw public entrypoint raises
the owned `ArtifactError` rather than upstream `ParserError`; see the
[error-type and display migration](../docs/library-api.md#parser-distribution-and-error-migration).

## Upstream status and removal checklist

The historical issue and package probe below refer to the singleton-rec fix.
Both source fixes have since been confirmed upstream; version `0.6.0` keeps the
reviewed `0.14.0` adaptations rather than substituting upstream development code.

Checked on September 20, 2026:

- [Issue #512](https://github.com/Milky2018/wasmoon/issues/512) was closed as
  completed on September 18. Upstream commit
  [`f0b01bd9`](https://github.com/Milky2018/wasmoon/commit/f0b01bd9b23ce6d3d3e36e978df37bc85f5ab980)
  fixes implicit singleton self-references. [PR #519](https://github.com/Milky2018/wasmoon/pull/519)
  merged that fix into `main` on the same day.
- The [Mooncakes manifest for `wasm_core@0.16.0`](https://mooncakes.io/api-new/v0/manifest/Milky2018/wasm_core@0.16.0)
  reports `latest_version: 0.16.0`, published on September 16 at 03:59:19 UTC,
  before the fix. Its package SHA-256 is
  `21a895f3c1298f89c0e6143cf84dd4cd1a1d5b708fb649c36d0da9b4b468b289`.
- An isolated project that downloaded `0.16.0` without applying any downstream
  patch still raised `invalid heap type` for the implicit singleton below.
  The equivalent explicit `rec` wrapper parsed successfully, and the malformed
  mutability control was rejected: two controls passed, one regression failed.
  The published parser still calls `read_subtype()` before registering the
  singleton type.

The minimal valid implicit singleton used in the probe is:

```moonbit
let bytes = b"\x00asm\x01\x00\x00\x00\x01\x06\x01\x5f\x01\x63\x00\x00"
// (module (type (struct (field (ref null 0)))))
```

Checked again on September 29, 2026, upstream
[`main` at `74a02453`](https://github.com/Milky2018/wasmoon/tree/74a02453afefbb5ba9c9476838ac0a0ba349e84a/modules/wasm_core/parser)
contains both singleton and iterative-expression fixes. The latter was added by
[`ff98fb9b`](https://github.com/Milky2018/wasmoon/commit/ff98fb9bd0e732059e7f8a4f151f5739a57e45c7).
The official `0.16.0` archive, with the hash above, contains neither. A manifest
version on the upstream development branch does not identify the same source
as the already published archive.

Bundling removes the consumer patch requirement now. Replacing the internal
parser with a future published dependency is a separate change:

1. Test the published archive in a clean dependency directory.
   Run the singleton probe, malformed-mutability test, real recursive fixtures,
   and type-reindexing compatibility tests.
2. Verify complete AST and malformed-input
   parity across structured instructions and initializer expressions, deep
   nesting on native DEBUG/release, JS and WasmGC, and real artifacts against
   the replacement package.
3. Review the shared `types.Module` identity and the public `ArtifactError`
   contract, including preserved diagnostic payloads and `Show` output. Document
   any migration, then update the dependency and provenance together.
4. Run the full verification, isolated package-consumer, and release-package
   gates before removing the bundled implementation or publishing a new version.
