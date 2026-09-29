# Input limits

These policies apply to the checked APIs and CLI in `0.6.0`. They were not part
of `0.5.1`. They deliberately reject some valid but
expensive Wasm modules. They are resource limits, not a WebAssembly validator,
process sandbox, timeout, or proof against every resource-exhaustion input.

## Checked Wasm boundary

`src/wasm_adapter.parse_artifact_checked(bytes)` performs an iterative structural
preflight before the bundled parser constructs its AST. It checks section and
function-body boundaries as well as the following inclusive limits:

| Budget | Maximum |
| --- | ---: |
| Artifact bytes | 32 MiB |
| Actual types, including members of recursive groups | 2,048 |
| Whole-module types when function ABI canonicalization is required | 1,024 |
| Cumulative declared/vector items | 65,536 |
| Expanded locals per function | 65,536 |
| Expanded locals across the module | 131,072 |
| Instruction opcodes across expressions, including `end` / `else` | 262,144 |
| Nested control constructs within an expression | 256 |
| Expanded public function/tag parameter and result slots | 131,072 |

The signature and canonicalization budgets run **after bounded AST parsing,
before ABI projection**. The signature budget
counts imports and exports, including repeated aliases of one wide signature;
it prevents projection from multiplying a small signature declaration into an
unbounded public surface. It does not claim to prevent the bounded AST's own
allocation. Structural scanning follows the bundled parser's supported
encodings, based on `wasm_core@0.14.0`; it does not extend its feature support.

`ArtifactError::LimitExceeded` identifies a policy rejection;
`ArtifactError::InvalidArtifact` identifies structural/parser failures.
Native debug testing exposed stack exhaustion in the old recursive dependency
parser at depth 128. The bundled iterative-expression parser uses explicit heap
frames and retains the complete AST. Both public parser entrypoints call this
internal implementation; its fixes are distributed in the MoonHostABI package
without consumer cache edits. The depth regression cases cover 256 levels of
block, loop, if/else and try_table, with depth 257 rejected before AST
construction. See the
[parser source and license](../third_party/wasm_core_parser/README.md).

For function roots without indexed references or supertypes, no canonical type
ID or GC definition can be emitted. The projector skips whole-module type
equivalence in that case. Indexed references, supertypes and invalid roots
conservatively retain the existing algorithm and its 1,024-type budget. This
admits larger internal type tables without multiplying the quadratic work limit.

Use checked entrypoints for artifact processing:

- `parse_artifact_checked` for parsing, then projection of the returned module.
- `verify_artifact_checked` for verification. It rejects oversized bytes before
  hashing them, then retains the existing report format for bounded inputs.
- `project_resource_artifact` for artifact-derived resource surfaces; this
  high-level entrypoint now uses checked parsing.

The `parse_artifact` entrypoint is still an unbounded low-level parser for
trusted, caller-budgeted bytes. It now raises `ArtifactError` instead of
upstream `ParserError`: `InvalidArtifact(detail)` retains the parser message,
while `Show` adds `invalid artifact: ` before it. This is an intentional
error-type and display migration in `0.6.0`; see the
[library API guide](library-api.md#parser-distribution-and-error-migration).
The report-only `verify_artifact`
now uses checked parsing but still hashes the supplied bytes first to retain
complete report provenance. Use its new checked variant when an early byte
limit matters. Library callers own the allocation of their input `Bytes` and
the limits on JSON or model values passed to other low-level APIs.

`project_resource_artifact_from_module(bytes, module)` avoids a second full
parse within one operation. It trusts that the caller supplies the exact
unmodified module parsed from those same bytes. It does not authenticate that
pair; prefer `project_resource_artifact(bytes)` at an external-input boundary.

## Native CLI files and diagnostics

The CLI reads a size-bounded payload from one open file handle. It rejects
short reads, observed growth, and read errors rather than returning truncated
data. Successful reads transfer the payload without making a second full copy.
POSIX inputs must be regular files; named pipes are not a supported input.

- Artifact and ordinary document files: at most 32 MiB before allocation.
- Generation ownership manifest: at most 64 KiB.
- Existing schema-specific JSON decoder limits still apply afterward.
- Files written by the CLI: at most 8 MiB each; normalized generated function
  contracts: at most 1 MiB, matching their decoder's limit conservatively.

File-size rejection uses `MHA_INPUT_TOO_LARGE`; structural budget rejection
uses `MHA_INPUT_LIMIT`. Both have CLI exit code `3`. I/O and malformed-input
diagnostics remain distinct. An oversized file fails on stderr before a report
is built; bounded `verify` parse failures still appear in its canonical report.
Output policy rejection uses `MHA_OUTPUT_LIMIT`; generation staging is cleaned
without publishing partial output. Output limits apply before file creation,
not before the generator constructs its in-memory strings.

## Remaining operational boundary

Run untrusted artifacts in an isolated process with OS CPU, memory and wall-time
limits. Type canonicalization can still perform quadratic work within the type
budget; complex recursive type graphs and all hostile file-system races have
not been exhaustively tested. A bounded file can still require substantially
more memory than its byte size. No service-level latency or memory guarantee is
made. The [benchmark method](performance.md) records representative observations,
not such a guarantee.

The 693,081-byte MoonBit test probe contains 1,644 types and 256 nested control
levels. It now passes checked parsing and retains the old projected ABI and
capability diagnostics. The source gate rebuilds and validates a large compiler
artifact rather than checking in the binary. File size alone is still not a
predictor of acceptance: more than 2,048 types, or more than 1,024 when full
canonicalization is required, remain explicit policy rejections. Evaluate the
deployment corpus; this is not unrestricted large-application support.
