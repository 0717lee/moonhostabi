# Production hardening implementation plan

> **Execution:** Use the host's available implementation workflow to execute this plan task-by-task when implementation is requested.

**Goal:** Bound artifact processing, measure representative workloads, remove measured duplicate work, and continuously exercise supported library/runtime paths.

**Architecture:** Keep existing wire formats, dependency pins and low-level API signatures. Add an allocation-light structural Wasm preflight and an additive checked parser API; route CLI and high-level resource/verification entrypoints through it. Reuse parsed/prepared values only within one operation, never cache mutable caller-owned objects by identity.

**Tech Stack:** MoonBit, existing native C shim, PowerShell 7, Python standard library, existing TypeScript/Playwright tooling.

## Contract and constraints

- Baseline: `33720320115c2fd2943367573f4674886fe40075` / published 0.5.1.
- Work locally on `codex/production-hardening`; no commits, pushes, releases or dependency upgrades.
- Preserve normal supported fixture output bytes and existing diagnostics/exit contracts. Budget violations must be explicit, not synthetic parser failures.
- `wasm_core` exposes no bounded reader and its `ParserError` constructors are private. Retain `parse_artifact` as a documented trusted-input compatibility API; add `parse_artifact_checked` with a project-owned error. Do not modify installed dependency caches to create unpublished safety guarantees.
- No new transports, platforms, service infrastructure or blanket caching. Limits are resource policies, not proof that arbitrary inputs are safe without process isolation.

## Task 1: checked parsing and CLI input boundaries

Files: `src/wasm_adapter/{parse,preflight,preflight_wbtest}.mbt`, package imports; `cmd/moonhostabi/{main,stderr}.c/mbt`; high-level parser callers in `src/verification/verify.mbt` and `src/resource/artifact_v4.mbt`.

1. Add small failing tests for compressed locals expansion, excessive nesting in every expression section, too many actual types within rec groups, truncated/cross-boundary bodies, and exact budget boundaries.
2. Run focused tests to record the red result without allocating dangerous ASTs.
3. Implement iterative structural preflight: bounded integer/section/body reads; counters for bytes, types, declared vector items, locals and instructions; explicit expression stack. Mirror the pinned parser's supported immediate shapes and reject unknown encodings.
4. Expose an additive checked parse entrypoint, wrapping true parse errors separately from input-limit failures. Keep legacy API compatibility.
5. Bound CLI file reads before allocation using the existing native shim, distinguish limit from I/O failures, and migrate high-level entrypoints.
   Structural budgets run before AST parsing; public function/tag expansion is
   checked after bounded AST parsing and before projection. The tested native
   default expression depth is 32. `verify_artifact_checked` also rejects the
   byte budget before hashing; legacy report-only verification keeps provenance.
6. Re-run exact-limit, one-over, malformed, legacy corpus and all-backend tests. Require valid checked/legacy projections to agree.

## Task 2: reproducible scale and application benchmark

Files: `scripts/benchmark-hostabi.ps1`, `scripts/benchmark_corpus.py`, associated standard-library tests, `docs/performance.md`.

1. Test deterministic corpus generation and valid Wasm encodings.
2. Build controllable corpora for byte volume, types, exports and resources; independently validate using existing wasm-tools when available.
3. Benchmark a supplied standalone native CLI (not `moon run`), with warmups, repeated samples, timeout, success/error checks, executable hash and environment metadata. Record median/P95 and OS memory observations without substituting zero for unavailable metrics.
4. Accept caller-provided real artifacts; keep generated data/results in ignored or OS-temp locations, never check in megabytes of synthetic data.
5. Capture baseline before optimization and compare identical cases after it. Benchmarks are evidence; do not add flaky CI percentage gates without calibrated data.

## Task 3: measured per-operation optimization

Files: `src/generator/{typescript,resource_contract_typescript}.mbt`, `src/resource/artifact_v4.mbt`, CLI orchestration as needed.

1. Preserve generated-output/canonical-report assertions and add meaningful equivalence regressions.
2. Avoid full Wasm parsing twice in resource-aware generation by composing already parsed Module with the raw metadata supplement.
3. Separate generator validation/preparation from final rendering so resource-aware generation emits and hashes final output once.
4. Use benchmark results to decide whether further indexing changes are warranted; preserve ordering, errors and validation boundaries.

## Task 4: continuous library/browser/consumer validation

Files: `scripts/verify-spike.ps1`, `scripts/verify-resources.ps1`, `runtime/browser/*`, `runtime/node/resource-adapter-e2e.mjs` only where shared runtime assertions are appropriate; consumer fixture/script under the main repository.

