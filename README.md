# MoonHostABI

Artifact-first MoonBit Wasm-GC Host ABI lock, adapter, and validation toolchain.

MoonHostABI projects a runtime-facing ABI from compiled MoonBit Wasm-GC,
canonicalizes recursive types independently of raw indices, detects breaking
host-contract drift, and emits a strict TypeScript/ESM adapter. The proof-grade
Spike is **GO** locally and on the public Linux/Windows CI matrix; see [the
validation evidence](docs/validation.md) for hashes, the compatibility matrix,
runtime observations, and limits.

Published package: `0717lee/moonhostabi@0.5.0` on Mooncakes.

Version `0.5.0` introduces resource surface v4, resource contract v5, and
artifact-bound adapters. Use `0717lee/moonhostabi@0.5.0` for these APIs; the
`0.4.1` package does not include them. See
[release availability and installation](docs/library-api.md).

## Independent scope

MoonHostABI is an artifact-first Wasm-GC host-boundary toolchain. It consumes
compiled Wasm bytes, models recursive GC types and runtime imports/exports,
locks the resulting ABI, and emits a typed TypeScript adapter plus reproducible
evidence. It is deliberately separate from source-level `.mbti` public-API
diff tools: those tools compare MoonBit declarations, while MoonHostABI checks the
binary host contract that a JavaScript or native embedding must satisfy.

## Judge quickstart

MoonHostABI makes a compiled MoonBit Wasm-GC artifact's host-facing ABI
reviewable before host code is shipped: one lock, one canonical report, and
one deterministic reproduction bundle provide the evidence trail. From a clean
repository root, run the three focused checks below and look for their exact
`GO` markers. The full walkthrough is [the judge quickstart](docs/quickstart.md).

| Check | Command | Expected marker |
| --- | --- | --- |
| CLI evidence | `pwsh -NoProfile -File scripts/verify-command.ps1` | `MOONHOSTABI_VERIFY_STATUS=GO` |
| Reproduction bundle | `pwsh -NoProfile -File scripts/verify-reproduction-bundle.ps1` | `MOONHOSTABI_BUNDLE_STATUS=GO` |
| Platform package | `pwsh -NoProfile -File scripts/verify-release-packaging.ps1` | `MOONHOSTABI_PACKAGE_STATUS=GO` |

The package check is locally observed on Windows, while the public Verification
matrix exercises the native CLI path on both Linux and Windows. Release archive
aggregation remains a separate dispatch-only dry run documented below.

For a short end-to-end presentation, run the [judge demo](docs/judge-demo.md):
it inspects a compiled artifact, creates a lockfile, verifies a contract, and
generates the TypeScript adapter in one temporary run.

The project's relationship to nearby MoonBit tooling and its planned ecosystem
integration points are recorded in [the ecosystem note](docs/ecosystem.md).

Release history is in [CHANGELOG.md](CHANGELOG.md); contribution and local gate
instructions are in [CONTRIBUTING.md](CONTRIBUTING.md).

The native CLI is the recommended integration point; reusable library packages
can be checked for supported MoonBit targets. The generated `adapter.ts` is the
JavaScript/TypeScript host boundary. See the [library API guide](docs/library-api.md)
before importing packages from a downstream module.

## Reproduce the Spike

Prerequisites are PowerShell 7, a MoonBit toolchain reporting `moon
0.1.20260827` / `moonc v0.10.11+6ff76a5f9` / `moonrun 0.1.20260827`, Node.js
`24.12.0` with npm `11.6.2`, and `wasm-tools 1.258.0`. CI obtains that
toolchain from the official installer snapshot `0.10.11+6ff76a5f9`; the
snapshot selector is distinct from the reported `moon` version. The command
below installs locked npm dependencies and the pinned Playwright Chromium
build as part of the gate:

```powershell
pwsh -NoProfile -File scripts/verify-spike.ps1
```

Success ends with `MOONHOSTABI_SPIKE_STATUS=GO`.

## CLI surface

Run the native CLI from source:

```powershell
moon run cmd/moonhostabi --target native inspect <artifact.wasm> --format json
moon run cmd/moonhostabi --target native lock <artifact.wasm> --out <lock.json>
moon run cmd/moonhostabi --target native resource-lock <artifact.wasm> --out <resource-lock.json>
moon run cmd/moonhostabi --target native resource-lock-v3 <artifact.wasm> --out <resource-lock-v3.json>
moon run cmd/moonhostabi --target native resource-lock-v4 <artifact.wasm> --out <resource-lock-v4.json>
moon run cmd/moonhostabi --target native resource-contract <artifact.wasm> --out <resource-contract.json>
moon run cmd/moonhostabi --target native resource-verify <artifact.wasm> --against <resource-lock-v4.json> --format json
moon run cmd/moonhostabi --target native check <artifact.wasm> --against <lock.json>
moon run cmd/moonhostabi --target native verify <artifact.wasm> --against <lock.json> --format json
moon run cmd/moonhostabi --target native verify <artifact.wasm> --against <lock.json> --contract <contract.json> --format json
moon run cmd/moonhostabi --target native generate <artifact.wasm> --out <new-directory>
moon run cmd/moonhostabi --target native generate <artifact.wasm> --resource-contract <resource-contract.json> --out <new-directory>
moon run cmd/moonhostabi --target native generate <artifact.wasm> --out <owned-directory> --update
moon run cmd/moonhostabi --target native generate <artifact.wasm> --out <new-directory> --dry-run
moon run cmd/moonhostabi --target native -- --help
moon run cmd/moonhostabi --target native -- --version
```

