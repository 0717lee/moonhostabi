# MoonBit ecosystem follow-up

MoonHostABI occupies the compiled-artifact boundary in the MoonBit toolchain.
It complements source-level `.mbti` API checks by validating the Wasm imports,
exports, recursive Wasm-GC types, and host adapter contract that a JavaScript or
native embedding actually consumes.

The next ecosystem improvements are deliberately incremental:

1. Keep the lockfile and report schemas versioned so libraries can use
   MoonHostABI as a CI gate without depending on internal MoonBit source files.
2. Publish a small consumer example whenever the CLI or contract schema gains a
   new capability, and run that consumer against the Mooncakes package in CI.
3. Adopt a published `wasm_core` version containing the merged recursive-type
   fix, then remove the local compatibility patch after unpatched regression tests pass.
4. Add strict-policy and additional report-format support only when a concrete
   downstream use case and compatibility tests exist.
5. Extend host support one boundary at a time (for example, a specific table or
   memory contract), with a fixture, adapter behavior, failure diagnostics, and
   documentation for each addition.

An independent downstream smoke project is available at
[0717lee/moonhostabi-consumer](https://github.com/0717lee/moonhostabi-consumer).
Its CI resolves `0717lee/moonhostabi@0.5.0` from Mooncakes in a clean project.
[Run 35496580826](https://github.com/0717lee/moonhostabi-consumer/actions/runs/35496580826)
passed all three tests: the function ABI lock, recursive GC projection, and
resource v4 lock/v5 contract APIs with compatible and breaking-memory checks.
The parser compatibility issue
[wasmoon#512](https://github.com/Milky2018/wasmoon/issues/512) was closed as fixed
on September 18, 2026; [PR #519](https://github.com/Milky2018/wasmoon/pull/519)
merged the fix into `main`. MoonHostABI reported the issue; the upstream
maintainer implemented the fix. This is upstream adoption of a downstream bug
report, not a claim that MoonHostABI authored the upstream implementation.

As of September 20, the latest published `wasm_core@0.16.0` still fails the
unpatched singleton self-reference probe. Keep the pinned dependency and guarded
patch until a fixed package passes the
[removal checklist](../patches/README.md#upstream-status-and-removal-checklist).

The current project does not claim to replace MoonBit's compiler diagnostics,
source API guards, or a general Wasm runtime. Keeping those boundaries explicit
helps prevent overlap with existing packages and makes future integrations
reviewable.

## Local performance baseline

On 2026-09-08, using the pinned MoonBit toolchain and the committed
`fixtures/artifacts/externref.wasm` fixture on the development machine, three
cold process invocations produced the following wall-clock observations:

| Operation                            | Runs | Observed times         | Median |
| ------------------------------------ | ---: | ---------------------- | -----: |
| `inspect --format json`              |    3 | 331 ms, 285 ms, 294 ms | 294 ms |
| `verify --format json` with contract |    3 | 285 ms, 278 ms, 268 ms | 278 ms |

These are a reproducibility baseline, not a cross-machine performance claim.
Future benchmark changes should retain the fixture, toolchain identity, and
command line so the numbers remain comparable.
