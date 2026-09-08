# Changelog

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
