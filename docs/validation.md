# Validation evidence

MoonHostABI reached a **local Spike GO** on 2026-09-04. The single verification
entry point reproduced the parser, projection, canonicalization, compatibility,
generation, Node.js, and Chromium evidence described below. Windows and Linux
CI are configured in `.github/workflows/ci.yml`; no remote CI run is claimed in
this document because the repository has not been pushed by this workflow.

## Reproduce the local gate

The host must provide PowerShell 7, the exact MoonBit snapshot, Node.js
`24.12.0` with npm `11.6.2`, and `wasm-tools 1.258.0`. The script resolves dependencies, applies the guarded
`wasm_core` patch, rebuilds all fixtures, installs the locked npm graph and
Chromium, and stops at the first unexpected result.

```powershell
pwsh -NoProfile -File scripts/verify-spike.ps1
```

Success ends with:

```text
MOONHOSTABI_SPIKE_STATUS=GO
```

The run creates a GUID directory beneath the resolved OS temporary directory.
Before recursive cleanup it resolves the path again, checks the exact GUID leaf
and parent boundary, and refuses deletion if either invariant changed.

The focused real-process CLI gate is also independently reproducible:

```powershell
pwsh -NoProfile -File scripts/verify-command.ps1
```

It ends with `MOONHOSTABI_VERIFY_STATUS=GO` after checking the bounded-process
timeout/kill path, strict `moon.mod`/CLI/committed-manifest version consistency,
exact help output, strict argument ordering, byte-identical repeated compatible
and breaking reports, exit codes `0`, `2`, `3`, and `4`, paths containing Chinese
characters and spaces, and a Wasm module whose trapping start function proves
that verification does not instantiate or execute the artifact.

## Verified toolchain

| Tool | Locally verified version |
| --- | --- |
| `moon` | `0.1.20260819 (fc2a4ee 2026-08-19)` |
| `moonc` | `v0.10.9+6e6c44045 (2026-08-19)` |
| `moonrun` | `0.1.20260819 (fc2a4ee 2026-08-19)` |
| `wasm-tools` | `1.258.0 (5c6d31c78 2026-08-24)` |
| Node.js | `v24.12.0` |
| npm | `11.6.2` |
| TypeScript | `7.0.2` |
| Playwright | `1.62.1` |
| Chromium used by Playwright | `151.0.7922.34` |

The module graph pins `Milky2018/wasm_core@0.14.0` and
`moonbitlang/x@0.5.1`. The npm lockfile pins `@types/node@24.12.0`,
TypeScript 7.0.2, and Playwright 1.62.1 with package integrity values and
official npm registry URLs.

CI downloads the official `wasm-tools v1.258.0` release archives and checks the
release-published SHA-256 before extraction:

| Platform archive | SHA-256 |
| --- | --- |
| `wasm-tools-1.258.0-x86_64-linux.tar.gz` | `b52d14eb74a4852cc249369bd4480c2b2fdd876145f41db51ff52269ded240ce` |
| `wasm-tools-1.258.0-x86_64-windows.zip` | `527fe5c3ef5363c58888548827bb44c87fcbf17bb2a2df295055788d82c72081` |

CI also downloads the official MoonBit installers as files rather than piping
them directly into a shell. The pinned installer SHA-256 values are
`46495f8cdc0050f79b6cb195d66478d101cb3601d68506568fbe377fcdf2a9fe`
(Unix) and
`a5101e91ffa9905fb25cd009b9a4aa942971a294bd055c89836e3af89b710c64`
(Windows). After installation, both the workflow and final gate reject any
toolchain other than the exact versions listed above.

## Fresh fixture provenance

Every fixture was authored for MoonHostABI. None comes from PixelForge or an
earlier submission. Text source hashes below are SHA-256 over UTF-8 after
normalizing line endings to LF; artifact hashes are over the exact committed
bytes. `scripts/build-fixtures.ps1` rebuilt and independently validated all
seven artifacts with `wasm-tools` before publishing them.

