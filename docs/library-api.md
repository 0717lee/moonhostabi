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

| Package            | Stable entry points                                                                    | Purpose                                                                      |
| ------------------ | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `src/model`        | `HostAbi`, `AbiFunction`, `AbiValueType`, `AbiResource`, diagnostics                   | Domain values, host resource inventory, and diagnostic codes                 |
| `src/wasm_adapter` | `parse_artifact`                                                                       | Parse compiled Wasm bytes                                                    |
| `src/projector`    | `analyze_host_abi` (`ProjectionAnalysis.resources`)                                    | Project function ABI and inventory table, memory, global, and tag boundaries |
| `src/resource`     | `ResourceAbi`, `create_lockfile`, `decode_lockfile`, `create_memory_contract`, `decode_memory_contract`, `generate_memory_contract` | Versioned memory resource lock and contract protocol                         |
| `src/lockfile`     | `canonicalize_host_abi`, `host_abi_sha256`, `create_lockfile`, `encode_lockfile`       | Canonical fingerprints and lockfiles                                         |
| `src/compat`       | `semantic_policy`, `strict_policy`, `compare_host_abi`, `compare_lockfiles`            | Compatibility decisions                                                      |
| `src/contract`     | `create_contract_draft`, `decode_contract`, `validate_contract`, `migrate_v1_contract` | Host contract validation                                                     |
| `src/generator`    | `generate_typescript_adapter`                                                          | Strict TypeScript adapter generation                                         |
| `src/verification` | `verify_artifact`, `encode_verification_report`                                        | Aggregate machine-readable release reports                                   |

The `cmd/moonhostabi` CLI targets `native`; reusable library packages can be
checked for supported MoonBit targets. The generated TypeScript adapter runs in
a JavaScript/TypeScript host; MoonHostABI does not provide a Wasm runtime or
application-specific host behavior.

## Memory contract guard

The first runtime resource extension is an explicit memory guard for consumers
that already have a memory contract. Import `assertMemoryContract` from the
runtime helper and call it after instantiation:

```ts
const memory = assertMemoryContract(instance.exports, {
  schemaVersion: 1,
  kind: "memory",
  exportName: "memory",
  minimumPages: 1,
  shared: false,
});
```

The guard checks the exported value, page count, sharedness, and contract shape,
and throws `MHA_ADAPTER_MISMATCH` on failure. It is intentionally separate from
the current function-only generated adapter until resource fields are added to
the canonical lockfile and contract schemas.

The same runtime boundary now has independent guards for tables, globals, and
exception tags: `assertTableContract`, `assertGlobalContract`, and
`assertTagContract`. They validate the JavaScript-observable instance and
contract fields, while leaving signature details that JavaScript cannot reflect
to the Wasm artifact analysis layer.

Lockfile schema v1 and contract schema v2 are versioned contracts. Treat
unknown schema versions, unsupported public Wasm items, and unrepresentable
values as failures. Keep generated adapters and lockfiles under the downstream
project's review and release process.

`ProjectionAnalysis.resources` is an inventory surface for non-function
boundaries. It records deterministic details for tables, memories, globals, and
tags so a host can make an explicit policy decision. The current JavaScript
adapter still fails closed for these resources; inventory support therefore does
not imply generated bindings.
