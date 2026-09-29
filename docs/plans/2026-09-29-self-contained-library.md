# Self-contained library implementation plan

> **Execution:** Use the host's available implementation workflow to execute this plan task-by-task when implementation is requested.

**Goal:** Install and use the candidate library through normal registry resolution without patching dependency caches, workspace replacement or a user-side PowerShell setup step.

**Architecture:** Ship the minimal corrected parser inside this module, retaining the published `wasm_core/types@0.14.0` model identity and the existing bounded adapter. Verify the actual `moon package` archive through a loopback-only test registry with a fresh Moon home and pristine upstream archives. This is pre-publication evidence, not a claim that the candidate already exists on public Mooncakes.

**Tech Stack:** MoonBit, existing native/JS/Wasm-GC targets, standard-library Python test tooling, existing CI and package commands.

## Contract

- Preserve all existing uncommitted production-hardening work in this worktree.
- No commit, push, remote publication, upstream PR, dependency version change or user-global configuration change.
- The current published upstream package lacks both needed fixes; the main branch contains them but is not the registry archive. Vendor only the 12 nonempty parser implementation files, not the whole Wasm library, and retain explicit Apache-2.0 provenance.
- Public `Module` and `ValueType` identity stays on `Milky2018/wasm_core/types`.
- The old `parse_artifact` exposes opaque upstream `ParserError`; an independent implementation cannot construct that type. No different preference has arrived after the optional question, so local implementation proceeds with the announced recommended assumption: unify on owned `ArtifactError`, preserve function name and Module identity, explicitly document the error-type migration for the next release. No fake errors, unsafe fallback, or silent compatibility claim.
- Keep both fixes, 256-frame parsing and all input/canonicalization budgets.

## Task 1: package-owned parser

Create `src/internal/wasm_parser/` and `third_party/wasm_core_parser/` with minimal imports, original provenance, license text, changed-file notices and a reproducible source inventory. Start from the checksum-verified 0.14.0 archive plus the two reviewed fixes. Remove the now-unnecessary patch-capability wrapper. Existing semantic/AST/boundary regressions must remain meaningful.

## Task 2: clean installation proof

Create a standard-library package-consumer gate and an ordinary consumer module. Package the current source, serve the archive from an ephemeral loopback registry, and run real `moon add`, `moon check`, `moon test` and the example on native/JS/Wasm-GC. Use an isolated child-process Moon home and the existing pinned toolchain. The resolver must download/checksum/extract the artifact itself: no moon.work, path override or manual dependency injection. Record archive and installed source identity, and verify pristine dependencies remain unchanged.

## Task 3: integration and migration

Connect the adapter to the built-in parser according to the selected public-error contract. Remove dependency patching from CI, source-consumer and release workflows; remove obsolete patch application machinery once provenance is preserved. Update dependency-resolution validators, install instructions, ownership/originality notices and change notes. Keep historical test records labelled as historical.

## Task 4: verification and review

Retain a pre-wiring package archive and replay it through the clean-consumer gate to establish the original failure. Run focused API/AST/recursive/depth tests, all backend tests/build, package provenance checks, clean registry installation, the existing source consumer and full Windows Spike. Independently review parser integration and the installation harness. Public-registry installation of a newly released version remains a separate post-publication gate requiring release authorization.

## Local result, 2026-09-29

Tasks 1-4 passed locally. The unmodified pre-wiring package failed with the
missing patch-only parser entrypoint; the bundled candidate passed real
registry installation and four consumer tests on each of native/JS/Wasm-GC.
The full Windows Spike passed with 189/152/152 library/CLI tests and 33 Chromium
tests, plus the existing source consumer and all package/transaction gates.
Native release parser tests (35), all-target build/check, provenance checks
and both independent reviews passed. See `docs/validation.md` for evidence.

The old patch application script and its dedicated tests were retired;
historical diffs remain, and the worktree's two modified dependency sources
were restored to their exact original 0.14.0 content. The fixed parser now ships
with the module. No project commit, push, release, dependency upgrade, or
user-global configuration change was made; original main remains unchanged.
The error-type migration requires a new version before public publication.
