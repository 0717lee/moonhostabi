# Validation evidence

## Compiler upgrade acceptance, 2026-10-01

The local `0.6.1` candidate based on `397ded8` passed the full Windows Spike
with `moonc v0.10.14+7d59c7ec9 (2026-09-18)` and
`moon` / `moonrun 0.1.20260920 (914d7da 2026-09-20)`.
The toolchain is installed in `.tools/moonbit-0.10.14`; the README documents
the environment assignments needed to select it in a new shell.

| Check | Result |
| --- | --- |
| Format and compilation | `moon fmt --check`; native check; Wasm, JS and Wasm-GC checks with `--deny-warn` passed |
| MoonBit tests | native 194/194; JS 157/157; Wasm-GC 157/157 |
| Python self-tests | provenance 4/4; benchmark runner 20/20; package consumer 19/19 |
| CLI, reproduction and packaging | CLI report, deterministic bundle, Windows package/unpacked smoke, release aggregation and workflow checks passed |
| Generator transactions | `MOONHOSTABI_TRANSACTION_STATUS=GO` |
| Host execution | Node checks passed; Chromium function 6/6 and resource 27/27 |
| Large compiler artifact | 1,633 type groups; `MOONHOSTABI_TYPE_POLICY_STATUS=GO` |
| Source SDK consumer | `MOONHOSTABI_SOURCE_CONSUMER_STATUS=GO` |
| Isolated package installation | `MOONHOSTABI_PACKAGE_CONSUMER_STATUS=GO`; native, JS and Wasm-GC each checked, ran 4/4 tests and executed the smoke example |
| Complete gate and demo | `MOONHOSTABI_SPIKE_STATUS=GO`; `MOONHOSTABI_JUDGE_DEMO_STATUS=GO` |
| Third-party provenance | Passed against the original `wasm_core@0.14.0` ZIP, including the documented package import change |

Both official platform archives were downloaded and hashed; their installed
tool identities match the pins below. The Linux toolchain also rebuilt the five
MoonBit fixtures under WSL Ubuntu 22.04, producing byte-identical Windows/Linux
artifacts. The WAT changes from the old compiler contain only the `processed-by`
version metadata. Canonical ABI and generated TypeScript bytes remain unchanged.
Public trait methods now have explicit `extend` declarations so the new
compiler's warning checks preserve the existing callable API.

Local raw evidence is in `_build/toolchain-upgrade/verify-spike.log`,
`_build/toolchain-upgrade/judge-demo.log`,
`_build/toolchain-upgrade/linux-fixtures.log`, and
`_build/package-consumer/20261001T024556Z-fc774b38/report.json`.
These checks establish local candidate evidence. The release commit must also
pass remote Windows/Linux Verification and Release dry run before publishing
`0.6.1`.

## Historical first Spike

MoonHostABI reached a **local Spike GO** on 2026-09-04. The single verification
entry point reproduced the parser, projection, canonicalization, compatibility,
generation, Node.js, and Chromium evidence described below. The public
Verification workflow has since completed successfully for both Windows and
Linux on the release candidate commit
(`https://github.com/0717lee/moonhostabi/actions/runs/34081779933`).

## Version 0.6.0 release verification