| Fixture | Primary source | Source SHA-256 | Artifact SHA-256 |
| --- | --- | --- | --- |
| scalar | `fixtures/projects/scalar/main.mbt` | `b5ae50108cd0cf9947ac672a14a68da85e0cb0eb866d40a85f3558372100be99` | `46def89a242695003f1585278be7df97a7d47e9f026a96b769a756f3a7670dc3` |
| externref | `fixtures/projects/externref/main.mbt` | `9cd011eefe6c70c4dcd1fede619b8164826be810a2e428eccb9c91a65f2a6773` | `11042a0924422795ad178f36c8cea79bc3225e3e5aa7ee63dfc55e5a50450a76` |
| recursive | `fixtures/projects/recursive/main.mbt` | `2ab36bc8823e415b7750e6ca79098373f21d9694a4c742a2301595c1adf77d2c` | `91174cb447d067743a996a5bad0f567f4c4b9615bc7e116db857d6ebd728b303` |
| breaking v1 | `fixtures/projects/breaking_v1/main.mbt` | `9f121a57617f5f17965f50f81d840f829244e1ee2a38c2a5b413408f8f1da314` | `798b207cae77584dca5fb7cbafd04b75fe341850892c85d4c6c275c208d96e2b` |
| breaking v2 | `fixtures/projects/breaking_v2/main.mbt` | `08f71cff1f32ede8d4842abb29bd3b1ad2ee795859578bf65ae4b8b8b8771c8f` | `c8acfa9ebf99c7c36401de96958d1b5f23ef93eb6d6d0941b97fba040fb8a420` |
| recursive layout A | `fixtures/wat/rec-a.wat` | `edce02ba59eb680db518ac4b980b293ea06b461e3de0a1d20b1464396fb64b7a` | `885ebd2fa3c5f4cadb67905569e1566ef84a53bc9a9b6a4cea77a7187fe873cc` |
| recursive reindexed | `fixtures/wat/rec-reindexed.wat` | `185536211967ff0c970e9e3055cf7b0b1251744a143f20ae0e37ec6bdb39e36c` | `c860e7e7fbdb91b8558a20bc5bc94f3a4fcbe71dd5036b3c6d32ac96a878cda5` |

## Canonicalization and lock determinism

- Two independent `lock` invocations over `breaking_v1.wasm` produced
  byte-identical files with SHA-256
  `2589ab342c39688bffdd7968d92262ac7865dcd06c4bde1a6ae1e90f2a0674d4`.
- The recursive compiler artifact projected two exports (`new_node` and
  `node_value`) and one reachable recursive struct with fields `i32` and
  mutable `ref null type[0]`. Its emitted ABI JSON SHA-256 was
  `478215e987ad7c210534341cf68017150f86f17c686186f8cef986745dcd320f`.
- `rec-a.wasm` and `rec-reindexed.wasm` have different bytes and raw type-index
  layouts. Their canonical ABI JSON was byte-identical, with SHA-256
  `e774790b17c7ad1f6506e45a5639bd4976cefdd009954543eb19b945d2d2fbba`.
- The runtime fixture contract and generated adapter share canonical ABI
  fingerprint
  `ecc9ee29e442515286ed65d66f0b3765c3beb015e086e9022fe641d9e0ccc6d7`.
- Artifact SHA-256 is retained as provenance but deliberately does not define
  semantic ABI compatibility.

## Tested compatibility matrix

`semantic` answers whether an existing host remains usable. `strict` treats any
surface change as breaking. `unknown` is a fail-closed result, never success.

