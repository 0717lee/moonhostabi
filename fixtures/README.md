# MoonHostABI fixture corpus

This corpus is authored specifically for MoonHostABI. It does not reuse source or binaries from PixelForge or another submission.

| Fixture | Purpose | Expected public surface |
|---|---|---|
| `scalar` | Scalar code generation and runtime smoke test | `add(i32,i32)->i32`, `answer()->i64` |
| `externref` | Opaque host-object import plus one-artifact runtime demo | import `host.echo(externref)->externref`; exports `roundtrip` and `add` |
| `recursive` | Real MoonBit compiler Wasm-GC output | exports `new_node` and `node_value` over a recursive `Node` |
| `breaking_v1` | Compatibility baseline | `add(i32,i32)->i32` |
| `breaking_v2` | Seeded breaking candidate | `add(i32)->i32` |
| `rec-a` / `rec-reindexed` | Independent WAT type-index invariance pair | equivalent `node-null` recursive ABI |

Rebuild the compiler fixtures and recursive-type Oracle printouts from the repository root:

```powershell
pwsh -NoProfile -File scripts/build-fixtures.ps1
```

The script requires `moon 0.1.20260827` / `moonc 0.10.11+6ff76a5f9` and the
pinned `wasm-tools 1.258.0`; it refuses other versions. On Windows it discovers
the checksum-verified executable under `.tools/wasm-tools`; CI may provide the
same version on `PATH`. Outputs are staged and structurally validated before
the committed artifacts and Oracle files are replaced. Per-run build data is
removed unless `-KeepBuild` is supplied for diagnosis.

## Resource boundary corpus

The `resources*.wat` fixtures cover all four resource kinds, imported resource
re-exports, individual table/global/tag changes, type-index renumbering, and
escaped export names. `resources-imports-start-changed` has the same resource
surface but a start function with a visible side effect; the generated adapter
must reject these unexpected bytes before executing that function.

Run `pwsh -NoProfile -File scripts/verify-resources.ps1` to rebuild these WAT
files in a temporary directory, validate them with `wasm-tools`, and compare
their bytes with the committed `resources*.wasm` files. The gate also compiles
freshly generated adapters with strict TypeScript and runs real Node resource
and rejection tests. It does not overwrite the committed fixtures.
