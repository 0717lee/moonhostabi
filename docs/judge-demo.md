# Judge demo

The demo shows the main MoonHostABI loop in a few minutes. Run it from a clean
repository root with the toolchain listed in [validation.md](validation.md):

```powershell
pwsh -NoProfile -File scripts/judge-demo.ps1
```

The script uses `fixtures/artifacts/externref.wasm` and its committed contract,
creates a lockfile, verifies the artifact against that lock, generates a strict
TypeScript adapter, and prints the generated file list. All temporary output is
created below the operating system temporary directory and removed at the end.

The expected final marker is:

```text
MOONHOSTABI_JUDGE_DEMO_STATUS=GO
```

For the compatibility failure branch, use the baseline lock produced by the
verification gate:

```powershell
pwsh -NoProfile -File scripts/verify-command.ps1
```

That gate compares the seeded `breaking_v1` and `breaking_v2` pair and expects
exit code `2` with `MHA_SIGNATURE_CHANGED`. The full evidence path is documented
in [validation.md](validation.md).