| Seeded change | Semantic | Strict | Stable evidence |
| --- | --- | --- | --- |
| add export | compatible | breaking | `MHA_EXPORT_ADDED`, `exports[add]` |
| remove export | breaking | breaking | `MHA_EXPORT_REMOVED`, `exports[render]` |
| remove import | compatible | breaking | `MHA_IMPORT_REMOVED`, `imports[clock.now]` |
| add required import | breaking | breaking | `MHA_IMPORT_ADDED`, `imports[host.echo]` |
| parameter value change | breaking | breaking | `MHA_SIGNATURE_CHANGED`, `exports[convert].params[0]` |
| result value change | breaking | breaking | `MHA_SIGNATURE_CHANGED`, `exports[convert].results[0]` |
| parameter arity change | breaking | not separately seeded | `MHA_SIGNATURE_CHANGED`, `exports[sum].params` |
| typed-ref nullability change | breaking | breaking | `MHA_GC_TYPE_CHANGED`, `exports[consume].params[0]` |
| reachable GC heap kind change | breaking | breaking | `MHA_GC_TYPE_CHANGED`, `types[type[0]].kind` |
| reachable GC field storage change | breaking | breaking | `MHA_GC_TYPE_CHANGED`, `types[type[0]].fields[0].storage` |
| unreachable private type change | compatible | compatible | no changes |
| unsupported public item diagnostic | unknown | unknown | `MHA_PROJECT_UNSUPPORTED_ITEM`, `imports[env.memory]` |
| unknown Host ABI feature | unknown | not separately seeded | `MHA_FEATURE_UNSUPPORTED`, `features[future.host-feature]` |
| unknown schema version | not separately seeded | unknown | `MHA_SCHEMA_UNSUPPORTED`, `schemaVersion` |
| unknown boundary value | unknown | not separately seeded | `MHA_PROJECT_UNREPRESENTABLE`, `exports[mystery].params[0]` |
| artifact bytes change, ABI unchanged | compatible | compatible | no changes |
| add typed export without reindexing old surface | compatible | not separately seeded | `MHA_EXPORT_ADDED`, `exports[aaa_new]` |
| compiled `breaking_v1` → `breaking_v2` | breaking | not separately seeded | `MHA_SIGNATURE_CHANGED`, `exports[add].params` |

The final CLI check over the compiled breaking pair returned exactly exit code
2 and emitted:

```json
{"classification":"breaking","changes":[{"classification":"breaking","code":"MHA_SIGNATURE_CHANGED","path":"exports[add].params","message":"function value count changed"}]}
```

## One-command verification report

`moonhostabi verify <artifact.wasm> --against <lock.json> [--contract
<contract.json>] --format json` aggregates the release decision into one
canonical schema-v1 document. Its six evidence sections are `artifact`,
`baseline`, `provenance`, `compatibility`, `contract`, and `generator`; the
top-level `outcome` is one of `compatible`, `breaking`, `unknown`, `invalid`,
or `adapterMismatch`.

The focused golden suite covers compatible input with a valid contract,
breaking ABI, unsupported projection, invalid lockfile, stale and malformed
contracts, generator adapter mismatch, equal ABI from different artifact
bytes, and malformed Wasm. In the real-process gate:

- compatible and representable input returned exit `0`;
- the compiled breaking pair returned exit `2` with
  `MHA_SIGNATURE_CHANGED` at `exports[add].params`;
- invalid and unsupported inputs returned exit `3` as distinct `invalid` and
  `unknown` outcomes;
- an invalid `moonbit:ffi.make_closure` signature returned exit `4` with
  `MHA_ADAPTER_MISMATCH`;
- equal canonical ABI with different artifact bytes returned exit `0` while
  reporting `artifactMatchesBaseline: false` and
  `abiMatchesBaseline: true`.

Readable semantic inputs always use the canonical report on stdout. CLI usage
errors and unreadable paths remain stderr-only. Verification has no fallback,
mock host, or artifact execution path.

## Deterministic reproduction bundle

The public bundle creator composes the existing `lock`, `generate`, and
`verify` commands; `validation.json` is the real canonical verify stdout, not a
second implementation or a substituted success result:

```powershell
pwsh -NoProfile -File scripts/create-reproduction-bundle.ps1 `
  -Artifact fixtures/artifacts/externref.wasm `
  -Contract fixtures/contracts/externref.contract.json `
  -Out <new-absolute-path>.zip
