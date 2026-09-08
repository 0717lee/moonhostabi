# Library API guide

MoonHostABI exposes reusable MoonBit packages as well as the `native` CLI. The
CLI is the recommended integration point for release pipelines. Library users
can import the model, lockfile, compatibility, contract, generator, or
verification packages when they need an in-process gate.

Add the published module to a downstream MoonBit project:

```powershell
moon add 0717lee/moonhostabi@0.1.1
moon update
moon check
```

The core package boundaries are:

| Package | Stable entry points | Purpose |
| --- | --- | --- |
| `src/model` | `HostAbi`, `AbiFunction`, `AbiValueType`, diagnostics | Domain values and diagnostic codes |
| `src/wasm_adapter` | `parse_artifact` | Parse compiled Wasm bytes |
| `src/lockfile` | `canonicalize_host_abi`, `host_abi_sha256`, `create_lockfile`, `encode_lockfile` | Canonical fingerprints and lockfiles |
| `src/compat` | `semantic_policy`, `strict_policy`, `compare_host_abi`, `compare_lockfiles` | Compatibility decisions |
| `src/contract` | `create_contract_draft`, `decode_contract`, `validate_contract`, `migrate_v1_contract` | Host contract validation |
| `src/generator` | `generate_typescript_adapter` | Strict TypeScript adapter generation |
| `src/verification` | `verify_artifact`, `encode_verification_report` | Aggregate machine-readable release reports |

The `cmd/moonhostabi` CLI targets `native`; reusable library packages can be
checked for supported MoonBit targets. The generated TypeScript adapter runs in
a JavaScript/TypeScript host; MoonHostABI does not provide a Wasm runtime or
application-specific host behavior.

Lockfile schema v1 and contract schema v2 are versioned contracts. Treat
unknown schema versions, unsupported public Wasm items, and unrepresentable
values as failures. Keep generated adapters and lockfiles under the downstream
project's review and release process.
