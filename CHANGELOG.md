# Changelog

## [Unreleased]

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

- These changes are source-only and are not included in the published
  `0717lee/moonhostabi@0.4.1` package.
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
