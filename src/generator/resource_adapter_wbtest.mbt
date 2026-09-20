///|
test "opaque resource guards fail closed before instantiation and use semantic aliases" {
  let abi = generator_fixture_abi()
  let generated = generate_typescript_adapter_with_resources(
    abi,
    @contract.create_contract_draft(abi),
    { memory: Some("{}"), table: None, global: None, tag: None, },
  )
  inspect(
    generated.typescript.contains(
      "if (memoryResourceContract !== null && typeof guards?.memory !== \"function\")",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains(
      "MHA_ADAPTER_MISMATCH: missing memory resource guard",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains("instantiateWithResources<HostToken"),
    content="false",
  )
  inspect(
    generated.typescript.contains(
      "imports: HostImports<TExtern0, TExtern1, TExtern2>",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains("): Promise<ModuleExports>"),
    content="true",
  )
}

///|
fn resource_adapter_surface() -> @resource.ResourceSurfaceV4 {
  {
    schema_version: 4,
    memories: [
      {
        path: "imports[\"env\"][\"memory\"]",
        module_name: Some("env"),
        name: "memory",
        minimum_pages: 1L,
        maximum_pages: Some(3L),
        shared: false,
        memory64: false,
        page_size_log2: 16,
      },
    ],
    tables: [
      {
        path: "exports[\"table\"]",
        module_name: None,
        name: "table",
        element_type: "externref",
        minimum_elements: 1L,
        maximum_elements: Some(5L),
        table64: false,
      },
    ],
    globals: [
      {
        path: "exports[\"global\"]",
        module_name: None,
        name: "global",
        value_type: "i64",
        mutable: true,
      },
    ],
    tags: [
      {
        path: "imports[\"env\"][\"tag\"]",
        module_name: Some("env"),
        name: "tag",
        params: ["i32", "externref"],
        results: [],
      },
    ],
    unsupported: [],
  }
}

///|
test "resource adapter uses verified contracts typed resources and default probes" {
  let abi = generator_fixture_abi()
  let surface = resource_adapter_surface()
  let generated = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    surface,
    @resource.create_resource_contract_v5(surface),
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(generated.diagnostics.length(), content="0")
  inspect(
    generated.typescript.contains(
      "export type HostImportsWithResources<TExtern0 = unknown, TExtern1 = unknown, TExtern2 = unknown> = HostImports<TExtern0, TExtern1, TExtern2> & {",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains(
      "export type ModuleExportsWithResources = ModuleExports & {",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains("\"memory\": WebAssembly.Memory;"),
    content="true",
  )
  inspect(
    generated.typescript.contains(
      "\"global\": WebAssembly.Global & { value: bigint };",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains("\"tag\": WebAssembly.Tag;"),
    content="true",
  )
  inspect(
    generated.typescript.contains("new WebAssembly.Instance"),
    content="true",
  )
  inspect(
    generated.typescript.contains("crypto.subtle.digest(\"SHA-256\", snapshot)"),
    content="true",
  )
  inspect(generated.typescript.contains("guards:"), content="false")
}

///|
test "resource adapter rejects mismatched contracts and unsupported resources" {
  let abi = generator_fixture_abi()
  let surface = resource_adapter_surface()
  let contract = @resource.create_resource_contract_v5(surface)
  let generated = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    surface,
    {
      ..contract,
      abi_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(generated.typescript, content="")
  inspect(generated.diagnostics[0].code, content="MHA_ADAPTER_MISMATCH")
  let unsupported_surface = { ..surface, unsupported: ["memory64"], }
  let unsupported = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    unsupported_surface,
    @resource.create_resource_contract_v5(unsupported_surface),
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(unsupported.typescript, content="")
  inspect(
    unsupported.diagnostics[0].code,
    content="MHA_PROJECT_UNREPRESENTABLE",
  )
}

///|
test "resource adapter rejects unrepresentable resource kinds and invalid artifact fingerprints" {
  let abi = generator_fixture_abi()
  let surface = resource_adapter_surface()
  let cases = [
    { ..surface, memories: [{ ..surface.memories[0], memory64: true, }], },
    { ..surface, memories: [{ ..surface.memories[0], shared: true, }], },
    { ..surface, memories: [{ ..surface.memories[0], page_size_log2: 12, }], },
    { ..surface, tables: [{ ..surface.tables[0], table64: true, }], },
    { ..surface, tables: [{ ..surface.tables[0], element_type: "typedref", }], },
    { ..surface, globals: [{ ..surface.globals[0], value_type: "v128", }], },
    { ..surface, tags: [{ ..surface.tags[0], params: ["v128"], }], },
  ]
  for invalid_surface in cases {
    let generated = generate_typescript_adapter_with_resource_contract(
      abi,
      @contract.create_contract_draft(abi),
      invalid_surface,
      @resource.create_resource_contract_v5(invalid_surface),
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    )
    inspect(generated.typescript, content="")
    inspect(
      generated.diagnostics[0].code,
      content="MHA_PROJECT_UNREPRESENTABLE",
    )
  }
  let invalid_hash = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    surface,
    @resource.create_resource_contract_v5(surface),
    "not-a-hash",
  )
  inspect(invalid_hash.typescript, content="")
  inspect(invalid_hash.diagnostics[0].path, content="artifactSha256")
}

///|
test "resource adapter rejects function resource property collisions" {
  let abi = generator_fixture_abi()
  let surface = resource_adapter_surface()
  let conflict = {
    ..surface,
    globals: [{ ..surface.globals[0], path: "exports[\"add\"]", name: "add", }],
  }
  let generated = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    conflict,
    @resource.create_resource_contract_v5(conflict),
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(generated.typescript, content="")
  inspect(generated.diagnostics[0].code, content="MHA_ADAPTER_MISMATCH")
  inspect(
    generated.diagnostics[0].message,
    content="resource and function share a JavaScript property",
  )
}

///|
test "resource adapters reject semantic aliases shadowing resource type names" {
  let abi = @model.HostAbi::{
    schema_version: 1,
    imports: [
      {
        module_name: Some("host"),
        name: "value",
        params: [@model.ExternRef],
        results: [],
      },
    ],
    exports: [],
    types: [],
    features: [],
  }
  let hash = @lockfile.host_abi_sha256(abi)
  let contract = @contract.decode_contract(
    abi,
    "{\"schemaVersion\":2,\"abiSha256\":\"\{hash}\",\"externrefs\":{\"imports[host.value].params[0]\":\"HostImportsWithResources\"},\"imports\":[]}\n",
  )
  let surface = resource_adapter_surface()
  let generated = generate_typescript_adapter_with_resource_contract(
    abi,
    contract,
    surface,
    @resource.create_resource_contract_v5(surface),
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(generated.typescript, content="")
  inspect(generated.diagnostics[0].code, content="MHA_PROJECT_UNREPRESENTABLE")
}

///|
test "artifact bound adapter has one guarded entry and snapshots host imports" {
  let abi = generator_fixture_abi()
  let surface = resource_adapter_surface()
  let generated = generate_typescript_adapter_with_resource_contract(
    abi,
    @contract.create_contract_draft(abi),
    surface,
    @resource.create_resource_contract_v5(surface),
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  )
  inspect(
    generated.typescript.contains("export async function instantiate<"),
    content="false",
  )
  inspect(
    generated.typescript.contains(
      "export const instantiate = instantiateWithResources;",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains(
      "const importSnapshot = snapshotResourceImports(imports);",
    ),
    content="true",
  )
  inspect(
    generated.typescript.contains(
      "WebAssembly.instantiate(snapshot, importSnapshot as unknown as WebAssembly.Imports)",
    ),
    content="true",
  )
}
