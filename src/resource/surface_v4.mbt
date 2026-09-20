///|
/// Exception identity uses its resolved function signature, never a type index.
pub(all) struct TagSignatureResource {
  path : String
  module_name : String?
  name : String
  params : Array[String]
  results : Array[String]
} derive(Eq, Debug)

///|
/// Resource protocol v4, independent of the legacy index-based v3 protocol.
pub(all) struct ResourceSurfaceV4 {
  schema_version : Int
  memories : Array[MemoryResource]
  tables : Array[TableResource]
  globals : Array[GlobalResource]
  tags : Array[TagSignatureResource]
  unsupported : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct ResourceLockfileV4 {
  lockfile_version : Int
  schema_sha256 : String
  artifact_sha256 : String
  abi_sha256 : String
  abi : ResourceSurfaceV4
} derive(Eq, Debug)

///|
pub(all) struct ResourceContractV5 {
  schema_version : Int
  abi_sha256 : String
  memories : Array[MemoryResource]
  tables : Array[TableResource]
  globals : Array[GlobalResource]
  tags : Array[TagSignatureResource]
  unsupported : Array[String]
} derive(Eq, Debug)

///|
fn resource_path(module_name : String?, name : String) -> String {
  match module_name {
    Some(module_name) =>
      "imports[\{json_string(module_name)}][\{json_string(name)}]"
    None => "exports[\{json_string(name)}]"
  }
}

///|
fn encode_type_sequence(values : Array[String]) -> String {
  "[\{values.map(json_string).join(",")}]"
}

///|
fn encode_tag_signature(value : TagSignatureResource) -> String {
  let module_json = match value.module_name {
    Some(name) => json_string(name)
    None => "null"
  }
  "{\"path\":\{json_string(value.path)},\"module\":\{module_json},\"name\":\{json_string(value.name)},\"params\":\{encode_type_sequence(value.params)},\"results\":\{encode_type_sequence(value.results)}}"
}

///|
fn encode_tag_signatures(values : Array[TagSignatureResource]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.path.compare(right.path) })
  "[\{sorted.map(encode_tag_signature).join(",")}]"
}

///|
pub fn encode_resource_surface_v4(surface : ResourceSurfaceV4) -> String {
  "{\"schemaVersion\":\{surface.schema_version},\"memories\":\{encode_memories(surface.memories)},\"tables\":\{encode_tables(surface.tables)},\"globals\":\{encode_globals(surface.globals)},\"tags\":\{encode_tag_signatures(surface.tags)},\"unsupported\":\{encode_strings(surface.unsupported)}}"
}

///|
pub fn resource_surface_v4_sha256(surface : ResourceSurfaceV4) -> String {
  sha256_text(encode_resource_surface_v4(surface))
}

///|
pub fn create_resource_lockfile_v4(
  surface : ResourceSurfaceV4,
  artifact : Bytes,
) -> ResourceLockfileV4 {
  {
    lockfile_version: 4,
    schema_sha256: sha256_text("moonhostabi.resource.lock/v4"),
    artifact_sha256: @crypto.bytes_to_hex_string(@crypto.sha256(artifact)),
    abi_sha256: resource_surface_v4_sha256(surface),
    abi: surface,
  }
}

///|
pub fn encode_resource_lockfile_v4(lockfile : ResourceLockfileV4) -> String {
  "{\"lockfileVersion\":\{lockfile.lockfile_version},\"schemaSha256\":\{json_string(lockfile.schema_sha256)},\"artifactSha256\":\{json_string(lockfile.artifact_sha256)},\"abiSha256\":\{json_string(lockfile.abi_sha256)},\"abi\":\{encode_resource_surface_v4(lockfile.abi)}}"
}

///|
pub fn create_resource_contract_v5(
  surface : ResourceSurfaceV4,
) -> ResourceContractV5 {
  {
    schema_version: 5,
    abi_sha256: resource_surface_v4_sha256(surface),
    memories: surface.memories,
    tables: surface.tables,
    globals: surface.globals,
    tags: surface.tags,
    unsupported: surface.unsupported,
  }
}

