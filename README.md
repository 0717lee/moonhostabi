# MoonHostABI

Artifact-first MoonBit Wasm-GC Host ABI lock, adapter, and validation toolchain.

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
