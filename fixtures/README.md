# MoonHostABI fixture corpus

This corpus is authored specifically for MoonHostABI. It does not reuse source or binaries from PixelForge or another submission.

| Fixture | Purpose | Expected public surface |
|---|---|---|
| `scalar` | Scalar code generation and runtime smoke test | `add(i32,i32)->i32`, `answer()->i64` |
| `externref` | Opaque host-object import and identity round-trip | import `host.echo(externref)->externref`, export `roundtrip` |
| `recursive` | Real MoonBit compiler Wasm-GC output | exports `new_node` and `node_value` over a recursive `Node` |
| `breaking_v1` | Compatibility baseline | `add(i32,i32)->i32` |
| `breaking_v2` | Seeded breaking candidate | `add(i32)->i32` |
| `rec-a` / `rec-reindexed` | Independent WAT type-index invariance pair | equivalent `node-null` recursive ABI |

Rebuild every artifact and Oracle printout from the repository root:

```powershell
pwsh -NoProfile -File scripts/build-fixtures.ps1
```

The script requires MoonBit and the pinned `wasm-tools 1.258.0`. On Windows it discovers the checksum-verified executable under `.tools/wasm-tools`; CI may provide the same version on `PATH`.
