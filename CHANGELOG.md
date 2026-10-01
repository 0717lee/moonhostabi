# Changelog

## [0.6.1] - Unreleased

### Changed

- Pin the verification and release toolchains to `moonc v0.10.14+7d59c7ec9`
  (`moon` / `moonrun 0.1.20260920`), including platform archive checksums.
- Explicitly export existing public `Eq`, `Debug`, and `Show` methods for
  compatibility with the new compiler's warning checks.
- Remove unused package imports and refresh compiled fixtures and validation
  evidence for the pinned compiler. Function and resource ABI formats are unchanged.

## [0.6.0] - 2026-09-29

### Added

- Separate 2,048-type parsing capacity from the 1,024-type canonicalization
  budget, skipping private type equivalence when the public boundary needs none.
- An internal Apache-2.0 parser adapted from `wasm_core@0.14.0`, including
  singleton-recursive and iterative-expression fixes, source provenance, and
  256-frame depth regression cases.
- A package consumer gate using `moon package`, an isolated local registry, and
  a fresh `MOON_HOME` to exercise real downstream installation and execution.
- Alternating paired benchmarks and a rebuilt large compiler-artifact gate.
- Checked Wasm parsing and verification entrypoints with structural budgets,
  expanded-local and public-signature limits, and explicit policy errors.
- Deterministic scale benchmarks with native process timing, output checks,
  exact executable/corpus identities, and Windows peak working-set observations.
- Chromium resource-adapter tests and a compiled MoonBit pricing consumer that
  checks an ABI upgrade before strict TypeScript/Node host execution.

### Changed

- **Source API migration:** `parse_artifact` raises the project-owned
  `ArtifactError` instead of upstream `ParserError`. Parser diagnostic text is
  retained in `InvalidArtifact(detail)`, whose `Show` output adds
  `invalid artifact: `. Callers must update typed error handling and any
  comparisons of rendered errors; unchanged `types.Module` identity does not
  imply source compatibility for the error API.
- Both raw and checked parsing use the bundled internal parser. Normal
  `moon update` / `moon check` setup no longer applies patches to `.mooncakes`;
  the old diffs remain as history. The pinned `wasm_core@0.14.0` types dependency
  remains in use.
- Bound CLI file reads and generated output sizes; preserve input I/O versus
  limit/decoding diagnostics and avoid copying the entire input payload.
- Reuse a parsed module in resource-aware commands and render/hash the final
  resource adapter once, preserving supported output bytes.
- Execute JS and Wasm-GC library tests in the existing verification gate.
- Remove dead branches, private wrappers, duplicate dependency/browser setup,
  and repeated runner configuration; reuse existing aggregate and heap-type
  helpers while retaining regression assertions and parser provenance checks.

### Notes

- The new default input policies reject some valid large/deep Wasm inputs.
  See [input limits](docs/input-limits.md) for exact budgets and trusted-input
  API boundaries.
- Regenerate adapters into a new directory after upgrading. `--update` requires
  the exact current generator manifest version and cannot update older outputs.
- See the [API migration guide](docs/library-api.md#parser-distribution-and-error-migration)
  before upgrading from `0.5.1`. Historical benchmark and CI results retain
  their original version and commit identities; publication availability is
  listed on [Mooncakes](https://mooncakes.io/docs/0717lee/moonhostabi) and
  [GitHub releases](https://github.com/0717lee/moonhostabi/releases).

## [0.5.1] - 2026-09-27

### Fixed

- Preserve opaque resource JSON semantics, including nested `__proto__` keys,
  when generating caller-guarded TypeScript adapters.
- Publish validated release archives without overwriting a destination created
  after preflight, and track rollback before post-publication checks.
- Keep concurrent `generate --update` failures as structured JSON by checking
  owned directory entries with a quiet, single-pass native scan.

### Changed

- Strengthen canonicalization and invalid-resource regression tests with
  independent expected values, input permutations, and matching fingerprints.
- Remove redundant compilation, JSON parsing, sorting, duplicate CLI coverage,
  and unused private verification plumbing without changing public APIs.

## [0.5.0] - 2026-09-20

### Added

- Resource surface and lockfile v4 with resolved tag parameter/result types,
  imported and exported resource declarations, and re-export handling.
- `resource-lock-v4` and `resource-contract` commands; the latter emits resource
  contract v5 from the compiled artifact.
- Resource comparison report v1 with per-field changes, classifications,
  recommendations, and JSON, text, or Markdown output.
- Artifact-bound resource adapters with typed imports/exports, SHA-256 checks,
  and Wasm type probes for memory, table, global, and tag bindings. Both generated
  instantiation entrypoints run the checks.
- Reproducible resource fixtures and a Node.js/TypeScript E2E gate in
  `scripts/verify-resources.ps1`.

### Changed

- `resource-verify` accepts legacy v3 and new v4 locks. Legacy tag indices and
  unresolved metadata return `unknown` with exit code `3` and require a new lock.
- `generate --resource-contract` validates contract v5 against the artifact;
  legacy v4 contracts can be lifted only when they have no tags or unresolved
  type evidence. Invalid or unsupported resource generation fails closed.
- Resource-aware output directories reject `--update`; regenerate into a fresh
  directory with an explicit resource contract.

### Notes

- Use `0717lee/moonhostabi@0.5.0` for these APIs; they are not included in the
  `0.4.1` package. Check the
  [GitHub releases](https://github.com/0717lee/moonhostabi/releases) and
  [Mooncakes package](https://mooncakes.io/docs/0717lee/moonhostabi) for publication
  status.
- Resource generation supports non-shared memory32 with 65,536-byte pages,
  table32 with `funcref`/`externref` elements, and scalar/`externref` globals and
  tag parameters. Analysis can record more types than generation supports.
- The function-only `verify` report and default generation path keep their
  existing behavior. See the [resource protocol](docs/resource-protocol.md) for
  the separate resource versions and runtime requirements.

## [0.1.1] - 2026-09-07

### Added

- Compiled MoonBit Wasm-GC imports/exports and recursive type projection.
- Canonical ABI lockfiles with stable fingerprints.
- Semantic compatibility reports with stable diagnostics and exit codes.
- Strict TypeScript/ESM adapter and contract manifest generation.
- Deterministic reproduction bundles and platform release package checks.
- Linux/Windows verification, Node/Chromium boundary tests, and a judge demo.

### Notes

- The default JavaScript adapter supports function imports/exports. Unsupported
  tables, memories, globals, tags, typed GC transport, and `v128` values fail
  closed and remain explicit follow-up scope.
- `Milky2018/wasm_core@0.14.0` is pinned with a guarded compatibility patch;
  upstream tracking is in [wasmoon#512](https://github.com/Milky2018/wasmoon/issues/512).

## [0.1.0] - 2026-09-04

Initial public development baseline for the MoonHostABI toolchain.
