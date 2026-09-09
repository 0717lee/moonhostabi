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
3. Track the `wasm_core` recursive-type parser fix upstream and remove the local
   compatibility patch as soon as a released dependency contains it.
4. Add strict-policy and additional report-format support only when a concrete
   downstream use case and compatibility tests exist.
5. Extend host support one boundary at a time (for example, a specific table or
   memory contract), with a fixture, adapter behavior, failure diagnostics, and
   documentation for each addition.

An independent downstream smoke project is available at
[0717lee/moonhostabi-consumer](https://github.com/0717lee/moonhostabi-consumer).
Its CI resolves `0717lee/moonhostabi@0.4.0` from Mooncakes in a clean project.
The parser compatibility issue is tracked upstream in
[wasmoon#512](https://github.com/Milky2018/wasmoon/issues/512).

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
