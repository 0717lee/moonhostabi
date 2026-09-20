///|
priv struct ResourceBinding {
  path : String
  module_name : String?
  name : String
  kind : String
  typescript : String
  probe : Array[Int]
}

///|
fn resource_mismatch(path : String, message : String) -> @model.Diagnostic {
  {
    code: @model.MHA_ADAPTER_MISMATCH,
    severity: @model.Error,
    path,
    message,
    byte_offset: None,
  }
}

///|
fn resource_scalar_type(value : String) -> Bool {
  ["i32", "i64", "f32", "f64", "externref"].contains(value)
}

///|
fn resource_type_byte(value : String) -> Int {
  match value {
    "i32" => 0x7f
    "i64" => 0x7e
    "f32" => 0x7d
    "f64" => 0x7c
    "funcref" => 0x70
    "externref" => 0x6f
    _ => abort("resource type must be validated before encoding")
  }
}

///|
fn resource_uleb(bytes : Array[Int], value : Int64) -> Unit {
  let mut remaining = value
  while remaining >= 128L {
    bytes.push((remaining & 127L).to_int() | 128)
    remaining = remaining >> 7
  }
  bytes.push(remaining.to_int())
}

///|
fn resource_probe_section(
  bytes : Array[Int],
  id : Int,
  payload : Array[Int],
) -> Unit {
  bytes.push(id)
  resource_uleb(bytes, payload.length().to_int64())
  bytes.append(payload)
}

///|
fn resource_probe(
  kind : Int,
  descriptor : Array[Int],
  type_section? : Array[Int] = [],
) -> Array[Int] {
  let bytes = [0, 97, 115, 109, 1, 0, 0, 0]
  if !type_section.is_empty() {
    resource_probe_section(bytes, 1, type_section)
  }
  // One import named "value" in the empty module namespace, and no start/code.
  let imports = [1, 0, 5, 118, 97, 108, 117, 101, kind]
  imports.append(descriptor)
  resource_probe_section(bytes, 2, imports)
  bytes
}

///|
fn resource_limits(minimum : Int64, maximum : Int64?) -> Array[Int] {
  let bytes = [if maximum is Some(_) { 1 } else { 0 }]
  resource_uleb(bytes, minimum)
  if maximum is Some(value) {
    resource_uleb(bytes, value)
  }
  bytes
}

///|
fn resource_bindings(
  surface : @resource.ResourceSurfaceV4,
) -> Array[ResourceBinding] {
  let bindings : Array[ResourceBinding] = []
  for memory in surface.memories {
    bindings.push({
      path: memory.path,
      module_name: memory.module_name,
      name: memory.name,
      kind: "memory",
      typescript: "WebAssembly.Memory",
      probe: resource_probe(
        2,
        resource_limits(memory.minimum_pages, memory.maximum_pages),
      ),
    })
  }
  for table in surface.tables {
    let descriptor = [resource_type_byte(table.element_type)]
    descriptor.append(
      resource_limits(table.minimum_elements, table.maximum_elements),
    )
    bindings.push({
      path: table.path,
      module_name: table.module_name,
      name: table.name,
      kind: "table",
      typescript: "WebAssembly.Table",
      probe: resource_probe(1, descriptor),
    })
  }
  for global in surface.globals {
    let value = match global.value_type {
      "i64" => "bigint"
      "externref" => "unknown"
      _ => "number"
    }
    bindings.push({
      path: global.path,
      module_name: global.module_name,
      name: global.name,
      kind: "global",
      typescript: "WebAssembly.Global & { value: \{value} }",
      probe: resource_probe(3, [
        resource_type_byte(global.value_type),
        if global.mutable {
          1
        } else {
          0
        },
      ]),
    })
  }
  for tag in surface.tags {
    let section = [1, 0x60]
    resource_uleb(section, tag.params.length().to_int64())
    for parameter in tag.params {
      section.push(resource_type_byte(parameter))
    }
    section.push(0)
    bindings.push({
      path: tag.path,
      module_name: tag.module_name,
      name: tag.name,
      kind: "tag",
      typescript: "WebAssembly.Tag",
      probe: resource_probe(4, [0, 0], type_section=section),
    })
  }
  bindings.sort_by(fn(left, right) { left.path.compare(right.path) })
  bindings
}