The 0.6.0 release line includes the bounded-input APIs, bundled parser,
source-error migration, resource generation optimizations and cleanup described
below. It preserves the function ABI and resource v4/v5 wire protocols.
The exact release commit must pass the full local Spike, the remote
Windows/Linux Verification matrix and Release dry run before publication.
The [0.6.0 release notes](https://github.com/0717lee/moonhostabi/releases/tag/v0.6.0)
record the immutable workflow run URLs; downloadable `SHA256SUMS` and
`provenance.json` bind both archives to that same clean commit.
Public Mooncakes installation is a separate post-publication check.
Future versions must repeat these gates for their own exact release commit.

## Historical pre-release source validation

### Bundled parser candidate, 2026-09-29

The candidate now ships its fixed parser inside `src/internal/wasm_parser`.
Both public parsing entrypoints use it, retain `wasm_core@0.14.0` module types,
and raise the owned `ArtifactError`; the raw entrypoint's error type and `Show`
format are an explicit [source API migration](library-api.md#parser-distribution-and-error-migration).
Normal consumers do not modify `.mooncakes`.

The full Windows Spike passed after bundling with
`MOONHOSTABI_SPIKE_STATUS=GO`: 189 native, 152 JS and 152 Wasm-GC tests,
6 function-browser and 27 resource-browser tests, plus the CLI, bundle,
deterministic package, transaction, large-artifact, source-consumer and isolated
package-consumer gates. Its log is `_build/distribution-spike.log`.
The 35 parser tests also passed in native release mode;
`moon check --target all --deny-warn`, `moon build --target all --deny-warn`
and `moon info` passed against unmodified upstream dependencies.

The provenance gate checked all 12 source files, the two adapted implementation
bodies and LICENSE against the checksum-verified original ZIP. Its four unit
tests, the 19 package-consumer harness tests and 19 benchmark tests passed.
The parser suite includes a 15-fixture comparison with the pristine upstream
parser; singleton and structured-expression fixes have explicit expected-AST
assertions. Independent parser and distribution-gate reviews approved this scope.

The isolated package gate passed twice, including the full Spike run:
`_build/package-consumer/20260929T090552Z-41d9ca19/report.json` records a real
`moon package` archive installed via `moon add` into a fresh `MOON_HOME`.
Native, JS and Wasm-GC each passed four consumer tests and all runtime markers.
Exactly three loopback archive downloads occurred; every installed source
matched its archive before and after testing, and temporary cleanup passed.
There was no `moon.work`, path override or dependency-cache patch.

Replaying the retained pre-wiring archive produced the expected failure:
`_build/package-consumer/20260929T090304Z-765779df/report.json` and
`check-native.stderr.txt` identify the missing `parse_module_iterative` API.
This is an actual old-package failure against pristine dependencies, not a
synthetic negative result.

The newly compiled large-artifact probe is 737,182 bytes, with 1,631 type groups
and SHA-256 `c866383c1010be21f3b0ebfc5c459bc8820cf5a3c883ffa2358bdbe34cf17e97`.
Independent Wasm validation and checked resource lock/verify pass.
No new remote CI, Linux execution or public publication is claimed.
The local archive retains version metadata `0.5.1` only for this isolated test;
it is not the public package. A new version and explicit API migration are
required before publication.

### Earlier source hardening run, before parser bundling

The full Windows Spike passed with 186 native, 149 JS, and 149 Wasm-GC tests,
6 function-browser and 27 resource-browser tests, plus the CLI, bundle, package,
transaction and fresh source-consumer gates. The parser also passed 32 tests
in native release mode. Nineteen benchmark tests and three isolated patch-guard
tests passed. This September 29 run used the former dependency-patch setup;
it is historical evidence, not a full validation of the bundled-parser revision.
No remote CI or new publication is claimed by this local record.

The rebuilt resource test driver is 734,405 bytes with 1,631 type groups
(a lower bound on actual types), SHA-256
`c7e84f60cf8c03bf6aaca1d3cf6cd671ae5166b44ce008d6cb23f4920f7e7286`.
It passes independent Wasm validation and checked resource lock/verify; function
inspection retains its known tag-capability diagnostic. The original 693,081-byte
probe also passes. See [input limits](input-limits.md), the
[paired performance results](performance.md), and the two
[historical dependency patches](../patches/README.md).

That pre-release checkout added [input budgets](input-limits.md),
[scale benchmarks](performance.md), and the [source consumer](consumer-example.md).
Its Spike gate now executes native, JS and Wasm-GC tests, the benchmark runner
self-tests, and the resource browser suite. The compiled consumer is included
on Windows; the Linux entry explicitly reports that consumer scope as skipped.
These local source changes do not inherit the published release's remote CI or
package evidence. Repeat exact-commit remote and package gates before release.

## Patch release 0.5.1 verification scope

Version `0.5.1` preserves the function ABI and resource v4/v5 protocols. It fixes
opaque resource JSON embedding, no-overwrite archive publication, and structured
CLI errors when an update directory disappears during validation. It strengthens
canonicalization and publication-failure regression coverage.

Release acceptance requires the full local Spike gate, native/JavaScript/Wasm-GC
tests, the remote Windows/Linux Verification matrix, and the Release dry run on
the exact release commit. The release notes record those immutable run URLs;
`SHA256SUMS` and `provenance.json` bind the downloadable archives to that commit.
After publication, validate a clean consumer against `0717lee/moonhostabi@0.5.1`
without local dependency overrides. See the
[0.5.1 release page](https://github.com/0717lee/moonhostabi/releases/tag/v0.5.1)
for publication status and the exact-commit evidence.

## Resource workflow verification for 0.5.0

On September 20, 2026, the resource workflow passed the full local
Windows gate, followed by `moon build --target all`:

- 147 MoonBit tests passed, with checks across the configured targets.
- The existing CLI, bundle, package, and transaction gates passed; original
  fixture and generated-adapter byte checks remained unchanged.
- All six Chromium tests passed.
- The resource E2E gate rebuilt its Wasm fixtures, parsed real CLI JSON reports,
  compiled generated adapters with strict TypeScript, and exercised actual
  memory, table, global, and tag bindings, including imports and re-exports.
- Twenty runtime rejection cases passed. A changed artifact containing a
  state-changing start function was rejected before that function could run.

The final markers were `MOONHOSTABI_RESOURCE_E2E_STATUS=GO` and
`MOONHOSTABI_SPIKE_STATUS=GO`. The resource gate is included in
`scripts/verify-spike.ps1`, which the existing CI workflow invokes. These local
results are separate from the remote release evidence recorded below.

Version `0.5.0` was published on September 20 from commit
`784e9fb4da540e07fbc9f8a239505b20c3c1866d` after both exact-commit gates passed:

- [Verification run 35496324936](https://github.com/0717lee/moonhostabi/actions/runs/35496324936):
  Linux and Windows full gates and clean-tree reproducibility checks passed.
- [Release run 35496325425](https://github.com/0717lee/moonhostabi/actions/runs/35496325425):
  both real platform packages, unpacked smoke tests, and aggregation passed.
- [GitHub Release v0.5.0](https://github.com/0717lee/moonhostabi/releases/tag/v0.5.0):
  both archives, `SHA256SUMS`, and `provenance.json` were uploaded. Their digests
  match the downloaded CI artifacts, and provenance names the clean source
  commit above. The downloaded Windows executable also passed resource lock,
  breaking-change verification, contract creation, and adapter generation.
- [Mooncakes manifest](https://mooncakes.io/api-new/v0/manifest/0717lee/moonhostabi@0.5.0):
  publication and package build succeeded. The uploaded package SHA-256 is
  `329b6cb9e34645d505f6915154a0c2a8022e3a38d661effa541710eae3c7c3e6`.
- [Consumer run 35496580826](https://github.com/0717lee/moonhostabi-consumer/actions/runs/35496580826):
  commit `83e4307393ca79aeadccfb55994d342833d689fd` resolves the published `0.5.0`
  package and passes all three tests, including v4 lock/v5 contract roundtrips
  and a changed-memory rejection. The same three tests passed locally against
  the freshly downloaded package.

Version `0.4.1` does not include this resource workflow. Future versions must
repeat these gates for their own release commit before publication.

See the [resource protocol](resource-protocol.md) for supported types, legacy
lock migration, field-level report formats, and artifact-bound runtime checks.

## Reproduce the local gate

The host must provide PowerShell 7, a MoonBit toolchain reporting the exact
identities below, Node.js `24.12.0` with npm `11.6.2`, and `wasm-tools 1.258.0`.
CI obtains those identities from the official MoonBit installer snapshot
`0.10.14+7d59c7ec9`; the snapshot selector is not the same value as the
reported `moon` version. The script resolves dependencies, rebuilds all fixtures,
installs the locked npm graph and Chromium, and stops at the first unexpected
result. On a clean checkout, normal dependency setup is `moon update` followed
by `moon check`. The parser fixes are part of the candidate package; no cache
patch or patch-only dependency API is required. The Spike definition also runs
the isolated package consumer gate; the workspace source example remains a
separate Windows check.

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
| `moon` | `0.1.20260920 (914d7da 2026-09-20)` |
| `moonc` | `v0.10.14+7d59c7ec9 (2026-09-18)` |
| `moonrun` | `0.1.20260920 (914d7da 2026-09-20)` |
| `wasm-tools` | `1.258.0 (5c6d31c78 2026-08-24)` |
| Node.js | `v24.12.0` |
| npm | `11.6.2` |
| TypeScript | `7.0.2` |
| Playwright | `1.62.1` |
| Chromium used by Playwright | `151.0.7922.34` |

The official installer/archive snapshot is `0.10.14+7d59c7ec9` (URL-encoded as
`0.10.14%2B7d59c7ec9`). It is deliberately recorded separately from the
reported tool identities: `moon` and `moonrun` report `0.1.20260920`, while
`moonc` reports `v0.10.14+7d59c7ec9`. CI preflights the platform binary archive
for that snapshot, then passes the unencoded snapshot selector to the official
installer and checks all three identities after installation.

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

The MoonBit binary archives are also preflighted against the fixed snapshot
hashes before installation:

| Platform archive | Official URL path | SHA-256 |
| --- | --- | --- |
| Linux x86_64 | `/binaries/0.10.14%2B7d59c7ec9/moonbit-linux-x86_64.tar.gz` | `9226694de9ff978db1ecf820b7710c4224e84ec7a76b19a222d96f0cd4e31b6a` |
| Windows x86_64 | `/binaries/0.10.14%2B7d59c7ec9/moonbit-windows-x86_64.zip` | `faae225a8287d0ce69e44b5b3f754af988e97f4446056d8f32ceb3ddb998fce7` |

CI also downloads the official MoonBit installers as files rather than piping
them directly into a shell. The installer SHA-256 values are
`46495f8cdc0050f79b6cb195d66478d101cb3601d68506568fbe377fcdf2a9fe`
(Unix) and
`a5101e91ffa9905fb25cd009b9a4aa942971a294bd055c89836e3af89b710c64`
(Windows). The installer selects the matching core archive from the same
snapshot; the post-install identity check is the guard for the combined
`moon`/`moonc`/`moonrun` toolchain.

## Fresh fixture provenance

Every fixture was authored for MoonHostABI. None comes from PixelForge or an
earlier submission. Text source hashes below are SHA-256 over UTF-8 after
normalizing line endings to LF; artifact hashes are over the exact committed
bytes. `scripts/build-fixtures.ps1` rebuilt and independently validated all
seven artifacts with `wasm-tools` before publishing them.

| Fixture | Primary source | Source SHA-256 | Artifact SHA-256 |
| --- | --- | --- | --- |
| scalar | `fixtures/projects/scalar/main.mbt` | `b5ae50108cd0cf9947ac672a14a68da85e0cb0eb866d40a85f3558372100be99` | `be817374900683570f87887b876ab8c24f9135c73bc554456524357bcbf3300b` |
| externref | `fixtures/projects/externref/main.mbt` | `9cd011eefe6c70c4dcd1fede619b8164826be810a2e428eccb9c91a65f2a6773` | `24ccbe8633b8ad0fbf3a730e5aeecc862da6c764243a6855807de150e8af4663` |
| recursive | `fixtures/projects/recursive/main.mbt` | `2ab36bc8823e415b7750e6ca79098373f21d9694a4c742a2301595c1adf77d2c` | `43f32236fa6234ae5176c913566c2ea79f445c2f78ee57a03d7a6d9cc0f78e1e` |
| breaking v1 | `fixtures/projects/breaking_v1/main.mbt` | `9f121a57617f5f17965f50f81d840f829244e1ee2a38c2a5b413408f8f1da314` | `b936ce52001611715140278b7dce3eb78bdf78e2b8958bb935e467d027906203` |
| breaking v2 | `fixtures/projects/breaking_v2/main.mbt` | `08f71cff1f32ede8d4842abb29bd3b1ad2ee795859578bf65ae4b8b8b8771c8f` | `9fbab7ae1cbe8cc0dd5d64407ea092a70ce2e58f3731ea852bc31a752b978c7a` |
| recursive layout A | `fixtures/wat/rec-a.wat` | `edce02ba59eb680db518ac4b980b293ea06b461e3de0a1d20b1464396fb64b7a` | `885ebd2fa3c5f4cadb67905569e1566ef84a53bc9a9b6a4cea77a7187fe873cc` |
| recursive reindexed | `fixtures/wat/rec-reindexed.wat` | `185536211967ff0c970e9e3055cf7b0b1251744a143f20ae0e37ec6bdb39e36c` | `c860e7e7fbdb91b8558a20bc5bc94f3a4fcbe71dd5036b3c6d32ac96a878cda5` |

## Canonicalization and lock determinism

- Two independent `lock` invocations over `breaking_v1.wasm` produced
  byte-identical files with SHA-256
  `17177ffdabf8b58537e187733d461fbcaad5b28753f3ed89dbf211fc5b11598a`.
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

Readable semantic inputs within the file-size policy use the canonical report
on stdout. CLI usage errors, unreadable paths, and oversized input files remain
stderr-only. Verification has no fallback,
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

## Local release packaging evidence

Task 7 adds deterministic platform packages and a dry-run-only release
aggregate. The local Windows gate created two independent release ZIPs, compared
their complete bytes, validated the exact eight-file layout and ZIP metadata,
then ran `--version`, `--help`, and compatible `verify` using the executable and
example files extracted from each archive. Checkout binaries cannot satisfy the
smoke assertion.

The package includes this validation document, so embedding its own final
archive hash here would create a self-reference. Instead, the gate emits
`MOONHOSTABI_PACKAGE_SHA256=<hash>` as external evidence after each run. The
final aggregate can bind both platform hashes without being inside either
archive.

Local aggregate tests use the real Windows ZIP plus an explicitly marked
simulated Linux tar.gz. They prove fixed input/output sets, canonical
`SHA256SUMS`, deterministic `provenance.json`, and rejection of missing, extra,
tampered, duplicate-platform, duplicate-key, and noncanonical evidence. Package
negatives independently cover linked/nonempty outputs, overwrite attempts, and
archive rollback when evidence publication fails. Simulated evidence records all
smoke fields as false and production aggregation rejects it unless the test-only
switch is explicit. No Linux binary execution is claimed from this Windows run.

The archive validator also rejects traversal, absolute/drive-qualified,
backslash-ambiguous, duplicate/case-fold paths and tar symlink, hardlink, device,
FIFO, socket, or other non-regular entries. Package contents are scanned for
checkout/temp paths, usernames, `.codex`, and high-confidence credential
markers.

`.github/workflows/release.yml` is `workflow_dispatch` only, uses
`permissions: contents: read`, and contains no secret or publication API. Linux
and Windows jobs create immutable platform handoffs; an Ubuntu job validates and
aggregates them into two archives, `SHA256SUMS`, and `provenance.json`. The
workflow and existing CI action references are pinned to official full commit
SHAs and are checked by a PyYAML semantic validator with negative self-tests.
See [the release dry-run guide](releasing.md).

This is local release-automation evidence. The public Verification workflow is
green for both matrix jobs, and the separate Release dry run completed
successfully for Linux, Windows, and aggregate
(`https://github.com/0717lee/moonhostabi/actions/runs/34081936398`). These are
historical pre-publication results; later release evidence is recorded above.

## Task 8 judge quickstart evidence

The judge-facing quickstart is available at [docs/quickstart.md](quickstart.md),
and the first screen links to it from `README.md`. From a clean repository root,
the focused commands produced these observed local markers:

| Command | Observed marker | Evidence scope |
| --- | --- | --- |
| `scripts/verify-command.ps1` | `MOONHOSTABI_VERIFY_STATUS=GO` | Native CLI report and failure contract |
| `scripts/verify-reproduction-bundle.ps1` | `MOONHOSTABI_BUNDLE_STATUS=GO` | Deterministic seven-entry bundle |
| `scripts/verify-release-packaging.ps1` | `MOONHOSTABI_PACKAGE_STATUS=GO` | Windows native package and extracted smoke |

The quickstart also points to the six-section report schema and explains how
`validation.json` connects that report to the bundle's artifact, lock, contract,
adapter, commands, and manifest files. Its document validator checks links,
relative command paths, encoding, and stale claims. The Verification matrix
provides the remote Linux native result; the Release dry-run workflow also passed
for the published candidate.

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
| Local platform release package is deterministic | two native packages, exact layout/metadata, unpacked CLI smoke and negative tests | GO |
| Release automation is non-publishing | dispatch-only workflow, read-only permission, pinned actions, fixed aggregate contract | GO |
| Generated TypeScript is strict and has no `any` | pinned TypeScript check and token scan | GO |
| Node and Chromium exercise real imports/exports | scalar, identity, trace and negative observations | GO |
| Malformed/unsupported values fail closed | parser, projector, decoder, generator and CLI tests | GO |

Local Spike decision: **GO**. The public Verification matrix decision is also
**GO** for both Linux and Windows. The dispatch-only Release dry run also passed
for both platform packages and aggregate
(`https://github.com/0717lee/moonhostabi/actions/runs/34081936398`). This records
the historical `0.4.1` candidate; later release evidence is recorded above.

## Current limitations

- Default generation supports function imports/exports only. Public tables,
  memories, globals and tags require the explicit 0.5.0
  `--resource-contract` workflow; otherwise they fail closed.
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
- The function ABI lockfile schema remains version 1. Host ABI contracts use canonical
  schema v2 and accept only a strictly validated v1-to-v2 migration; no later
  function-contract migration is implemented. The separate 0.5.0 resource
  workflow uses lockfile v4 and contract v5.
- Runtime preflight validates required imports and, immediately after
  instantiation, verifies every required export is an own property whose value
  is a function. Failures report `MHA_ADAPTER_MISMATCH` with an `exports[...]`
  path. JavaScript does not repeat Wasm parameter and result signature checks;
  artifact ABI analysis and the generated contract remain authoritative for
  those signatures.
- The proof covers native CLI execution on Windows locally and on both Linux and
  Windows in the public Verification matrix. The separate Release dry run passed
  for the published candidate. Future versions must repeat the same checks before
  publication.
- MoonBit's CI installer is content-hash pinned and receives the official
  installer snapshot `0.10.14+7d59c7ec9` (not the reported `moon` identity
  `0.1.20260920`). The Linux and Windows binary archives are preflighted with
  the hashes recorded above, and the installed `moon`/`moonc`/`moonrun`
  identities are version-gated. The installer-selected core archives share the
  snapshot selector but do not currently have independent recorded hashes.
- The browser verifier uses fixed loopback port 4173 with one worker; concurrent
  verifier processes intentionally contend rather than reuse an unknown server.
- `verify` currently accepts canonical JSON output only and uses the semantic
  compatibility policy. Strict-policy selection and additional report formats
  are not implemented.
- The deterministic ZIP result above is locally observed with the tool/runtime
  versions recorded inside its manifest. Fixed metadata minimizes platform
  variation; the Verification matrix and the recorded Release dry run are green.
- The Windows release ZIP path is locally executed and deterministic. Linux
  tar/gzip flags, modes, entry types, and aggregate behavior have local static or
  simulated coverage. Earlier releases passed the remote Release dry run;
  every new release commit must pass that gate independently.

## Parser distribution and upstream status

MoonBit 0.10.11 emits a valid implicit singleton recursive type whose typed
self-reference exposes an ordering defect in `Milky2018/wasm_core@0.14.0`.
The 0.5.1 release used a guarded dependency patch. Version 0.6.0
instead bundles the 12 required parser source files with the singleton and
iterative-expression fixes; its dependency stays at `0.14.0` for the shared
types. The [provenance and license record](../third_party/wasm_core_parser/README.md)
separates original upstream source from the adapted implementation. Historical
singleton patch hashes are retained here:

- normalized upstream source SHA-256:
  `d2d70401532ce13ed844ce2e70f64702ff6591bd9188848f85b8ea2115807417`;
- normalized patched source SHA-256:
  `a835b9e5a47587c4f5d1e6792313f59b2ebfc149156de5b388903007662397d0`.

Upstream [Issue #512](https://github.com/Milky2018/wasmoon/issues/512) was closed
as completed on September 18, 2026. Commit
[`f0b01bd9`](https://github.com/Milky2018/wasmoon/commit/f0b01bd9b23ce6d3d3e36e978df37bc85f5ab980)
was merged into `main` by [PR #519](https://github.com/Milky2018/wasmoon/pull/519).

On September 20, the [Mooncakes manifest](https://mooncakes.io/api-new/v0/manifest/Milky2018/wasm_core@0.16.0)
still listed `0.16.0` as the latest version, published on September 16. In a clean
isolated project without the downstream patch, the implicit singleton
self-reference probe failed with `invalid heap type`; the explicit `rec` control
and malformed-mutability rejection control passed. Thus the fix is merged
upstream but is not yet available in the latest published package tested here.

The September 29 source/package comparison confirms that upstream
[`main` at `74a02453`](https://github.com/Milky2018/wasmoon/tree/74a02453afefbb5ba9c9476838ac0a0ba349e84a/modules/wasm_core/parser)
contains both fixes, including iterative expression parsing introduced by
[`ff98fb9b`](https://github.com/Milky2018/wasmoon/commit/ff98fb9bd0e732059e7f8a4f151f5739a57e45c7).
The official `0.16.0` archive still contains neither fix. The candidate removes
consumer patching by distributing the adapted parser, not by upgrading to an
unpublished upstream checkout. A future published replacement must pass the
[parser and package regression checklist](../patches/README.md#upstream-status-and-removal-checklist).

## Source references

- [MoonBit toolchain installation](https://github.com/moonbitlang/moonbit-docs/blob/main/next/tutorial/tour.md)
- [`wasm-tools` v1.258.0 release](https://github.com/bytecodealliance/wasm-tools/releases/tag/v1.258.0)
- [Playwright 1.62.1 CI guidance](https://github.com/microsoft/playwright/blob/v1.62.1/docs/src/ci.md)
