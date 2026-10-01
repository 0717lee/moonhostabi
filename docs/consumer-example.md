# Consumer gates

These gates cover the `0.6.1` source and package candidate, including the bundled
parser and checked entrypoints. A source workspace run and an isolated
package-install run provide different evidence; public publication and
third-party adoption require separate evidence. Check
[Mooncakes](https://mooncakes.io/docs/0717lee/moonhostabi) and
[GitHub releases](https://github.com/0717lee/moonhostabi/releases) for availability.

## Source workspace gate

Run from the repository root on Windows with PowerShell 7:

The full `verify-spike.ps1` gate also runs this example on Windows after the
runtime checks; its Linux path reports an explicit consumer-scope skip.

```powershell
pwsh -NoProfile -File scripts/verify-consumer.ps1
```

Success requires process exit `0` and
`MOONHOSTABI_SOURCE_CONSUMER_STATUS=GO`. The gate compiles a real MoonBit pricing
application, consumes MoonHostABI's public SDK from this checkout, compiles the
generated adapter with strict TypeScript, and executes the WasmGC application
in Node. This is a repository-owned consumer example and local source
validation, not third-party adoption or published-package validation.

## Inputs and prerequisites

- Moon `0.1.20260920 (914d7da)` and moonc `v0.10.14+7d59c7ec9`, checked by the gate.
- A working native C toolchain for the SDK consumer and Node with WasmGC support
  (validated here with Node `24.12.0`).
- The existing `runtime/node_modules/typescript/bin/tsc` and
  `runtime/node_modules/@types/node` installations. The gate does not run npm or
  install tools; its evidence records the actual TypeScript and Node versions.
- Moon's existing dependency cache/registry access for the declared dependencies.
  The consumer declares `0717lee/moonhostabi@0.6.1` and `moonbitlang/x@0.5.1`.
  Normal Moon dependency resolution happens inside the temporary workspace.
- Optional bundled `.tools/wasm-tools/**/wasm-tools.exe`. If present, both
  freshly compiled artifacts must pass `wasm-tools validate`; absence prints
  an explicit `CONSUMER_WASM_VALIDATE=SKIP` marker.

## Local source override

The script copies `examples/consumer/` and `examples/consumer-app/` into a fresh
OS temporary directory named `moonhostabi-consumer-<GUID>`. It writes this
`moon.work` in that directory's `workspace/` child, using absolute paths:

```text
members = ["C:/absolute/path/to/moonhostabi-production", "C:/absolute/temp/moonhostabi-consumer-<GUID>/workspace/consumer"]
```

The string-array manifest and running commands from the workspace root follow
[MoonBit's workspace documentation](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html).
Absolute members were also exercised with the pinned toolchain. The consumer's
declared version is `0.6.1`; the workspace member supplies the actual local
library implementation. No library source is copied into the consumer.

Before the SDK build, the gate saves `moon build --dry-run` output and requires
the parser, verifier, and generator source paths to point to this checkout.
Failure to establish that resolution stops the gate, with no fallback to a
downloaded package. The source marker records checkout resolution independently
of public release availability.

The dry run also materializes the temporary workspace's dependencies. The local
library includes the fixed parser in `src/internal/wasm_parser`; compilation
does not require a patch to the workspace's `.mooncakes` directory. This still
tests workspace resolution rather than the contents of a distributable package.

## End-to-end behavior

1. Compile `consumer-app/v1` and `consumer-app/v2` separately with
   `moon build --release --target wasm-gc`. Both use the same application module
   name and export `total_price`.
2. Build the copied native SDK consumer using the temporary workspace. Its
   `main.mbt` calls the public checked parser, projector, lockfile, contract,
   verification, and TypeScript generator APIs.
3. Create `pricing.lock.json` from the compiled v1 bytes and read it back through
   the public baseline decoder. Verify v1 with its generated function contract;
   assert `VerificationCompatible` and recommended exit code `0`.
4. Verify v2 against the saved baseline without supplying the stale v1 contract;
   assert `VerificationBreaking` and recommended exit code `2`. Supplying a
   stale contract would test an adapter mismatch instead of this ABI change.
5. Generate the v1 TypeScript adapter, function contract, and manifest. The SDK
   asserts that the public resource inventory is empty: this app's memory is
   internal, so no resource contract is needed.
6. Strictly compile both the generated adapter and `host.ts` using the existing
   TypeScript installation. Node binds the selected artifact to its SDK report
   using the report's artifact fingerprint, then permits only a compatible
   report to reach adapter instantiation.
7. Call v1 through the generated adapter: three items at 1,250 cents with a
   1,000-basis-point discount produce **3,375 cents**. Also check zero quantity
   and no discount. Feed v2 and its breaking report to the same host; require
   process exit `2` and the blocking marker before any instantiation.

The SDK consumer itself exits `0` after asserting both expected decisions.
The Node upgrade attempt actually exits `2`; the enclosing gate treats that
specific result as a successful rejection.

Expected markers include:

```text
CONSUMER_SOURCE_WORKSPACE=GO
CONSUMER_V1_EXIT=0
CONSUMER_V2_EXIT=2
CONSUMER_SDK=GO
CONSUMER_TYPESCRIPT=GO
CONSUMER_HOST_TOTAL_CENTS=3375
CONSUMER_HOST_BLOCKED=breaking
CONSUMER_TEMP_CLEANUP=GO
MOONHOSTABI_SOURCE_CONSUMER_STATUS=GO
```

## Reusable outputs and evidence

`CONSUMER_EVIDENCE` prints the unique `_build/consumer-tools/<GUID>/` run
directory. Every child process has a saved stdout/stderr pair there. The
directory also retains the workspace manifest, SDK build, and `inputs.json`
with the exact consumed artifact/output paths. `output/` contains:

| File | Purpose |
| --- | --- |
| `v1.wasm`, `v2.wasm` | Freshly compiled application versions |
| `pricing.lock.json` | Reusable v1 ABI baseline |
| `v1.report.json`, `v2.report.json` | Canonical SDK verification reports |
| `generated/adapter.ts` | Generated v1 TypeScript host interface |
| `generated/moonhostabi.contract.json` | Function contract |
| `generated/moonhostabi.manifest.json` | Generator manifest |
| `host.ts`, `tsconfig.json`, `package.json`, `dist/` | Strict host build and runnable ESM |

To replay the host with the printed run path:

```powershell
$output = Join-Path '<CONSUMER_EVIDENCE path>' 'output'
node (Join-Path $output 'dist/host.js') (Join-Path $output 'v1.wasm') (Join-Path $output 'v1.report.json')
# Exit 0; CONSUMER_HOST_TOTAL_CENTS=3375
node (Join-Path $output 'dist/host.js') (Join-Path $output 'v2.wasm') (Join-Path $output 'v2.report.json')
# Exit 2; CONSUMER_HOST_BLOCKED=breaking
```

The script removes only its exact OS temporary GUID directory after checking
the resolved parent, exact leaf, and absence of a reparse point at that root.
Build outputs remain under `_build`; the saved `moon.work` is evidence of the
completed run and references a consumer directory removed during cleanup.
Run the script again to create a fresh workspace.

The pricing example assumes small nonnegative integers, a discount from 0 to
10,000 basis points, and an intermediate product that fits MoonBit `Int`.
It truncates fractional cents. This gate covers a scalar function boundary on
the pinned Windows/native and Node path; it does not exercise public resources,
browser hosting, other operating systems, or general monetary arithmetic.

## Isolated package consumer gate

Run from the repository root:

```powershell
python -B scripts/verify-package-consumer.py
```

Success requires exit `0` and `MOONHOSTABI_PACKAGE_CONSUMER_STATUS=GO`.
The gate tests the candidate as a packaged dependency. It uses
the actual `moon package` archive, serves a temporary registry on loopback, and
runs `moon add`, `moon check`, `moon test`, and `moon run` in a fresh consumer
with a fresh `MOON_HOME`. The pinned toolchain and the gate's declared runtime
prerequisites must already be available. Normal package resolution supplies the
dependencies; there is no `moon.work` override or manual dependency-cache patch.

It checks the complete packaged parser, LICENSE and provenance, then verifies
singleton self-references, all 256 expression frames, owned error cases, and a
nonempty compatible/breaking ABI lock workflow. Each of native, JS and Wasm-GC
executes four tests and the example. This is distinct from the source example's
compiled pricing application and generated TypeScript host.

`PACKAGE_CONSUMER_EVIDENCE` names a unique `_build/package-consumer/<run>/`
directory containing the candidate ZIP, command logs, HTTP downloads,
source-resolution plan, before/after installed-file hashes and `report.json`.
The source workspace marker above cannot satisfy this installation target.
See [validation evidence](validation.md) for the passing local candidate runs.

The local registry exercises package creation, download, installation, and
downstream use without publishing to Mooncakes. A public release still requires
its own exact-commit CI, release gates, and a consumer of the published package.
