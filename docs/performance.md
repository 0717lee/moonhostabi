# Native CLI performance measurements

The benchmark measures an already-built native MoonHostABI executable against
a reproducible synthetic Wasm corpus. It checks every result before accepting
a timing sample. It does not build the executable or invoke `moon run` inside
the measured workload.

The measurements below are historical local observations from September 29,
2026, before the `0.6.0` version change and final bundled-parser cleanup. They
retain the exact measured binary hashes and reported `0.5.1` identities; they
are not measurements of the final `0.6.0` release executable. Run the benchmark
with that executable to produce a release-specific result.

## Run

Requirements: Python 3.10 or newer, PowerShell 7, a native MoonHostABI executable,
and `wasm-tools`. No additional Python packages are required. The runner locates
`wasm-tools` on `PATH` or as a single executable under `.tools/wasm-tools`;
`-WasmToolsPath` selects an explicit executable.

Build once before benchmarking, then provide the exact executable:

```powershell
moon build cmd/moonhostabi --target native --release
pwsh -NoProfile -File scripts/benchmark-hostabi.ps1 `
  -CliPath _build/native/release/build/cmd/moonhostabi/moonhostabi.exe `
  -WasmToolsPath <path-to-wasm-tools> `
  -OutputDirectory _build/benchmarks/native-release
```

On Unix-like systems use the executable without the `.exe` suffix. The
benchmark requires `-CliPath`; it never silently substitutes a different build.
The default is three warmups followed by 20 measured samples for each case.
A short smoke measurement uses `-Warmups 3 -Samples 3`; its small sample count
is not sufficient for performance claims. `-TimeoutSeconds` may reduce the
30-second process limit, but cannot increase it.

For a comparison, add `-BaselineCliPath <old-native-executable>`. The runner
alternates baseline/candidate then candidate/baseline for each warmup and sample,
using identical input bytes and one shared baseline-created resource lock or
contract. Both sides must produce identical response and generated-file hashes.
This strict mode compares implementation changes preserving output bytes, not
releases that intentionally change formats or generator version metadata.
`-Case resources-512` selects a single workload; Python's repeatable `--case`
selects several:

```powershell
python -B scripts/benchmark_corpus.py run `
  --cli-path <candidate-executable> --baseline-cli-path <baseline-executable> `
  --case resources-512 --case types-512 --warmups 5 --samples 30
```

Candidate report fields remain unchanged. `baselineCli` identifies the old
binary, each case's `baseline` retains its complete samples/argv/memory/hashes,
and `comparison.pairs` records the actual AB/BA order and paired differences.
Both executables and the common inputs are checked for mutation. Compare paired
observations before attributing a serial-run timing difference to changed code.

`-OutputDirectory` must be a new directory under the repository's ignored
`_build` directory or the system temporary directory. If omitted, the runner
creates `_build/benchmarks/<UTC timestamp>`. Each run retains generated Wasm,
its manifest, resource locks/contracts, and `results.json`. An incomplete run records
`status: "failed"` and exits with failure; previously completed cases remain
available for diagnosis. Initialization failures before a run starts can exit
without a result file.

To include an actual compiled artifact, add:

```powershell
pwsh -NoProfile -File scripts/benchmark-hostabi.ps1 `
  -CliPath <native-executable> `
  -ArtifactPath fixtures/artifacts/scalar.wasm