///|
fn validate_resource_surface_for_adapter(
  surface : @resource.ResourceSurfaceV4,
) -> Array[@model.Diagnostic] {
  let diagnostics : Array[@model.Diagnostic] = []
  for unsupported in surface.unsupported {
    diagnostics.push(
      generator_diagnostic(
        "resourceContract.unsupported",
        "resource feature is not representable: \{unsupported}",
      ),
    )
  }
  for memory in surface.memories {
    if memory.memory64 || memory.shared || memory.page_size_log2 != 16 {
      diagnostics.push(
        generator_diagnostic(
          memory.path,
          "resource adapter supports only non-shared memory32 with 65536-byte pages",
        ),
      )
    }
    if memory.minimum_pages < 0L ||
      memory.minimum_pages > 65536L ||
      (
        memory.maximum_pages is Some(maximum) &&
        (maximum < memory.minimum_pages || maximum > 65536L)
      ) {
      diagnostics.push(
        generator_diagnostic(
          memory.path,
          "memory limits must be ordered and within memory32 bounds",
        ),
      )
    }
  }
  for table in surface.tables {
    if table.table64 || !["funcref", "externref"].contains(table.element_type) {
      diagnostics.push(
        generator_diagnostic(
          table.path,
          "resource adapter supports only table32 with funcref or externref elements",
        ),
      )
    }
    if table.minimum_elements < 0L ||
      table.minimum_elements > 4294967295L ||
      (
        table.maximum_elements is Some(maximum) &&
        (maximum < table.minimum_elements || maximum > 4294967295L)
      ) {
      diagnostics.push(
        generator_diagnostic(
          table.path,
          "table limits must be ordered and within table32 bounds",
        ),
      )
    }
  }
  for global in surface.globals {
    if !resource_scalar_type(global.value_type) {
      diagnostics.push(
        generator_diagnostic(
          global.path,
          "global value type cannot be represented by the resource adapter: \{global.value_type}",
        ),
      )
    }
  }
  for tag in surface.tags {
    if !tag.results.is_empty() ||
      tag.params.any(fn(value) { !resource_scalar_type(value) }) {
      diagnostics.push(
        generator_diagnostic(
          tag.path,
          "tag signatures require scalar or externref parameters and no results",
        ),
      )
    }
  }
  diagnostics
}

///|
fn append_resource_types(
  lines : Array[String],
  abi : @model.HostAbi,
  contract : @contract.Contract,
  bindings : Array[ResourceBinding],
) -> Unit raise @contract.ContractError {
  let imports = semantic_aliases_for_functions(
    @model.sort_abi_functions(abi.imports),
    contract,
  )
  let exports = semantic_aliases_for_functions(
    @model.sort_abi_functions(abi.exports),
    contract,
  )
  lines.push(
    "export type HostImportsWithResources\{type_parameter_declaration(imports, true)} = HostImports\{type_arguments(imports)} & {",
  )
  let modules : Array[String] = []
  for binding in bindings {
    if binding.module_name is Some(module_name) &&
      !modules.contains(module_name) {
      modules.push(module_name)
    }
  }
  modules.sort()
  for module_name in modules {
    lines.push("  \{contract_json_string(module_name)}: {")
    for binding in bindings {
      if binding.module_name == Some(module_name) {
        lines.push(
          "    \{contract_json_string(binding.name)}: \{binding.typescript};",
        )
      }
    }
    lines.push("  };")
  }
  lines.push("};")
  lines.push("")
  lines.push(
    "export type ModuleExportsWithResources\{type_parameter_declaration(exports, true)} = ModuleExports\{type_arguments(exports)} & {",
  )
  for binding in bindings {
    if binding.module_name is None {
      lines.push(
        "  \{contract_json_string(binding.name)}: \{binding.typescript};",
      )
    }
  }
  lines.push("};")
}

///|
fn resource_binding_json(binding : ResourceBinding) -> String {
  let module_name = match binding.module_name {
    Some(value) => contract_json_string(value)
    None => "null"
  }
  let probe = binding.probe.map(fn(value) { "\{value}" }).join(", ")
  "{ path: \{contract_json_string(binding.path)}, module: \{module_name}, name: \{contract_json_string(binding.name)}, kind: \{contract_json_string(binding.kind)}, probe: [\{probe}] }"
}