```

The focused gate created two archives from separate input copies and independent
temporary/staging runs. Every unpacked byte and both final archive hashes were
identical:

```text
590507a2f6a865dcbe4cba496356a203fa92cc30c83c94f2e45b64bc5a49e1af
```

This is external local-gate evidence. `manifest.json` deliberately does not
claim its own hash or the archive hash; it records fixed-order SHA-256 and byte
size entries for the other six payloads. The ZIP uses a fixed entry order,
forward-slash names, no compression, zero external attributes, UTF-8/LF text,
and timestamp `1980-01-01 00:00:00`.

Appending a valid empty custom section changed exactly:

- `manifest.json`;
- `validation.json`;
- `host-abi.lock.json`;
- `artifact.wasm`.

It left `moonhostabi.contract.json`, `adapter.ts`, and `commands.txt`
byte-identical because the canonical ABI did not change. The same gate validates
the exact seven-entry archive, every manifest hash/size, and rejects artifact
paths through links/reparse points, output overwrite, pre-publication failure,
Zip Slip, absolute/drive-qualified, duplicate, and unknown entries. No creator
work directory or sibling staging file associated with the current verifier
remained; an unrelated same-shape creator sentinel is preserved until its own
strict cleanup, so legitimate concurrent runs do not create false failures. A
separate black-box run started two full reproduction verifiers concurrently;
both exited `0` with `MOONHOSTABI_BUNDLE_STATUS=GO` and empty stderr.

See [the report schema](report-schema.md) and the
[bundle reproduction guide](../fixtures/reproduction/README.md) for the field
contract and portable commands.

## Runtime observations

The generated adapter contains no `any` escape hatch and passes TypeScript 7
with `strict` and `noImplicitAny`.

Node.js loaded the committed Wasm bytes and emitted only after asserting the
actual calls:

```json
{"result":42,"externrefIdentity":true,"traceCount":1,"traceArgumentIdentity":true}
{"code":"MHA_ADAPTER_MISMATCH","paths":["imports[host.echo]","exports[roundtrip]","exports[add]","exports[add]"],"observed":true}
```

Chromium 151 executed the same compiled adapter and fixture. Playwright 1.62.1
observed:

- `#result` = `42` from `add(20, 22)`;
- `#externref-identity` = `true` from strict object identity after
  `roundtrip(token)`;
- `#trace` = `{"count":1,"argumentIdentity":true}` from the Wasm-triggered
  `host.echo` call;
- the intentional missing-import case contained both
  `MHA_ADAPTER_MISMATCH` and `imports[host.echo]`;
- real Wasm modules with a missing `roundtrip`, a renamed `add`, and an `add`
  global in place of a function failed at `exports[roundtrip]`, `exports[add]`,
  and `exports[add]`, respectively. The positive result, identity, and trace
  observations remained unchanged.

The browser server exposes only the page, compiled adapter and Wasm fixture,
binds to `127.0.0.1`, and had zero listeners after the run.

## Malformed and unsupported inputs

- Malformed Wasm: exit 3 with `MHA_PARSE_MALFORMED`.
- Missing input: exit 3 with `MHA_INPUT_IO`, not a false parse diagnosis.
- Public table, memory, global or tag imports/exports:
  `MHA_PROJECT_UNSUPPORTED_ITEM`.
- Public typed GC references and `v128` under the default JavaScript capability
  policy: exit 3 with `MHA_PROJECT_UNREPRESENTABLE`.
- Unknown value encodings, Host ABI features and schema versions classify as
  `unknown`.
- `verify` reports malformed, noncanonical or hash-inconsistent lockfiles and
  malformed or ABI-mismatched contracts in its canonical stdout document;
  mutating commands still reject them before output is written.
- Duplicate JavaScript import/export keys are rejected; `__proto__` is emitted
  as a computed own property and validated with an own-property check.

The recursive fixture's exit 3 is therefore expected at the default JavaScript
runtime boundary. Its complete recursive graph is still projected and tested
under the explicit typed-GC capability policy; MoonHostABI does not pretend
that today's Node/Chromium adapter can exchange typed GC references.

## GO criteria

