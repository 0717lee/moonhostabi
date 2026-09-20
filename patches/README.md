# Dependency patches

## `wasm_core-0.14.0-singleton-rec.patch`

MoonBit 0.10.11 emits a self-recursive struct as an implicit singleton recursive
type. The artifact is valid according to `wasm-tools 1.258.0`, but
`Milky2018/wasm_core@0.14.0` resolves the field's typed self-reference before
inserting the current type into its parser table and raises `invalid heap type`.

The patch applies the placeholder strategy already used by `wasm_core` for an
explicit `rec` group to the implicit singleton branch. It is intentionally kept
as a standalone upstream-shaped diff rather than copied into MoonHostABI's
parser adapter.

The regression is exercised with the compiler-produced
`fixtures/artifacts/recursive.wasm`:

```powershell
pwsh -NoProfile -File scripts/apply-wasm-core-patch.ps1
moon test src/projector --target native
```

The application script is idempotent and refuses versions other than `0.14.0`
or a target source file whose normalized UTF-8/LF SHA-256 is neither the
reviewed baseline nor the reviewed patched result. Newline normalization keeps
the guard cross-platform while all non-newline source drift is rejected. Remove
this patch and the script after upgrading to an upstream release containing the
same fix.

## Upstream status and removal checklist

Checked on September 20, 2026:

- [Issue #512](https://github.com/Milky2018/wasmoon/issues/512) was closed as
  completed on September 18. Upstream commit
  [`f0b01bd9`](https://github.com/Milky2018/wasmoon/commit/f0b01bd9b23ce6d3d3e36e978df37bc85f5ab980)
  fixes implicit singleton self-references. [PR #519](https://github.com/Milky2018/wasmoon/pull/519)
  merged that fix into `main` on the same day.
- The [Mooncakes manifest for `wasm_core@0.16.0`](https://mooncakes.io/api-new/v0/manifest/Milky2018/wasm_core@0.16.0)
  reports `latest_version: 0.16.0`, published on September 16 at 03:59:19 UTC,
  before the fix. Its package SHA-256 is
  `21a895f3c1298f89c0e6143cf84dd4cd1a1d5b708fb649c36d0da9b4b468b289`.
- An isolated project that downloaded `0.16.0` without applying any downstream
  patch still raised `invalid heap type` for the implicit singleton below.
  The equivalent explicit `rec` wrapper parsed successfully, and the malformed
  mutability control was rejected: two controls passed, one regression failed.
  The published parser still calls `read_subtype()` before registering the
  singleton type.

The minimal valid implicit singleton used in the probe is:

```moonbit
let bytes = b"\x00asm\x01\x00\x00\x00\x01\x06\x01\x5f\x01\x63\x00\x00"
// (module (type (struct (field (ref null 0)))))
```

The closed issue is evidence of an upstream source fix, not evidence that the
published package contains it. Keep `wasm_core@0.14.0` and this patch for now;
do not switch the release to a development checkout.

When a published package contains the fix:

1. Test it in a clean dependency directory without running the patch script.
   Run the singleton probe, malformed-mutability test, real recursive fixtures,
   and type-reindexing compatibility tests.
2. Upgrade the pinned dependency only after those tests pass. Remove the patch
   application from `scripts/verify-spike.ps1` and `.github/workflows/release.yml`.
3. Update `scripts/validate_workflows.py` and its self-tests, which currently
   require dependency resolution before applying the patch. Then remove the
   patch file and its application script.
4. Run the full verification and release-package gates and validate a clean
   downstream consumer before publishing a new MoonHostABI version.