`verify` is the machine-facing release gate. It emits one canonical JSON report
on stdout with `artifact`, `baseline`, `provenance`, `compatibility`, `contract`,
and `generator` sections. It parses and analyzes Wasm bytes but never
instantiates them or runs host behavior. `--contract` is optional and its
absence is reported explicitly as `notProvided`; generator representability is
still checked against a deterministic draft contract.

The stable verification exit codes are:

| Exit | Meaning |
| --- | --- |
| `0` | compatible and representable |
| `1` | invalid CLI usage |
| `2` | breaking ABI |
| `3` | invalid artifact/baseline or unsupported/unknown compatibility |
| `4` | invalid contract or adapter/generator mismatch |
| `5` | unexpected runtime failure |

For combined findings, an invalid artifact/baseline or unknown compatibility
takes precedence, followed by a contract or generator mismatch, then a
breaking ABI.

Readable but invalid lockfiles, contracts, and artifacts are represented in the
canonical report. Missing or unreadable paths remain I/O errors on stderr.
Option order is intentionally strict; use `--help` as the authoritative grammar.
The real-process verification suite, including paths containing Chinese
characters and spaces, can be run independently:

```powershell
pwsh -NoProfile -File scripts/verify-command.ps1
```

`generate` also accepts `--contract <contract.json>` before `--out`. Generated
defaults throw for user-owned imports; they never invent host business logic.
Unsupported JavaScript boundaries fail closed with structured diagnostics. A
successful fresh generation publishes `adapter.ts`,
`moonhostabi.contract.json`, and canonical `moonhostabi.manifest.json`
together from a unique sibling staging directory without replacing an existing
path.

Resource-aware generation is opt-in. `resource-lock-v4` captures imported and
exported memory, table, global, and tag declarations, including resources defined
in the module and re-exported imports. Tags use resolved parameter/result types
so a raw type-index change alone does not break compatibility.
`resource-contract` writes contract v5 from the artifact; `generate
--resource-contract` requires that contract to match the artifact's resource
surface. Both generated `instantiate(bytes, imports)` and
`instantiateWithResources(bytes, imports)` check the artifact SHA-256 and real
host resource types before instantiating the application module.

`resource-verify` accepts v3 or v4 locks and JSON, text, or Markdown output. It
returns `0` for an unchanged known surface, `2` for a resource change, and `3`
when compatibility is unknown or inputs are invalid. A legacy v3 tag stores only
a type index, so even the same artifact requires a new v4 lock before its tag
compatibility can be accepted. Invalid or mismatched resource contracts and
unsupported generation also return `3`.

Generated resource adapters currently support non-shared memory32 with
65,536-byte pages, table32 with `funcref` or `externref` elements, and globals
and tag parameters using scalar types or `externref`. Analysis can record a
wider surface than generation supports. The runtime requires Web Crypto
`crypto.subtle` (Node.js 24 or a supporting browser in a secure context); any
artifact byte change requires a new adapter. See the
[resource protocol walkthrough](docs/resource-protocol.md) for fixtures,
version migration, the report schema, and runtime checks.

Run the source resource gate after installing the locked runtime dependencies:

```powershell
npm --prefix runtime ci
pwsh -NoProfile -File scripts/verify-resources.ps1
```

Success ends with `MOONHOSTABI_RESOURCE_E2E_STATUS=GO`.

`--dry-run` performs parsing, contract validation, and generation without
creating filesystem output. `--update` reuses the existing contract and only
replaces a real, non-link directory whose manifest, exact file set, and SHA-256
values prove MoonHostABI ownership. The directory is atomically claimed and its
exact byte snapshot is revalidated before publication. Edited, missing,
unknown, concurrently replaced, symbolic-link, and reparse-point outputs are
refused. There is no `--force` mode.

Resource-aware outputs require a fresh directory and an explicit resource
contract on each generation. `--update` refuses these outputs so it cannot
replace their resource checks with a function-only adapter.

## Development setup

MoonHostABI currently carries a minimal, version-checked patch for a
`Milky2018/wasm_core@0.14.0` parser defect exposed by recursive Wasm-GC output
from MoonBit 0.10.11. Apply it after dependency resolution:

```powershell
moon update
moon check
pwsh -NoProfile -File scripts/apply-wasm-core-patch.ps1
```

On a clean checkout, `moon update` refreshes dependency metadata while `moon check`
materializes the source under `.mooncakes`; the guarded patch runs after that
resolution step.

The patch only teaches the upstream parser to resolve self-references in an
implicit singleton recursive type. It is kept separate from MoonHostABI's own
ABI logic so it can be removed when an upstream release contains the fix.

As of September 20, 2026, wasmoon issue #512 is closed and the fix is merged
through PR #519. The latest published `wasm_core` package, `0.16.0`, still fails
the unpatched singleton regression.
Keep the pinned `0.14.0` dependency and guarded patch until a published version
passes that regression without the patch. See the
[upstream status and removal checklist](patches/README.md#upstream-status-and-removal-checklist).