///|
pub fn encode_resource_contract_v5(contract : ResourceContractV5) -> String {
  "{\"schemaVersion\":\{contract.schema_version},\"abiSha256\":\{json_string(contract.abi_sha256)},\"memories\":\{encode_memories(contract.memories)},\"tables\":\{encode_tables(contract.tables)},\"globals\":\{encode_globals(contract.globals)},\"tags\":\{encode_tag_signatures(contract.tags)},\"unsupported\":\{encode_strings(contract.unsupported)}}"
}

///|
fn contract_v5_surface(contract : ResourceContractV5) -> ResourceSurfaceV4 {
  {
    schema_version: 4,
    memories: contract.memories,
    tables: contract.tables,
    globals: contract.globals,
    tags: contract.tags,
    unsupported: contract.unsupported,
  }
}

///|
pub fn validate_resource_contract_v5(
  surface : ResourceSurfaceV4,
  contract : ResourceContractV5,
) -> Bool {
  try {
    validate_surface_v4(surface)
    validate_surface_v4(contract_v5_surface(contract))
  } catch {
    _ => return false
  }
  surface.unsupported.is_empty() &&
  contract.unsupported.is_empty() &&
  contract.schema_version == 5 &&
  contract.abi_sha256 == resource_surface_v4_sha256(surface) &&
  encode_resource_surface_v4(surface) ==
  encode_resource_surface_v4(contract_v5_surface(contract))
}

///|
fn resource_value_type(value : @wasm_types.ValueType) -> String? {
  match value {
    I32 => Some("i32")
    I64 => Some("i64")
    F32 => Some("f32")
    F64 => Some("f64")
    V128 => Some("v128")
    FuncRef => Some("funcref")
    ExternRef => Some("externref")
    RefFunc => Some("(ref func)")
    RefExtern => Some("(ref extern)")
    AnyRef => Some("anyref")
    StructRef => Some("structref")
    ArrayRef => Some("arrayref")
    RefAny => Some("(ref any)")
    RefEq => Some("(ref eq)")
    RefNullEq => Some("eqref")
    RefI31 => Some("(ref i31)")
    RefNullI31 => Some("i31ref")
    RefStructAbs => Some("(ref struct)")
    RefArrayAbs => Some("(ref array)")
    RefNone => Some("(ref none)")
    NullRef => Some("nullref")
    // wasm_core 0.14 maps both nullable and non-nullable encodings to these
    // variants. Their original type cannot be recovered from Module alone.
    ExnRef | NullFuncRef | NullExnRef | NullExternRef => None
    RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_) => None
  }
}

///|
fn resource_reference_limitation(
  value : @wasm_types.ValueType,
  kind : String,
) -> String {
  match value {
    ExnRef | NullFuncRef | NullExnRef | NullExternRef =>
      "\{kind} reference nullability unavailable in wasm_core 0.14 parser"
    _ => "typed \{kind} reference requires structural type normalization"
  }
}

///|
fn add_table(
  surface : ResourceSurfaceV4,
  value : @wasm_types.TableType,
  module_name : String?,
  name : String,
) -> Unit {
  let path = resource_path(module_name, name)
  match resource_value_type(value.elem_type) {
    Some(element_type) =>
      surface.tables.push({
        path,
        module_name,
        name,
        element_type,
        minimum_elements: value.limits.min,
        maximum_elements: value.limits.max,
        table64: value.is_table64,
      })
    None =>
      surface.unsupported.push(
        "\{path}: \{resource_reference_limitation(value.elem_type, "table")}",
      )
  }
}

///|
fn add_global(
  surface : ResourceSurfaceV4,
  value : @wasm_types.GlobalType,
  module_name : String?,
  name : String,
) -> Unit {
  let path = resource_path(module_name, name)
  match resource_value_type(value.value_type) {
    Some(value_type) =>
      surface.globals.push({
        path,
        module_name,
        name,
        value_type,
        mutable: value.mutable,
      })
    None =>
      surface.unsupported.push(
        "\{path}: \{resource_reference_limitation(value.value_type, "global")}",
      )
  }
}

