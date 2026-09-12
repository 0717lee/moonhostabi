# MoonHostABI judge quickstart

_A short, repository-root walkthrough for reproducing the evidence on PowerShell 7._

---

## 🎯 What this proves

MoonHostABI turns a compiled MoonBit Wasm-GC artifact into a reviewable host ABI:
the lock captures a baseline, `verify` compares the current bytes and ABI, and a
deterministic bundle carries the inputs needed to reproduce that decision. The
commands below use repository-owned fixtures and public scripts; they do not
depend on a machine-specific path or an uncommitted file.

The shortest judge path is three focused checks:

| Check | What it exercises | Success marker |
| --- | --- | --- |
| CLI evidence | Native CLI grammar, report, exit codes, and smoke cases | `MOONHOSTABI_VERIFY_STATUS=GO` |
| Reproduction bundle | Seven fixed entries, hashes, deterministic bytes, and mutation rules | `MOONHOSTABI_BUNDLE_STATUS=GO` |
| Platform package | Current-platform archive, extracted CLI smoke, and aggregate negatives | `MOONHOSTABI_PACKAGE_STATUS=GO` |

## ⚙️ Prerequisites

Run every command from the repository root. Use PowerShell 7 or newer and the
tool versions recorded in [the validation record](validation.md). The complete
Spike additionally uses Node.js, npm, and the pinned Chromium build; the three
focused checks keep their published test outputs outside the repository and
remove those outputs when they finish.

Check the working tree before starting:

```powershell
git status --short
```

For a judge run, the command should print no lines. Do not add a path argument or
an environment override; each script resolves its repository-relative inputs.

## 🚀 Run three checks

### CLI evidence

This is the fastest way to see the six-section report contract and real-process
negative cases:

```powershell
pwsh -NoProfile -File scripts/verify-command.ps1
```

Expected final marker:

```text
MOONHOSTABI_VERIFY_STATUS=GO
```

To create a standalone versioned host-resource lock, run the native CLI with a
compiled artifact:

```powershell
moon run cmd/moonhostabi --target native resource-lock-v3 <artifact.wasm> --out <resource-lock-v3.json>
moon run cmd/moonhostabi --target native resource-verify <artifact.wasm> --against <resource-lock-v3.json> --format json
```

`resource-verify` exits `0` when the canonical resource surface is unchanged
and `2` when it changes. The v3 CLI serializes memory metadata and keeps table,
global, and tag inventory entries in the explicit `unsupported` list. This is a
deliberate fail-closed boundary: the command does not infer JavaScript binding
semantics for those resource kinds.

To opt into resource-aware TypeScript generation, provide a validated v4
resource contract alongside the artifact:

```powershell
moon run cmd/moonhostabi --target native generate fixtures/artifacts/externref.wasm --resource-contract <resource-contract.json> --out <generated-directory>
```

The generated directory contains `adapter.ts`,
`moonhostabi.contract.json`, and `moonhostabi.manifest.json`; resource guards
are wired only through the explicit contract and callbacks supplied by the
consumer.

The script also prints the individual help, version, timeout, exit-code,
canonical-report, Unicode-path, and no-host-execution markers. A successful
exit code and the marker are both required.

### Reproduction bundle

Run the deterministic bundle gate over the committed `externref` fixture:

```powershell
pwsh -NoProfile -File scripts/verify-reproduction-bundle.ps1
```

Expected final marker:

```text
MOONHOSTABI_BUNDLE_STATUS=GO
```

The gate builds two independent archives, compares every byte after extraction,
checks the manifest's six payload hashes, and runs a controlled mutation. See
the [bundle layout and mutation contract](../fixtures/reproduction/README.md)
for the fixed entry names.

### Platform package

Run the package gate from the same clean root:

```powershell
pwsh -NoProfile -File scripts/verify-release-packaging.ps1
```

Expected final marker on the locally observed Windows path:

```text
MOONHOSTABI_PACKAGE_STATUS=GO
```

The gate executes the extracted native CLI with `--version`, `--help`, and
`verify`, then validates archive layout, metadata, aggregate manifests, and
failure cleanup. Read [the release dry-run guide](releasing.md) for the fixed
archive names and the non-publishing workflow boundary.

## 🔍 Read the evidence

`verify` emits one canonical report. Its six top-level evidence sections answer
different questions:

| Section | Question answered |
| --- | --- |
| `artifact` | Were the exact artifact bytes parsed and projected? |
| `baseline` | What lock and fingerprints were used for comparison? |
| `provenance` | Do artifact and canonical ABI fingerprints match the baseline? |
| `compatibility` | Is the semantic host ABI compatible or breaking? |
| `contract` | Does the supplied host contract match the current ABI? |
| `generator` | Can the supported adapter be represented deterministically? |

Open the [machine-checked report example](report-schema.md#verified-example) to
see the canonical shape instead of copying a report into this guide. The
reproduction bundle contains `manifest.json` plus six payloads: its
`validation.json` is the real `verify` stdout, while the artifact, lock,
contract, adapter, and commands provide the inputs and replay material. The
manifest indexes those payload hashes and sizes. The [validation record](validation.md)
connects the focused markers to the broader Spike.

## 📍 Platform boundary

The committed local evidence is deliberately split:

- **Windows local:** native CLI, deterministic ZIP, extracted smoke, and focused
  package negatives are observed and marked `GO`.
- **Linux archive path:** tar/gzip metadata and aggregate behavior are checked by
  the local static/mock path; this is not a Linux native-binary result.
- **Remote Linux native:** covered by successful public Verification matrix run
  `34081779933` (see the repository's Actions history). No tag or GitHub Release
  is implied by these markers.
- **Release dry run:** passed for Linux, Windows, and aggregate in run
  `34081936398`; it is separate from the Verification matrix and does not publish
  a GitHub Release.
- **Mooncakes publication:** `0717lee/moonhostabi@0.4.0` is the published release and passed the package self-check. Future versions must repeat the same checks before publication.

For a short live demonstration, run the repository-owned [judge demo](judge-demo.md).
It uses the committed `externref` fixture to show inspection, lock creation,
compatibility verification, and typed adapter generation in one temporary output
directory.

The quickstart commands do not invoke a remote service or require a hidden
checkout setting. A green local marker is evidence for the named local check
only.

## 🛠️ Troubleshooting

### A script cannot find `moon`

Install the exact MoonBit toolchain listed in `validation.md`, reopen PowerShell,
and rerun the command from the repository root. The scripts intentionally stop
when the tool version is different.

### The report has exit code `2`, `3`, or `4`

Inspect the canonical stdout report and its `outcome` field. Use the section
definitions in [report-schema.md](report-schema.md) rather than parsing the
human-readable message; these codes represent a breaking, invalid/unknown, or
adapter/contract result.

### An output path already exists

Choose a new temporary output path and rerun the focused command. The gates
refuse to replace an existing archive or generated directory so that an old
result cannot be mistaken for a fresh one.

### The browser or full Spike check fails

Run the three focused checks first. If they pass, install the Node/npm and
Chromium versions in [validation.md](validation.md), then run the full gate:

```powershell
pwsh -NoProfile -File scripts/verify-spike.ps1
```

The full gate should end with `MOONHOSTABI_SPIKE_STATUS=GO`; the remote matrix
result is recorded separately from this local command.

## 🔗 References

- [Validation evidence](validation.md)
- [Verification report schema](report-schema.md)
- [Reproduction bundle guide](../fixtures/reproduction/README.md)
- [Release dry-run guide](releasing.md)
- [Judge demo](judge-demo.md)
- [MoonBit ecosystem follow-up](ecosystem.md)