///|
fn render_resource_contract_adapter(
  abi : @model.HostAbi,
  contract : @contract.Contract,
  bindings : Array[ResourceBinding],
  artifact_sha256 : String,
) -> String raise @contract.ContractError {
  let lines : Array[String] = [""]
  append_resource_types(lines, abi, contract, bindings)
  lines.push("")
  lines.push(
    "// Resource signatures and declared limits are bound to these exact artifact bytes.",
  )
  lines.push(
    "const resourceArtifactSha256 = \{contract_json_string(artifact_sha256)};",
  )
  lines.push("const resourceContracts: readonly ResourceBinding[] = [")
  for binding in bindings {
    lines.push("  \{resource_binding_json(binding)},")
  }
  lines.push("];")
  lines.push(
    "const resourceImportKeys: readonly { module: string; name: string }[] = [",
  )
  for function in @model.sort_abi_functions(abi.imports) {
    lines.push(
      "  { module: \{contract_json_string(function.module_name.unwrap_or(""))}, name: \{contract_json_string(function.name)} },",
    )
  }
  for binding in bindings {
    if binding.module_name is Some(module_name) {
      lines.push(
        "  { module: \{contract_json_string(module_name)}, name: \{contract_json_string(binding.name)} },",
      )
    }
  }
  lines.push("];")
  lines.push(resource_contract_runtime())
  let all_names = contract.semantic_aliases()
  let import_names = semantic_aliases_for_functions(
    @model.sort_abi_functions(abi.imports),
    contract,
  )
  let export_names = semantic_aliases_for_functions(
    @model.sort_abi_functions(abi.exports),
    contract,
  )
  lines.push(
    "export async function instantiateWithResources\{type_parameter_declaration(all_names, true)}(",
  )
  lines.push("  bytes: BufferSource,")
  lines.push(
    "  imports: HostImportsWithResources\{type_arguments(import_names)},",
  )
  lines.push(
    "): Promise<ModuleExportsWithResources\{type_arguments(export_names)}> {",
  )
  lines.push("  const snapshot = await verifyResourceArtifact(bytes);")
  lines.push("  const importSnapshot = snapshotResourceImports(imports);")
  if !abi.imports.is_empty() {
    lines.push("  assertHostImports(importSnapshot);")
  }
  lines.push("  assertResourceBindings(importSnapshot, true);")
  lines.push(
    "  // DOM ImportValue typings omit Tag; all copied resources were checked above.",
  )
  lines.push(
    "  const result = await WebAssembly.instantiate(snapshot, importSnapshot as unknown as WebAssembly.Imports);",
  )
  if !abi.exports.is_empty() {
    lines.push("  assertModuleExports(result.instance.exports);")
  }
  lines.push("  assertResourceBindings(result.instance.exports, false);")
  lines.push(
    "  return result.instance.exports as unknown as ModuleExportsWithResources\{type_arguments(export_names)};",
  )
  lines.push("}")
  lines.push("")
  lines.push("export const instantiate = instantiateWithResources;")
  lines.join("\n") + "\n"
}

///|
/// Generate an artifact-bound adapter with default resource import/export checks.
/// The function-only adapter remains unchanged. Static resource facts are checked
/// against the validated surface; runtime probes check actual host object types.
pub fn generate_typescript_adapter_with_resource_contract(
  abi : @model.HostAbi,
  contract : @contract.Contract,
  surface : @resource.ResourceSurfaceV4,
  resource_contract : @resource.ResourceContractV5,
  artifact_sha256 : String,
) -> GenerationResult raise @contract.ContractError {
  let base = generate_typescript_adapter(abi, contract)
  let diagnostics = base.diagnostics.copy()
  for semantic_name in contract.semantic_aliases() {
    if ["HostImportsWithResources", "ModuleExportsWithResources"].contains(
        semantic_name,
      ) {
      diagnostics.push(
        generator_diagnostic(
          "contract.externrefs",
          "semantic alias conflicts with generated resource type: \{semantic_name}",
        ),
      )
    }
  }
  diagnostics.append(validate_resource_surface_for_adapter(surface))
  if !@resource.validate_resource_contract_v5(surface, resource_contract) {
    diagnostics.push(
      resource_mismatch(
        "resourceContract", "resource contract does not match the artifact resource surface",
      ),
    )
  }
  if artifact_sha256.length() != 64 ||
    !artifact_sha256
    .to_array()
    .all(fn(character) {
      (character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')
    }) {
    diagnostics.push(
      resource_mismatch(
        "artifactSha256", "resource adapters require a lowercase SHA-256 artifact fingerprint",
      ),
    )
  }
  if !diagnostics.is_empty() {
    return { ..base, typescript: "", manifest: "", diagnostics, }
  }
  let bindings = resource_bindings(surface)
  for index, binding in bindings {
    let expected_path = match binding.module_name {
      Some(module_name) =>
        "imports[\{contract_json_string(module_name)}][\{contract_json_string(binding.name)}]"
      None => "exports[\{contract_json_string(binding.name)}]"
    }
    if binding.path != expected_path {
      diagnostics.push(
        resource_mismatch(
          binding.path,
          "resource path does not match its module and name",
        ),
      )
    }
    for previous in 0..<index {
      if bindings[previous].module_name == binding.module_name &&
        bindings[previous].name == binding.name {
        diagnostics.push(
          resource_mismatch(
            binding.path,
            "duplicate resource property cannot be represented by one JavaScript property",
          ),
        )
      }
    }
    for
      function in (if binding.module_name is Some(_) {
        abi.imports
      } else {
        abi.exports
      }) {
      if function.module_name == binding.module_name &&
        function.name == binding.name {
        diagnostics.push(
          resource_mismatch(
            binding.path,
            "resource and function share a JavaScript property",
          ),
        )
      }
    }
  }
  if !diagnostics.is_empty() {
    return { ..base, typescript: "", manifest: "", diagnostics, }
  }
  let typescript = render_typescript(
      abi,
      base.abi_sha256,
      contract,
      include_instantiate=false,
    ) +
    render_resource_contract_adapter(abi, contract, bindings, artifact_sha256)
  let manifest = encode_generation_manifest(
    create_generation_manifest(base.abi_sha256, base.contract, typescript),
  )
  { ..base, typescript, manifest, diagnostics, }
}
