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

///|
/// JSON contract sources for the four Wasm resource kinds. The generator keeps
/// these opaque so runtime packages can evolve their own guard implementations.
pub(all) struct ResourceContractSources {
  memory : String?
  table : String?
  global : String?
  tag : String?
} derive(Eq, Debug)

///|
fn resource_source(value : String?) -> String {
  match value {
    Some(text) => if text.trim().is_empty() { "null" } else { text }
    None => "null"
  }
}

///|
fn render_resource_runtime(sources : ResourceContractSources) -> String {
  let lines = [
    "",
    "export interface ResourceGuards {",
    "  memory?: (exports: WebAssembly.Exports, contract: unknown) => void;",
    "  table?: (exports: WebAssembly.Exports, contract: unknown) => void;",
    "  global?: (exports: WebAssembly.Exports, contract: unknown) => void;",
    "  tag?: (exports: WebAssembly.Exports, contract: unknown) => void;",
    "}",
    "const memoryResourceContract: unknown = \{resource_source(sources.memory)};",
    "const tableResourceContract: unknown = \{resource_source(sources.table)};",
    "const globalResourceContract: unknown = \{resource_source(sources.global)};",
    "const tagResourceContract: unknown = \{resource_source(sources.tag)};",
    "",
    "export async function instantiateWithResources<HostToken = unknown>(",
    "  bytes: BufferSource,",
    "  imports: HostImports<HostToken>,",
    "  guards: ResourceGuards,",
    "): Promise<ModuleExports<HostToken>> {",
    "  const exports = await instantiate(bytes, imports);",
    "  if (memoryResourceContract !== null && guards.memory) guards.memory(exports as unknown as WebAssembly.Exports, memoryResourceContract);",
    "  if (tableResourceContract !== null && guards.table) guards.table(exports as unknown as WebAssembly.Exports, tableResourceContract);",
    "  if (globalResourceContract !== null && guards.global) guards.global(exports as unknown as WebAssembly.Exports, globalResourceContract);",
    "  if (tagResourceContract !== null && guards.tag) guards.tag(exports as unknown as WebAssembly.Exports, tagResourceContract);",
    "  return exports;",
    "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// Generate an adapter with caller-supplied guards for all resource kinds.
/// Contract JSON remains opaque; this preserves compatibility with independent
/// runtime guard packages while keeping the legacy function-only API unchanged.
pub fn generate_typescript_adapter_with_resources(
  abi : @model.HostAbi,
  contract : @contract.Contract,
  sources : ResourceContractSources,
) -> GenerationResult raise @contract.ContractError {
  let base = generate_typescript_adapter(abi, contract)
  if !base.diagnostics.is_empty() {
    return base
  }
  let typescript = base.typescript + render_resource_runtime(sources)
  let manifest = encode_generation_manifest(
    create_generation_manifest(base.abi_sha256, base.contract, typescript),
  )
  {
    typescript,
    contract: base.contract,
    manifest,
    abi_sha256: base.abi_sha256,
    diagnostics: [],
  }
}