```

The additional case runs `inspect`, requires exit 0 and a valid schema-1
function surface, and verifies deterministic output across repetitions.
Choose an artifact supported by the function projection. Artifacts with public
resources should instead use the resource workflow; they are not accepted as
a successful `inspect` sample by this option. The report identifies the supplied
artifact by its absolute path, byte length, and SHA-256. These measurements
represent only that artifact, not all MoonBit programs.

The generator and benchmark can also be invoked directly:

```powershell
python -B scripts/benchmark_corpus.py generate --output-directory _build/benchmark-corpus
python -B scripts/benchmark_corpus.py run --cli-path <native-executable> --samples 20
python -B -m unittest discover -s scripts -p test_benchmark_corpus.py -v
```

## Corpus

Every module is generated directly from the Wasm binary format with Python's
standard library, then independently validated by `wasm-tools validate` before
any benchmark workload starts. Generation does not use MoonHostABI or its Wasm
parser. The versioned manifest records all bytes by SHA-256; `corpusSha256`
hashes the canonical manifest identity, independent of the output directory.
Suite version 2 runs 16 workloads against the same 14 modules: the original
inspection/verification cases plus two resource-aware generation cases.

| Dimension | Values | Measured command and expected result |
| --- | --- | --- |
| Custom-section payload bytes | 64 KiB, 1 MiB, 8 MiB | `inspect`; one empty function export |
| Function exports | 32, 128, 512, 2048 | `inspect`; exact named exports sharing one empty function |
| Distinct function types | 32, 128, 256, 512 | `inspect`; one empty function export, other types unused |
| Memory exports | 32, 128, 512 | `resource-verify`; unchanged resource surface |
| Resource-aware generation | 512 function exports; 128 memory exports | `generate --resource-contract`; three deterministic output files |

The payload dimension varies one custom-section payload; total artifact size
also includes its section framing and a minimal function module. The export
dimension changes names and export entries without duplicating function code.
Distinct types use one empty signature and unique five-parameter signatures
over `i32`, `i64`, `f32`, and `f64`. This measures processing of distinct declared
types with minimal code; it does not measure GC graph complexity. Even the
512-type case has fewer than 3,100 type and parameter entries, below this
checkout's 65,536 declared-item budget. All cases also fit its 32 MiB byte and
2,048-type structural limit. These [input limits](input-limits.md) are included
in `0.6.0`; the historical candidate measurements below predate that release.

The resource dimension exports one defined memory under distinct names. It
measures resource-surface cardinality, not allocation of many memories. The
memory has a zero-page minimum and one-page maximum. Before timing, the runner
creates a v4 lock and checks all expected export names and bounds. Each timed
`resource-verify` invocation must report `compatible`, exit 0, and no changes.

The generation workloads reuse `exports-512.wasm` and `resources-128.wasm`.
Each prepares a v5 resource contract outside timing; the function-only artifact
has an empty resource surface. Every warmup and sample generates to a fresh
child directory. After timing, the runner checks the exact three-file set,
response/manifest/contract agreement, and manifest hashes against actual bytes.
All three file hashes must also match across repetitions. Cleanup removes only
the expected regular files and that exact child directory outside timing; file
hashes remain in the report. Short output leaf names leave room for the native
CLI's sibling staging suffix on Windows; keep the chosen run directory short
if the host's native filesystem calls impose a path-length limit.

These synthetic modules isolate input dimensions. They are not MoonBit
compiler output and do not establish performance on production artifacts.
`-ArtifactPath` adds a separate real-artifact observation with its own identity.
Neither path instantiates Wasm or executes application code.

## Measurement and interpretation

Each warmup and sample launches a fresh native process. Timing uses
`time.perf_counter_ns()` around process creation, execution, and captured stdout
and stderr. Thus it includes startup, file reads, parsing, analysis, JSON output,
and pipe capture. Generation also includes rendering and writing the output
files. It excludes builds, corpus generation, independent Wasm validation,
resource-lock/contract preparation, result assertions, output cleanup,
memory-counter queries, and statistics.
This is a warm filesystem/process workload after the configured warmups, not a
cold-cache measurement or an in-process parser microbenchmark.

Every command must exit 0 with empty stderr. Known synthetic function surfaces
are checked exactly. Resource locks and verification reports receive semantic
checks. Output SHA-256 must remain identical across every repetition, and the
runner checks that the artifact and CLI executable have not changed during the
run. A process exceeding the limit is killed and reaped before the run fails.

`results.json` records the CLI absolute path, version, executable SHA-256,
validator version and SHA-256, OS, machine architecture, processor description,
logical CPU count, Python version, corpus identity, command arguments, raw sample
milliseconds, median, and P95. P95 uses the nearest-rank rule:
`sortedSamples[ceil(0.95 * sampleCount) - 1]`. For three samples this is the
maximum; retain the raw measurements when interpreting small runs.

On Windows, the runner reads the OS-maintained `PeakWorkingSetSize` using
`GetProcessMemoryInfo` after process exit while its handle remains open. This
is the peak resident working set, not total virtual memory or allocated heap.
The counter query is outside timing and needs no third-party package. A test
launches a child with a known 32 MiB allocation and checks that its recorded
peak is at least that large.

Each measured process has a `memorySamples` observation with method, byte count,
and any failure reason. A case's `peakMemoryBytes` is the maximum available OS
peak across its measured samples, excluding warmups; `memorySamplesAvailable`
makes incomplete observation explicit. Unsupported platforms and counter
failures produce `null` with a reason, never a fabricated zero. Linux sampling
is not implemented, and no sampled working-set value is presented as an exact
peak. The original suite-version-1 quick baseline predates memory observation.

For comparisons, keep the machine, build profile, corpus hash, sample counts,
and background load comparable. Record both executable hashes and keep both
result files. A single local result, particularly a three-sample smoke run,
does not prove a speedup or a production latency bound. The corpus does not
cover every recursive GC shape, failure path, resource kind, or runtime host.
GPU, database, and web-application tuning are outside this tool's workload.

## Historical initial serial comparison, 2026-09-29 (superseded interpretation)

Four suite-version-2 runs completed on Windows x86_64, build 26200,
AMD64 Family 25 Model 117 Stepping 2 (16 logical CPUs), Python 3.11.7.
Both executables are native release builds using the pinned MoonBit toolchain.
The comparison order was published baseline, hardened source, hardened source,
published baseline. Each run used 3 warmups and 20 samples for all 16 workloads.
Builds and the full verification suite finished before timing began; the
desktop was not an isolated performance runner.

- Published `0.5.1` executable SHA-256:
  `595de0e79ff7fa4dd5c252fc64c7a7e4051f1719b05ff8c29b6fbdd904c888a8`.
- Then-unreleased local executable SHA-256:
  `8898a16709658ffd597951a2761ec418b7db0e35e6c6ef90ded688c6316be843`.
- Identical corpus SHA-256 in every run:
  `95e68e4c437828c6065827e8d1dd3286783116cf691a8b92b4bbeb83a188e43e`.
- Raw local records are `_build/benchmarks/{old20,new20,new20r,old20r}/results.json`.
  They are ignored run artifacts, not files distributed with the repository.
  The measured unreleased binary reported `0.5.1`; its distinct digest identifies
  this local comparison, not a new published release.

Selected first-pair observations (milliseconds; peak resident working set in MiB):

| Workload | Baseline median / P95 | Hardened median / P95 | Baseline / hardened peak MiB |
| --- | ---: | ---: | ---: |
| Inspect 8 MiB custom payload | 33.753 / 44.192 | 30.558 / 34.270 | 15.598 / 15.621 |
| Inspect 512 distinct types | 114.245 / 128.400 | 117.165 / 139.645 | 22.105 / 22.117 |
| Verify 512 memory exports | 49.984 / 61.313 | 64.595 / 75.587 | 9.645 / 9.672 |
| Generate 512 function exports | 59.204 / 67.750 | 59.663 / 78.137 | 9.805 / 9.551 |
| Generate 128 memory exports | 47.831 / 51.515 | 50.436 / 60.576 | 9.465 / 9.449 |

All 16 response hashes and all three generated-file hashes in both generation
cases agree across all four runs. Removing the discarded base render and second
parse therefore preserved this corpus's observable bytes. The bounded reader
no longer adds a full payload-sized copy: the 8 MiB case's peak remains close
to the old reader rather than growing by another 8 MiB.

There is **no general speedup claim**. In the reverse-order pair, generation of
512 function exports measured 55.343 ms hardened versus 60.923 ms baseline, but
the first pair showed no latency improvement. More importantly, verification
of 512 memory exports measured 58.121 ms hardened versus 49.979 ms baseline;
the two pairs show a 16–29% increase in median wall time for that workload.
Keep this as an open profiling target. These observations do not identify the
cause or distinguish all preflight costs from OS/process noise. The 512-type
case also retains the existing expensive type-normalization path; this change
bounds its input size rather than replacing that algorithm.

### Compiled-artifact boundary probe

A separate, untimed-for-comparison check used an existing MoonBit resource test
binary of 693,081 bytes, SHA-256
`b6cd53f02dffa74980381a6837828e2af6ba14a8994b5f65ef1113e3c922b015`.
The published CLI projected it and returned exit 3 for the unsupported public
`exception.tag` boundary. The hardened CLI instead returned exit 3 with
`MHA_INPUT_LIMIT` / `types`, before projection, because it exceeds 1,024 types.
This is a deliberate policy restriction and a real compatibility cost, **not
a faster successful analysis**. The synthetic 8 MiB payload case does not
establish support for similarly sized compiler output. Wider production
artifacts need separate budget calibration and type-path profiling before
raising the default or claiming general large-artifact readiness.

## Historical follow-up: controlled pairs and bounded real-artifact admission

The earlier 16–29% resource-512 increase did not reproduce with alternating
process pairs. Two preliminary 5-warmup/30-sample runs compared the unchanged
hardening binary against the published CLI: baseline/candidate medians were
44.203/44.066 ms and 45.445/44.852 ms. Startup medians were also comparable.
The serial observations above are retained as history, not evidence of a
confirmed parser-induced regression. No unrelated resource-comparison rewrite
was made to compensate for that unconfirmed attribution.

After the type-policy fix and iterative parser patch, the full paired suite ran
all 16 workloads with 5 warmups and 30 samples per side. The corpus identity and
published baseline binary were unchanged. That local native release-build digest is
`b2548b4c3f1a17df1f6a6185e3ea0c00999c3e06f935f7d543b3835b361f41e4`;
the final post-format/build record is `_build/benchmarks/paired3/results.json`.
An earlier complete paired run is retained in `paired2`. Every response and
all generated files matched the baseline across every pair.

| Workload | Baseline median / P95 ms | Candidate median / P95 ms | Median paired change |
| --- | ---: | ---: | ---: |
| Verify 512 memory exports | 43.924 / 50.104 | 44.127 / 52.499 | +1.01% |
| Inspect 512 private types | 83.760 / 118.914 | 26.897 / 33.609 | -69.08% |
| Generate 512 function exports | 60.433 / 84.161 | 53.536 / 73.854 | -7.40% |
| Generate 128 memory exports | 45.673 / 53.857 | 45.738 / 56.028 | +0.36% |

The median of paired percentage changes is not the percentage difference of
the two medians. The resource verification result is effectively comparable
on this host; small differences and generation tail latency still vary. The
large private-type improvement has a specific cause: public functions without
indexed references or supertypes no longer trigger full-module type equivalence.
Inputs needing that algorithm keep its original 1,024-type budget; the separate
structural limit is now 2,048 types, not an unbounded bypass.

The same 693,081-byte real compiler artifact contains 1,644 types and a maximum
control depth of 256. At measurement time, an explicit-stack dependency patch
removed recursive expression parsing, and checked parsing required that patch
at compile time. Version `0.6.0` distributes those fixes in its bundled parser;
dependency-cache patching is no longer required. The measured artifact reached
complete function-ABI projection with **identical
stdout and tag diagnostic bytes**, instead of being rejected by the input
budget. Its `resource-lock-v4` and `resource-verify` workflows also passed.

In a separate alternating 5-warmup/20-sample inspection comparison, baseline
median/P95 were 936.817/1005.199 ms versus 47.283/55.420 ms for the candidate.
Observed peak working sets were 135,344,128 versus 15,187,968 bytes. Both
inspection processes intentionally return exit 3 for the same unsupported
public tag: this measures complete ABI analysis, **not successful function-only
adapter support or application execution**. Raw evidence is
`_build/real-paired-final.json` (the earlier repeat is `real-paired.json`).
The source gate continuously rebuilds a large compiler
artifact and verifies its resource workflow; no large binary is checked in.

These local observations close the two investigated findings. They do not
remove the finite [input limits](input-limits.md), establish arbitrary typed-GC
scalability, or substitute for exact-commit Linux/Windows release CI.