1. Execute JS and Wasm-GC library tests, not just checks, from the existing gate.
2. Exercise generated resource v4/v5 adapters in Chromium in a secure loopback context, including real resource operations and at least one rejection before application execution.
3. Add a reproducible downstream application workflow for ABI upgrade detection,
   adapter generation, strict TS compilation and actual host use; distinguish
   local-source integration from published-package verification. The pricing
   consumer exercises functions; the separate browser/Node gate exercises resources.
4. Keep scope at currently supported platforms/runtime; no invented adoption claims.

## Review and final acceptance

- Each implementation scope gets independent requirement review followed by quality review; parent audits the final diff.
- Run formatting, all-target checks/build, native/JS/Wasm-GC tests, input-limit regressions, scale corpus self-tests, generator byte equivalence, CLI/transaction gates, browser/resource E2E and full Spike where supported.
- Record exact benchmark method and results, including regressions and unmeasured properties. No claims of OOM/DoS-proof behavior or measured coverage percentage without evidence.
- Update README, change notes and performance/security boundaries; leave all changes local and report remaining production risks honestly.

## Initial local execution outcome

Implemented all four bounded scopes; independent parser/spec, native/generator,
benchmark and consumer/runtime reviews closed their actionable findings. Parent
validation on 2026-09-29 completed:

- Full Windows Spike: native 176/176, JS 139/139, Wasm-GC 139/139;
  CLI, reproduction bundle, Windows package/aggregate, transaction, fixtures,
  Node and Chromium (6 function + 27 resource tests), and source consumer GO.
- All-target build, release native build, formatting, quickstart/workflow
  validators, 14 benchmark self-tests, and diff whitespace checks passed.
- The native C shim passed Linux C11 `-Wall -Wextra -Werror` syntax checking;
  this is not a substitute for the pending exact-commit Linux runtime/CI run.
- Four serial 3-warmup/20-sample benchmark runs preserved all corpus response
  and generated-file hashes. Results and limitations are in `docs/performance.md`.

The stage establishes bounded input handling and repeatable verification, not
universal production maturity or a performance SLA. Two explicit follow-ups
remain: profile the observed 512-resource verification latency increase, and
calibrate type limits against larger real compiler artifacts (the 693 KB probe
exceeds the current type policy). No new version was committed or published.

## Follow-up contract: resource latency and real-artifact type policy

The user requested immediate treatment of both remaining findings. Scope is
controlled process/in-process profiling, the responsible resource/type paths,
budget calibration, regressions and the corresponding evidence/docs. Preserve
all earlier local work; no commits, remote writes, releases or dependency upgrades.
Acceptance: retain byte-identical supported outputs; remove or explain the
resource-512 regression with controlled repeated measurements; allow the known
real compiler artifact through the checked boundary without bypassing protection;
prove the chosen finite work limits with exact/one-over and adversarial cases.
Use all-target tests and the full local gate after code changes. No blanket
increase that simply trades type rejection for unbounded canonicalization.

The real compiled probe also exceeds 128 control levels, revealing that the
earlier depth-32 workaround is not adequate for this application. Extend the
existing version/source-hash-guarded dependency patch flow with an iterative
expression parser that preserves the full AST. This is a checked-in, disclosed
patch with clean-source application tests, not a hidden dependency-cache change.
Only after native-debug boundary tests pass may the expression budget admit the
real probe; retain a finite depth limit and all other resource budgets.

## Follow-up acceptance

Both investigated findings are closed locally:

- Alternating process pairs did not reproduce the serial resource-512 latency
  increase. The permanent runner now alternates AB/BA, records both sides, and
  requires identical response/generated bytes. Independent review approved it.
- Checked parsing admits the original 1,644-type, depth-256 compiled probe.
  Function ABI and the expected unsupported-tag diagnostic remain identical;
  resource lock/verify succeed. The current gate also rebuilds and admits a
  734,405-byte resource-test artifact with at least 1,631 actual types.
- Parsing is bounded at 2,048 types; complete canonicalization still has the
  old 1,024-type budget. Simple public function surfaces skip private type
  equivalence. Explicit control frames replace recursive expression parsing;
  256 levels pass native debug/release and 257 fail closed.
- The iterative parser is a checked-in, source-hash-guarded patch. Checked APIs
  require its dedicated symbol at compile time. Consumer workspaces apply the
  same patch rather than accidentally compiling the old recursive dependency.
- Independent type-policy and iterative-parser reviews approved the changes.
  Full Windows Spike: native 186/186, JS 149/149, Wasm-GC 149/149, 33 Chromium
  tests, CLI/bundle/package/transaction/resource gates and fresh source consumer
  all pass. Release-mode parser tests: 32/32. The 19 benchmark and 3 isolated
  patch-guard tests pass, including rejection before any partial mutation.

Exact measurements, executable identities and remaining finite policy limits
are documented in `docs/performance.md` and `docs/input-limits.md`. The main
checkout and published package remain unchanged; no commit/push/release was made.
