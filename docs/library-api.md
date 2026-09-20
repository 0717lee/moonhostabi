# Library API guide

MoonHostABI exposes reusable MoonBit packages as well as the `native` CLI. The
CLI is the recommended integration point for release pipelines. Library users
can import the model, lockfile, compatibility, contract, generator, or
verification packages when they need an in-process gate.

Use the `0.5.0` release in a downstream MoonBit project:

```powershell
moon add 0717lee/moonhostabi@0.5.0
moon update
moon check
```

Version `0.5.0` introduces the resource surface v4, lockfile v4, contract v5, and
artifact-bound generator below. The `0.4.1` package does not include these APIs.
Check the [Mooncakes package](https://mooncakes.io/docs/0717lee/moonhostabi) and
[GitHub releases](https://github.com/0717lee/moonhostabi/releases) for published
versions.

The core package boundaries are:

| Package            | Stable entry points                                                                                                                 | Purpose                                                                      |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `src/model`        | `HostAbi`, `AbiFunction`, `AbiValueType`, `AbiResource`, diagnostics                                                                | Domain values, host resource inventory, and diagnostic codes                 |
| `src/wasm_adapter` | `parse_artifact`                                                                                                                    | Parse compiled Wasm bytes                                                    |
| `src/projector`    | `analyze_host_abi` (`ProjectionAnalysis.resources`)                                                                                 | Project function ABI and inventory table, memory, global, and tag boundaries |
| `src/resource`     | `ResourceAbi`, `create_lockfile`, `decode_lockfile`, `create_memory_contract`, `decode_memory_contract`, `generate_memory_contract` | Versioned memory resource lock and contract protocol                         |
| `src/lockfile`     | `canonicalize_host_abi`, `host_abi_sha256`, `create_lockfile`, `encode_lockfile`                                                    | Canonical fingerprints and lockfiles                                         |
| `src/compat`       | `semantic_policy`, `strict_policy`, `compare_host_abi`, `compare_lockfiles`                                                         | Compatibility decisions                                                      |
| `src/contract`     | `create_contract_draft`, `decode_contract`, `validate_contract`, `migrate_v1_contract`                                              | Host contract validation                                                     |
| `src/generator`    | `generate_typescript_adapter`, `generate_typescript_adapter_with_memory`, `generate_typescript_adapter_with_resources`              | Strict TypeScript adapter and resource preflight generation                  |
| `src/verification` | `verify_artifact`, `encode_verification_report`                                                                                     | Aggregate machine-readable release reports                                   |

The `cmd/moonhostabi` CLI targets `native`; reusable library packages can be
checked for supported MoonBit targets. The generated TypeScript adapter runs in
a JavaScript/TypeScript host; MoonHostABI does not provide a Wasm runtime or
application-specific host behavior.

## Use the artifact-bound resource API

Use `src/resource.project_resource_artifact(bytes)` to build a
`ResourceSurfaceV4`. It resolves imported and defined resource indices before
projecting the host imports and exports, including re-exports. Unlike the
module-only `project_resource_surface` helper, the artifact path also reads
memory flags directly from the Wasm bytes; the pinned parser does not retain
shared-memory metadata. The module-only helper marks that missing evidence as
unsupported.

The resource APIs introduced in `0.5.0` are:

| Operation | Entry points | Result |
| --- | --- | --- |
| Project | `project_resource_artifact` | `ResourceSurfaceV4` |
| Lock | `create_resource_lockfile_v4`, `encode_resource_lockfile_v4`, `decode_resource_lockfile_v4` | `ResourceLockfileV4` with artifact and surface fingerprints |
| Contract | `create_resource_contract_v5`, `encode_resource_contract_v5`, `decode_resource_contract_v5`, `validate_resource_contract_v5` | `ResourceContractV5` bound to the resource surface |
| Compare | `compare_resource_surfaces`, `encode_resource_comparison`, `render_resource_comparison_text`, `render_resource_comparison_markdown` | `ResourceComparison` schema v1 |
| Migrate | `lift_legacy_surface` | Known legacy resource types normalized; missing tag signatures remain unsupported |

`TagSignatureResource` stores resolved `params` and `results`, replacing the
legacy raw tag type index. `compare_resource_surfaces` classifies any known
resource-field change as `breaking`; unresolved types make the result `unknown`
even if the fingerprints match. See the [resource protocol](resource-protocol.md)
for wire fields, CLI commands, and migration behavior.

Call `src/generator.generate_typescript_adapter_with_resource_contract` with
the function ABI, function contract, resource surface, v5 resource contract,
and lowercase SHA-256 of the same artifact bytes. The CLI computes these inputs
together. Library callers must also derive them from the same artifact; the
generator takes the supplied fingerprint and does not receive bytes to hash.
Inspect the returned diagnostics before using the generated output.

This generator emits `HostImportsWithResources`, `ModuleExportsWithResources`,
and the equivalent `instantiate` and `instantiateWithResources` entrypoints.
Both check the artifact hash and validate imported resources with small Wasm
type probes before instantiating the application module, then validate its
exported resources. The probes have no code or start function and check real
resource types, declared limits, global mutability, and tag signatures.

Generation supports non-shared memory32 with 65,536-byte pages, table32 with
`funcref`/`externref` elements, scalar or `externref` globals, and tags with
scalar or `externref` parameters and no results. A wider analyzable surface
does not imply adapter support. Runtime SHA-256 needs `crypto.subtle`; use
Node.js 24 or a supporting browser in a secure context. Regenerate for any
artifact byte change, even when its resource surface is unchanged.

## Keep legacy guard APIs separate

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
and throws `MHA_ADAPTER_MISMATCH` on failure. Resource-aware generation remains
an explicit opt-in so existing function-only adapters retain byte-for-byte
compatibility while consumers adopt the versioned resource contracts.

The legacy runtime boundary also has independent guards for tables, globals, and
exception tags: `assertTableContract`, `assertGlobalContract`, and
`assertTagContract`. `generate_typescript_adapter_with_resources` can append a
resource-aware `instantiateWithResources` entrypoint and accepts these guards as
explicit callbacks. The guards validate JavaScript-observable instance and
contract fields, while leaving signature details that JavaScript cannot reflect
to the Wasm artifact analysis layer.

Lockfile schema v1 and contract schema v2 are versioned contracts. Treat
unknown schema versions, unsupported public Wasm items, and unrepresentable
values as failures. Keep generated adapters and lockfiles under the downstream
project's review and release process.

`ProjectionAnalysis.resources` is an inventory surface for non-function
boundaries. It records deterministic details for tables, memories, globals, and
tags so a host can make an explicit policy decision. Resource-aware generation
through `generate_typescript_adapter_with_resources` provides the legacy guard
callback contract; applications choose and wire its guards. The new
`generate_typescript_adapter_with_resource_contract` API uses the built-in
artifact and type checks described above.
