# Contributing to MoonHostABI

MoonHostABI changes should preserve the artifact-first boundary: compiled Wasm
host contracts are the input, and lockfiles, reports, adapters, or evidence
bundles are the observable outputs.

Before opening a pull request, run the focused checks from the repository root:

```powershell
moon fmt --check
moon check --deny-warn
moon test --target native --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target all
pwsh -NoProfile -File scripts/judge-demo.ps1
pwsh -NoProfile -File scripts/verify-command.ps1
python -B scripts/validate_quickstart.py --repository . --self-test
python -B scripts/validate_workflows.py --repository . --self-test
python -B -m unittest discover -s scripts -p test_benchmark_corpus.py -v
pwsh -NoProfile -File scripts/verify-consumer.ps1
python -B scripts/verify-package-consumer.py
```

Normal dependency setup is `moon update` followed by `moon check`; the current
source bundles its parser fixes. The source consumer uses a `moon.work` override
on Windows. The separate package consumer gate builds and installs the local
candidate through an isolated loopback registry and fresh `MOON_HOME`, then
runs downstream checks without a workspace override or dependency-cache edits.
See [consumer evidence boundaries](docs/consumer-example.md).

Changes to `src/internal/wasm_parser` must retain the upstream license and
attribution, update the affected modification notices and
[provenance record](third_party/wasm_core_parser/README.md), and exercise the
parser regressions and package consumer gate. The historical diffs in `patches/`
are not applied during setup.

Changes to ABI projection, lockfile encoding, diagnostics, contract schemas, or
generated files should include a fixture or regression test and update the
relevant schema or validation documentation. Keep unsupported host boundaries
fail-closed until the complete parser, model, adapter, runtime, test, and docs
path is implemented.

Use a focused commit message such as `feat: ...`, `fix: ...`, `test: ...`,
`docs: ...`, or `ci: ...`. Do not commit `.mooncakes`, `_build`, temporary
archives, credentials, or generated local reports.
