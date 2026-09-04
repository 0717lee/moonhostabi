# MoonHostABI

Artifact-first MoonBit Wasm-GC Host ABI lock, adapter, and validation toolchain.

MoonHostABI projects a runtime-facing ABI from compiled MoonBit Wasm-GC,
canonicalizes recursive types independently of raw indices, detects breaking
host-contract drift, and emits a strict TypeScript/ESM adapter. The current
proof-grade Spike is **local GO**; see [the validation evidence](docs/validation.md)
for hashes, the compatibility matrix, runtime observations, limits, and the
unverified remote-CI boundary.

## Reproduce the Spike

Prerequisites are PowerShell 7, MoonBit `0.1.20260819`, Node.js `24.12.0` with
npm `11.6.2`, and `wasm-tools 1.258.0`. The command below installs locked npm
dependencies and the pinned Playwright Chromium build as part of the gate:

```powershell
pwsh -NoProfile -File scripts/verify-spike.ps1
```

Success ends with `MOONHOSTABI_SPIKE_STATUS=GO`.

## CLI surface

Run the native CLI from source:

```powershell
moon run cmd/moonhostabi --target native inspect <artifact.wasm> --format json
moon run cmd/moonhostabi --target native lock <artifact.wasm> --out <lock.json>
moon run cmd/moonhostabi --target native check <artifact.wasm> --against <lock.json>
moon run cmd/moonhostabi --target native generate <artifact.wasm> --out <new-directory>
```

`generate` also accepts `--contract <contract.json>` before `--out`. Generated
defaults throw for user-owned imports; they never invent host business logic.
Unsupported JavaScript boundaries fail closed with structured diagnostics.

## Development setup

MoonHostABI currently carries a minimal, version-checked patch for a
`Milky2018/wasm_core@0.14.0` parser defect exposed by recursive Wasm-GC output
from MoonBit 0.10.9. Apply it after dependency resolution:

```powershell
moon update
pwsh -NoProfile -File scripts/apply-wasm-core-patch.ps1
```

The patch only teaches the upstream parser to resolve self-references in an
implicit singleton recursive type. It is kept separate from MoonHostABI's own
ABI logic so it can be removed when an upstream release contains the fix.