///|
fn add_tag(
  surface : ResourceSurfaceV4,
  wasm : @wasm_types.Module,
  type_index : Int,
  module_name : String?,
  name : String,
) -> Unit raise ResourceError {
  let path = resource_path(module_name, name)
  guard wasm.func_type_at(type_index) is Some(signature) else {
    return invalid_resource(
      "\{path}: invalid tag function type index \{type_index}",
    )
  }
  if !signature.results.is_empty() {
    invalid_resource("\{path}: tag signature must not have results")
  }
  let params : Array[String] = []
  for value in signature.params {
    match resource_value_type(value) {
      Some(value) => params.push(value)
      None => {
        surface.unsupported.push(
          "\{path}: \{resource_reference_limitation(value, "tag")}",
        )
        return
      }
    }
  }
  surface.tags.push({ path, module_name, name, params, results: [], })
}

///|
fn[T] indexed_resource(
  values : Array[T],
  index : Int,
  path : String,
) -> T raise ResourceError {
  if index < 0 || index >= values.length() {
    invalid_resource("\{path}: invalid resource index \{index}")
  }
  values[index]
}

///|
/// Project all host-visible resources using the independent resource index spaces.
/// Module v0.14 does not retain memory shared flags; use artifact projection for memories.
pub fn project_resource_surface(
  wasm_module : @wasm_types.Module,
) -> ResourceSurfaceV4 raise ResourceError {
  let surface : ResourceSurfaceV4 = {
    schema_version: 4,
    memories: [],
    tables: [],
    globals: [],
    tags: [],
    unsupported: [],
  }
  let tables : Array[@wasm_types.TableType] = []
  let memories : Array[@wasm_types.MemoryType] = []
  let globals : Array[@wasm_types.GlobalType] = []
  let tags : Array[Int] = []
  let imports : Map[String, Bool] = Map([])
  for imported in wasm_module.imports {
    let module_name = Some(imported.mod_name)
    let path = resource_path(module_name, imported.name)
    // Repeated resource identities cannot be represented by this protocol.
    if !(imported.desc is Func(_)) {
      if imports.get(path) is Some(_) {
        invalid_resource("\{path}: duplicate import identity")
      }
      imports[path] = true
    }
    match imported.desc {
      Table(value) => {
        tables.push(value)
        add_table(surface, value, module_name, imported.name)
      }
      Memory(value) => {
        memories.push(value)
        surface.unsupported.push("\{path}: shared memory metadata unavailable")
      }
      Global(value) => {
        globals.push(value)
        add_global(surface, value, module_name, imported.name)
      }
      Tag(index) => {
        tags.push(index)
        add_tag(surface, wasm_module, index, module_name, imported.name)
      }
      Func(_) => ()
    }
  }
  for value in wasm_module.tables {
    tables.push(value.type_)
  }
  for value in wasm_module.memories {
    memories.push(value)
  }
  for value in wasm_module.globals {
    globals.push(value.type_)
  }
  for value in wasm_module.tags {
    tags.push(value.type_idx)
  }
  let exports : Map[String, Bool] = Map([])
  for exported in wasm_module.exports {
    let path = resource_path(None, exported.name)
    if exports.get(path) is Some(_) {
      invalid_resource("\{path}: duplicate export identity")
    }
    exports[path] = true
    match exported.desc {
      Table(index) =>
        add_table(
          surface,
          indexed_resource(tables, index, path),
          None,
          exported.name,
        )
      Global(index) =>
        add_global(
          surface,
          indexed_resource(globals, index, path),
          None,
          exported.name,
        )
      Tag(index) =>
        add_tag(
          surface,
          wasm_module,
          indexed_resource(tags, index, path),
          None,
          exported.name,
        )
      Memory(index) => {
        ignore(indexed_resource(memories, index, path))
        surface.unsupported.push("\{path}: shared memory metadata unavailable")
      }
      Func(_) => ()
    }
  }
  validate_surface_v4(surface)
  surface
}
