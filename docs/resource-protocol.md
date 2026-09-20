# Lock resources and generate a checked adapter

This workflow is available from the current source checkout and is not included
in the published `0717lee/moonhostabi@0.4.1` package. It gives memory, table,
global, and exception-tag boundaries their own lock, contract, comparison
report, and generated runtime checks. The function-only `verify` report and
default `generate` path keep their existing behavior.

## Create a lock and contract from the fixture

Run these commands from the repository root in PowerShell 7, after the
[development setup](../README.md#development-setup). Use a fresh temporary
directory so the lock and contract have an existing parent and the generated
adapter has a new output path:

```powershell
$resourceRun = Join-Path ([IO.Path]::GetTempPath()) ('moonhostabi-resource-demo-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resourceRun | Out-Null
moon run cmd/moonhostabi --target native resource-lock-v4 fixtures/artifacts/resources.wasm --out "$resourceRun/resources.lock.json"
moon run cmd/moonhostabi --target native resource-contract fixtures/artifacts/resources.wasm --out "$resourceRun/resources.contract.json"
moon run cmd/moonhostabi --target native generate fixtures/artifacts/resources.wasm --resource-contract "$resourceRun/resources.contract.json" --out "$resourceRun/generated"
moon run cmd/moonhostabi --target native resource-verify fixtures/artifacts/resources.wasm --against "$resourceRun/resources.lock.json" --format json
```

All four commands should exit `0`. The fixture defines an exported memory with
limits of 1–3 pages, an `externref` table with limits of 2–4 elements, a mutable
`i32` global, and a tag taking one `i32`. Its source is
[`resources.wat`](../fixtures/wat/resources.wat).

The last command emits this report:

```json
{
  "schemaVersion": 1,
  "classification": "compatible",
  "compatible": true,
  "exitCode": 0,
  "changes": []
}
```

Generation writes `adapter.ts`, `moonhostabi.contract.json`, and
`moonhostabi.manifest.json`. The generated `moonhostabi.contract.json` remains the
function contract; retain the separate `resources.contract.json` as the resource
input for regeneration. The adapter embeds its resource checks and artifact
fingerprint. Use a fresh directory for each generation: `--update` refuses
resource-aware outputs, and `--resource-contract` does not accept `--update`.

## Compare changed declarations and renumbered types

The resource gate conservatively treats every known resource-field change as
breaking. Run the changed fixture against the lock above:

```powershell
moon run cmd/moonhostabi --target native resource-verify fixtures/artifacts/resources-changed.wasm --against "$resourceRun/resources.lock.json" --format json
$LASTEXITCODE # 2
moon run cmd/moonhostabi --target native resource-verify fixtures/artifacts/resources-changed.wasm --against "$resourceRun/resources.lock.json" --format markdown
$LASTEXITCODE # 2
```

This reports changes to the memory and table limits, global mutability, and tag
parameters. Use `--format text` for plain text or `--format markdown` for a
review table; both use the same classification and exit code as JSON.

The reindexed fixture inserts an unrelated function type before the tag type.
Its raw type index changes, but its resolved tag signature does not:

```powershell
moon run cmd/moonhostabi --target native resource-verify fixtures/artifacts/resources-reindexed.wasm --against "$resourceRun/resources.lock.json" --format json
$LASTEXITCODE # 0
```

Resource compatibility compares declarations, not artifact hashes. The lock
retains the original artifact SHA-256 as provenance. Generated adapters have a
stricter runtime requirement: they accept only the exact bytes used for
generation. Regenerate the adapter for `resources-reindexed.wasm` before running
it, even though the comparison above passes.

## Read the versioned files and report

The resource versions are independent of the function lock and contract:

| Document             | Version              | Key evidence                                              |
| -------------------- | -------------------- | --------------------------------------------------------- |
| `ResourceSurfaceV4`  | `schemaVersion: 4`   | Resource declarations and resolved tag `params`/`results` |
| `ResourceLockfileV4` | `lockfileVersion: 4` | `schemaSha256`, `artifactSha256`, `abiSha256`, and `abi`  |
| `ResourceContractV5` | `schemaVersion: 5`   | `abiSha256` and matching resource arrays                  |
| Resource comparison  | `schemaVersion: 1`   | `classification`, `compatible`, `exitCode`, and `changes` |

Surfaces and contracts contain `memories`, `tables`, `globals`, `tags`, and
`unsupported` arrays. Each resource has a `path`, `module`, and `name`; `module`
is `null` for an export. Paths quote names, for example
`imports["env"]["memory"]` and `exports["memory"]`, preserving quotes,
backslashes, and newlines in names.

| Kind   | Declaration fields                                                   |
| ------ | -------------------------------------------------------------------- |
| Memory | `minimumPages`, `maximumPages`, `shared`, `memory64`, `pageSizeLog2` |
| Table  | `elementType`, `minimumElements`, `maximumElements`, `table64`       |
| Global | `valueType`, `mutable`                                               |
| Tag    | `params`, `results`                                                  |

The projection builds index spaces from both imports and module definitions, so
exported definitions and re-exported imports resolve to their actual types.
Unexported definitions do not become host boundaries. Memory flags, including
sharedness, are read from the artifact because the pinned parser's module model
does not retain all of them. Tags store resolved signatures instead of raw type
indices. Missing type evidence is recorded as unsupported, never guessed.

The pinned parser loses nullability for some exception and bottom reference
types. Those artifact types produce `unknown` compatibility rather than a
guessed signature. Very large table32 limits can also be rejected by the
parser's current numeric representation. An unsupported result is not proof of
compatibility, even when the same artifact is checked twice.

Each `changes` entry contains `path`, `before`, `after`, `classification`, and
`recommendation`. `before` and `after` are strings containing JSON values, or
JSON `null` when the field is absent. For example, a tag parameter change has
`before: "[\"i32\"]"` and `after: "[\"i64\"]"`; a page-count change has
`before: "1"` and `after: "2"`. The string `"null"` represents an explicit
JSON-null field value, such as an absent maximum limit, while bare `null` means
the field itself was not present on that side. Parse the non-null string once
more if a consumer needs its underlying JSON value.

| Resource verification exit | Meaning                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `0`                        | `compatible`: a known, unchanged resource surface             |
| `2`                        | `breaking`: one or more resource fields changed               |
| `3`                        | Unknown compatibility, invalid input, or unsupported metadata |

Unknown evidence takes precedence over breaking changes. A readable but
unsupported surface yields an `unknown` comparison report; malformed files can
fail during decoding before a comparison report is available. Invalid or
mismatched resource contracts and unsupported adapter generation also exit `3`.
These codes belong to the resource workflow; the aggregate function `verify`
command retains its [existing exit-code contract](../README.md#cli-surface).

## Migrate legacy resource files

`resource-lock-v3` retains its existing JSON structure. `resource-verify` accepts
both v3 and v4 resource locks and normalizes known legacy type spellings. A v3
tag contains only `typeIndex`, so it cannot establish the tag's signature. Even
an unchanged artifact therefore returns `unknown`, exit `3`, when its v3
baseline has tags:

```powershell
moon run cmd/moonhostabi --target native resource-lock-v3 fixtures/artifacts/resources.wasm --out "$resourceRun/resources-v3.lock.json"
moon run cmd/moonhostabi --target native resource-verify fixtures/artifacts/resources.wasm --against "$resourceRun/resources-v3.lock.json" --format json
$LASTEXITCODE # 3
```

Create a new v4 lock from the original baseline artifact and review it; changing
a version number in the old file cannot recover the missing signature. Unknown
legacy descriptors likewise require complete evidence before compatibility can
be accepted.

`generate --resource-contract` accepts v5 contracts and can lift a legacy v4
contract only when it contains no tags or unresolved type evidence. The lifted
contract must still match the artifact's complete resource surface. For new
work, create v5 with `resource-contract`. Missing signature fields, stale
fingerprints, or resource declarations that differ from the artifact fail
closed.

## Provide host resources to the generated adapter

The imported-resource fixture includes all four resource kinds, re-exports
them, and defines additional exported resources. Generate its adapter separately:

```powershell
moon run cmd/moonhostabi --target native resource-contract fixtures/artifacts/resources-imports.wasm --out "$resourceRun/imports.contract.json"
moon run cmd/moonhostabi --target native generate fixtures/artifacts/resources-imports.wasm --resource-contract "$resourceRun/imports.contract.json" --out "$resourceRun/generated-imports"
```

After compiling the generated TypeScript in your host project, supply the
resources through its typed import object. For example, the following host
function accepts the bytes of `resources-imports.wasm`:

```ts
import {
  instantiate,
  type HostImportsWithResources,
} from "./generated-imports/adapter.js";

export async function run(bytes: ArrayBuffer) {
  const imports: HostImportsWithResources = {
    env: {
      memory: new WebAssembly.Memory({ initial: 1, maximum: 3 }),
      table: new WebAssembly.Table({
        element: "externref",
        initial: 2,
        maximum: 4,
      }),
      global: new WebAssembly.Global({ value: "i32", mutable: true }, 11),
      tag: new WebAssembly.Tag({ parameters: ["i32"] }),
    },
  };
  const exports = await instantiate(bytes, imports);
  exports.write_host_global(27);
  console.assert(imports.env.global.value === 27);
  console.assert(exports.imported_memory === imports.env.memory);
  return exports;
}
```

`instantiate` and `instantiateWithResources` are equivalent. They copy and hash
the supplied bytes, snapshot required imports, validate function imports and
resource bindings, instantiate the application module, and then check exports.
Resource checks use small Wasm modules with one import and no code or start
function. These probes ask the engine to check actual types and import-compatible
limits, including table element types, global mutability, and tag signatures;
they do not rely on JavaScript reflection or caller-supplied guard callbacks.
Wrong artifact bytes and invalid imports fail before the application module's
start function can execute. Runtime resource mismatches throw
`MHA_ADAPTER_MISMATCH`.

The runtime requires Web Crypto `crypto.subtle` for SHA-256. Use Node.js 24, or a
browser in a secure context with the needed Wasm features and Web Crypto. Pass
artifact bytes (`BufferSource`), not a precompiled `WebAssembly.Module`.

## Stay within the generated adapter's supported types

| Resource | Generated adapter support                                                  |
| -------- | -------------------------------------------------------------------------- |
| Memory   | Non-shared memory32 with 65,536-byte pages                                 |
| Table    | Table32 with `funcref` or `externref` elements                             |
| Global   | `i32`, `i64`, `f32`, `f64`, or `externref`; declared mutability is checked |
| Tag      | Parameters using `i32`, `i64`, `f32`, `f64`, or `externref`; no results    |

Analysis and locking can describe a wider surface, including shared memory
flags. That does not make those resources representable by this generator.
Shared memory, memory64, table64, custom page sizes, typed GC references, `v128`,
and unresolved signatures do not gain adapter support from a contract. A
successfully written contract can still be rejected by generation if its known
types are outside the supported subset.

## Run the resource end-to-end check

With Node.js 24, the configured MoonBit toolchain, and `wasm-tools` available, run:

```powershell
npm --prefix runtime ci
pwsh -NoProfile -File scripts/verify-resources.ps1
```

The script rebuilds the resource fixtures from WAT and checks their bytes,
parses real CLI JSON, verifies changed and reindexed surfaces, compiles adapters
with strict TypeScript, and exercises real resources in Node.js. It also rejects
missing or incorrectly typed imports, mismatched artifact bytes, and invalid
contracts. Success ends with `MOONHOSTABI_RESOURCE_E2E_STATUS=GO`.
