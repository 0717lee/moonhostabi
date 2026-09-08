///|
fn memory_resource_diagnostics(
  contract : @resource.MemoryContract,
) -> Array[@model.Diagnostic] {
  let diagnostics : Array[@model.Diagnostic] = []
  if contract.schema_version != 3 {
    diagnostics.push(
      generator_diagnostic(
        "resourceContract.schemaVersion", "memory resource contract must use schema version 3",
      ),
    )
  }
  if contract.abi_sha256.length() != 64 {
    diagnostics.push(
      generator_diagnostic(
        "resourceContract.abiSha256", "memory resource contract must contain a SHA-256 fingerprint",
      ),
    )
  }
  for memory in contract.memories {
    if memory.path.is_empty() || memory.name.is_empty() {
      diagnostics.push(
        generator_diagnostic(
          "resourceContract.memories", "memory resource path and name must not be empty",
        ),
      )
    }
    if memory.minimum_pages < 0L {
      diagnostics.push(
        generator_diagnostic(
          "resourceContract.memories[{memory.path}].minimumPages", "memory minimum pages must be non-negative",
        ),
      )
    }
  }
  diagnostics
}

///|
fn render_memory_resource_runtime(
  contract : @resource.MemoryContract,
) -> String {
  let entries = contract.memories.map(fn(memory) {
    let shared = if memory.shared { "true" } else { "false" }
    "{ exportName: \{Json::string(memory.name).stringify()}, minimumPages: \{memory.minimum_pages}, shared: \{shared} }"
  })
  let lines = [
    "",
    "const memoryContracts = [\{entries.join(", ")}] as const;",
    "",
    "function assertMemoryResources(exports: WebAssembly.Exports): void {",
    "  const root = exports as unknown as Record<string, unknown>;",
    "  for (const contract of memoryContracts) {",
    "    if (!Object.prototype.hasOwnProperty.call(root, contract.exportName) ||",
    "      !(root[contract.exportName] instanceof WebAssembly.Memory)) {",
    "      throw new Error(`MHA_ADAPTER_MISMATCH: module export exports[${contract.exportName}] must be a WebAssembly.Memory`);",
    "    }",
    "    const memory = root[contract.exportName] as WebAssembly.Memory;",
    "    const pages = memory.buffer.byteLength / 65536;",
    "    if (pages < contract.minimumPages) {",
    "      throw new Error(`MHA_ADAPTER_MISMATCH: memory exports[${contract.exportName}] has ${pages} pages; expected at least ${contract.minimumPages}`);",
    "    }",
    "    if (contract.shared !== undefined) {",
    "      const isShared = typeof SharedArrayBuffer !== \"undefined\" && memory.buffer instanceof SharedArrayBuffer;",
    "      if (isShared !== contract.shared) {",
    "        throw new Error(`MHA_ADAPTER_MISMATCH: memory exports[${contract.exportName}] shared flag does not match contract`);",
    "      }",
    "    }",
    "  }",
    "}",
    "",
    "export async function instantiateWithResources<HostToken = unknown>(",
    "  bytes: BufferSource,",
    "  imports: HostImports<HostToken>,",
    "): Promise<ModuleExports<HostToken>> {",
    "  const exports = await instantiate(bytes, imports);",
    "  assertMemoryResources(exports as unknown as WebAssembly.Exports);",
    "  return exports;",
    "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// Generate the existing function adapter plus memory resource checks.
/// The legacy generator remains byte-for-byte unchanged.
pub fn generate_typescript_adapter_with_memory(
  abi : @model.HostAbi,
  contract : @contract.Contract,
  resource_contract : @resource.MemoryContract,
) -> GenerationResult raise @contract.ContractError {
  let base = generate_typescript_adapter(abi, contract)
  let resource_diagnostics = memory_resource_diagnostics(resource_contract)
  let diagnostics = base.diagnostics.copy()
  diagnostics.append(resource_diagnostics)
  if !diagnostics.is_empty() {
    return {
      typescript: "",
      contract: base.contract,
      manifest: "",
      abi_sha256: base.abi_sha256,
      diagnostics,
    }
  }
  let typescript = base.typescript +
    render_memory_resource_runtime(resource_contract)
  let manifest = encode_generation_manifest(
    create_generation_manifest(base.abi_sha256, base.contract, typescript),
  )
  {
    typescript,
    contract: base.contract,
    manifest,
    abi_sha256: base.abi_sha256,
    diagnostics,
  }
}