| Criterion | Evidence | Status |
| --- | --- | --- |
| Real recursive GC artifact is parsed and projected | compiler artifact, exact graph assertions, independent `wasm-tools validate` | GO |
| Repeated lock output is byte-identical | two files, one SHA-256 above | GO |
| Raw type reindexing creates no drift | different artifacts, identical canonical ABI bytes | GO |
| Seeded breaking changes have stable code/path | matrix plus compiled pair exit 2 | GO |
| One command aggregates release evidence | canonical six-section report, exits 0/2/3/4, real Unicode/space paths | GO |
| Reproduction archive is deterministic and bounded | two independent ZIPs/bytes, manifest hash+size checks, mutation and path-security negatives | GO |
| Generated TypeScript is strict and has no `any` | pinned TypeScript check and token scan | GO |
| Node and Chromium exercise real imports/exports | scalar, identity, trace and negative observations | GO |
| Malformed/unsupported values fail closed | parser, projector, decoder, generator and CLI tests | GO |

Local Spike decision: **GO**. Contest/release delivery still requires the first
green remote run of both CI matrix jobs; the workflow exists, but local work is
not evidence of a GitHub-hosted run.

## Current limitations

- The generated adapter supports function imports/exports only. Public tables,
  memories, globals and tags fail closed.
- Typed GC references and `v128` are modeled for ABI comparison but are not
  represented by the default JavaScript adapter.
- Contract v2 names each public `externref` position independently; positions
  share one TypeScript parameter only when the contract repeats an alias.
  Aliases do not add runtime brand checks.
- Only the exact known `moonbit:ffi.make_closure` signature receives generated
  behavior. Other host behavior remains an explicit throwing stub.
- Duplicate `(module, name)` imports are rejected instead of synthesized as
  overloads. Fresh generation never replaces an existing path; updates require
  a real non-link directory, an exact manifest-owned file set with matching
  hashes, and an unchanged byte snapshot after the directory is atomically
  claimed.
- The lockfile schema remains version 1. Host ABI contracts use canonical
  schema v2 and accept only a strictly validated v1-to-v2 migration; no later
  schema migration is implemented.
- Runtime preflight validates required imports and, immediately after
  instantiation, verifies every required export is an own property whose value
  is a function. Failures report `MHA_ADAPTER_MISMATCH` with an `exports[...]`
  path. JavaScript does not repeat Wasm parameter and result signature checks;
  artifact ABI analysis and the generated contract remain authoritative for
  those signatures.
- The proof covers native CLI execution on Windows locally and configures Linux
  CI, but no remote Linux result is claimed yet.
- MoonBit's CI installer is content-hash pinned and the installed binaries are
  version-gated, but it still resolves the service's `latest` toolchain. A new
  upstream release therefore fails closed instead of silently upgrading; an
  immutable, checksum-pinned historical archive is a release prerequisite.
- The browser verifier uses fixed loopback port 4173 with one worker; concurrent
  verifier processes intentionally contend rather than reuse an unknown server.
- `verify` currently accepts canonical JSON output only and uses the semantic
  compatibility policy. Strict-policy selection and additional report formats
  are not implemented.
- The deterministic ZIP result above is locally observed with the tool/runtime
  versions recorded inside its manifest. Fixed metadata minimizes platform
  variation, but byte identity across Windows and Linux is not claimed before a
  green remote matrix run compares those outputs.

## `wasm_core` parser patch and upstream status

MoonBit 0.10.9 emits a valid implicit singleton recursive type whose typed
self-reference exposes an ordering defect in `Milky2018/wasm_core@0.14.0`.
MoonHostABI carries `patches/wasm_core-0.14.0-singleton-rec.patch` plus an
idempotent, version- and source-hash-guarded application script.

- normalized upstream source SHA-256:
  `d2d70401532ce13ed844ce2e70f64702ff6591bd9188848f85b8ea2115807417`;
- normalized patched source SHA-256:
  `a835b9e5a47587c4f5d1e6792313f59b2ebfc149156de5b388903007662397d0`.

No upstream Issue or PR has been opened as of 2026-09-04, so there is no link to
claim. Replacing the cache patch with an upstream release containing the fix is
a release prerequisite.

## Source references

- [MoonBit toolchain installation](https://github.com/moonbitlang/moonbit-docs/blob/main/next/tutorial/tour.md)
- [`wasm-tools` v1.258.0 release](https://github.com/bytecodealliance/wasm-tools/releases/tag/v1.258.0)
- [Playwright 1.62.1 CI guidance](https://github.com/microsoft/playwright/blob/v1.62.1/docs/src/ci.md)
