# Contributing to MoonHostABI

MoonHostABI changes should preserve the artifact-first boundary: compiled Wasm
host contracts are the input, and lockfiles, reports, adapters, or evidence
bundles are the observable outputs.

Before opening a pull request, run the focused checks from the repository root:

```powershell
moon fmt --check
moon check --deny-warn
moon test --target native --deny-warn
moon build --target all
pwsh -NoProfile -File scripts/judge-demo.ps1
pwsh -NoProfile -File scripts/verify-command.ps1
python -B scripts/validate_quickstart.py --repository . --self-test
python -B scripts/validate_workflows.py --repository . --self-test
```

Changes to ABI projection, lockfile encoding, diagnostics, contract schemas, or
generated files should include a fixture or regression test and update the
relevant schema or validation documentation. Keep unsupported host boundaries
fail-closed until the complete parser, model, adapter, runtime, test, and docs
path is implemented.

Use a focused commit message such as `feat: ...`, `fix: ...`, `test: ...`,
`docs: ...`, or `ci: ...`. Do not commit `.mooncakes`, `_build`, temporary
archives, credentials, or generated local reports.
