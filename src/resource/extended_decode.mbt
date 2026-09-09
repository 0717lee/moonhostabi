///|
fn decode_module_name(
  value : Map[String, Json],
  key : String,
  path : String,
) -> String? raise ResourceError {
  match required(value, key, path) {
    Null => None
    String(text) => Some(text)
    _ => invalid_resource("\{path}.\{key}: expected string or null")
  }
}

///|
fn decode_table_resource(
  value : Json,
  path : String,
) -> TableResource raise ResourceError {
  let object = object(value, path)
  keys(
    object,
    [
      "path", "module", "name", "elementType", "minimumElements", "maximumElements",
      "table64",
    ],
    path,
  )
  let minimum_elements = int64_value(object, "minimumElements", path)
  let maximum_elements = optional_int64(object, "maximumElements", path)
  if minimum_elements < 0L {
    invalid_resource("\{path}.minimumElements: expected non-negative integer")
  }
  match maximum_elements {
    Some(value) if value < minimum_elements =>
      invalid_resource(
        "\{path}.maximumElements: must be at least minimumElements",
      )
    _ => ()
  }
  TableResource::{
    path: string_value(object, "path", path),
    module_name: decode_module_name(object, "module", path),
    name: string_value(object, "name", path),
    element_type: string_value(object, "elementType", path),
    minimum_elements,
    maximum_elements,
    table64: bool_value(object, "table64", path),
  }
}

///|
fn decode_global_resource(
  value : Json,
  path : String,
) -> GlobalResource raise ResourceError {
  let object = object(value, path)
  keys(object, ["path", "module", "name", "valueType", "mutable"], path)
  GlobalResource::{
    path: string_value(object, "path", path),
    module_name: decode_module_name(object, "module", path),
    name: string_value(object, "name", path),
    value_type: string_value(object, "valueType", path),
    mutable: bool_value(object, "mutable", path),
  }
}

///|
fn decode_tag_resource(
  value : Json,
  path : String,
) -> TagResource raise ResourceError {
  let object = object(value, path)
  keys(object, ["path", "module", "name", "typeIndex"], path)
  let type_index = int64_value(object, "typeIndex", path)
  if type_index < 0L {
    invalid_resource("\{path}.typeIndex: expected non-negative integer")
  }
  TagResource::{
    path: string_value(object, "path", path),
    module_name: decode_module_name(object, "module", path),
    name: string_value(object, "name", path),
    type_index,
  }
}

///|
fn strings_array(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Array[String] raise ResourceError {
  let values : Array[String] = []
  for _, item in array_value(value, key, path) {
    match item {
      String(text) => values.push(text)
      _ => invalid_resource("\{path}.\{key}[{index}]: expected string")
    }
  }
  values
}

///|
fn tables_array(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Array[TableResource] raise ResourceError {
  let values : Array[TableResource] = []
  for _, item in array_value(value, key, path) {
    values.push(decode_table_resource(item, "\{path}.\{key}[{index}]"))
  }
  values
}

///|
fn globals_array(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Array[GlobalResource] raise ResourceError {
  let values : Array[GlobalResource] = []
  for _, item in array_value(value, key, path) {
    values.push(decode_global_resource(item, "\{path}.\{key}[{index}]"))
  }
  values
}

///|
fn tags_array(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Array[TagResource] raise ResourceError {
  let values : Array[TagResource] = []
  for _, item in array_value(value, key, path) {
    values.push(decode_tag_resource(item, "\{path}.\{key}[{index}]"))
  }
  values
}

///|
fn decode_surface(
  value : Json,
  path : String,
) -> ResourceSurface raise ResourceError {
  let object = object(value, path)
  keys(
    object,
    ["schemaVersion", "memories", "tables", "globals", "tags", "unsupported"],
    path,
  )
  guard required(object, "schemaVersion", path) is Number(version, ..) &&
    version == 3.0 else {
    return invalid_resource("\{path}.schemaVersion: expected version 3")
  }
  let memories : Array[MemoryResource] = []
  for index, item in array_value(object, "memories", path) {
    memories.push(decode_memory(item, "\{path}.memories[\{index}]"))
  }
  ResourceSurface::{
    schema_version: 3,
    memories,
    tables: tables_array(object, "tables", path),
    globals: globals_array(object, "globals", path),
    tags: tags_array(object, "tags", path),
    unsupported: strings_array(object, "unsupported", path),
  }
}

///|
/// Decode and validate a complete resource lockfile (schema v3).
pub fn decode_resource_lockfile(
  text : String,
) -> ResourceLockfileV3 raise ResourceError {
  let root = object(parse_json(text), "lockfile")
  keys(
    root,
    ["lockfileVersion", "schemaSha256", "artifactSha256", "abiSha256", "abi"],
    "lockfile",
  )
  guard required(root, "lockfileVersion", "lockfile") is Number(version, ..) &&
    version == 3.0 else {
    return invalid_resource("lockfile.lockfileVersion: expected version 3")
  }
  let lockfile = ResourceLockfileV3::{
    lockfile_version: 3,
    schema_sha256: string_value(root, "schemaSha256", "lockfile"),
    artifact_sha256: string_value(root, "artifactSha256", "lockfile"),
    abi_sha256: string_value(root, "abiSha256", "lockfile"),
    abi: decode_surface(required(root, "abi", "lockfile"), "lockfile.abi"),
  }
  if !is_sha256(lockfile.schema_sha256) ||
    !is_sha256(lockfile.artifact_sha256) ||
    !is_sha256(lockfile.abi_sha256) ||
    lockfile.schema_sha256 != sha256_text("moonhostabi.resource.lock/v3") ||
    lockfile.abi_sha256 != resource_surface_sha256(lockfile.abi) {
    invalid_resource("lockfile: fingerprint mismatch")
  }
  if encode_resource_lockfile(lockfile) != text {
    invalid_resource("lockfile: expected canonical JSON")
  }
  lockfile
}

///|
/// Decode and validate a complete resource contract (schema v4).
pub fn decode_resource_contract(
  text : String,
) -> ResourceContract raise ResourceError {
  let root = object(parse_json(text), "contract")
  keys(
    root,
    [
      "schemaVersion", "abiSha256", "memories", "tables", "globals", "tags", "unsupported",
    ],
    "contract",
  )
  guard required(root, "schemaVersion", "contract") is Number(version, ..) &&
    version == 4.0 else {
    return invalid_resource("contract.schemaVersion: expected version 4")
  }
  let memories : Array[MemoryResource] = []
  for index, item in array_value(root, "memories", "contract") {
    memories.push(decode_memory(item, "contract.memories[\{index}]"))
  }
  let contract = ResourceContract::{
    schema_version: 4,
    abi_sha256: string_value(root, "abiSha256", "contract"),
    memories,
    tables: tables_array(root, "tables", "contract"),
    globals: globals_array(root, "globals", "contract"),
    tags: tags_array(root, "tags", "contract"),
    unsupported: strings_array(root, "unsupported", "contract"),
  }
  if !is_sha256(contract.abi_sha256) {
    invalid_resource("contract.abiSha256: expected SHA-256 fingerprint")
  }
  let surface = ResourceSurface::{
    schema_version: 3,
    memories: contract.memories,
    tables: contract.tables,
    globals: contract.globals,
    tags: contract.tags,
    unsupported: contract.unsupported,
  }
  if contract.abi_sha256 != resource_surface_sha256(surface) {
    invalid_resource("contract: fingerprint mismatch")
  }
  if encode_resource_contract(contract) != text {
    invalid_resource("contract: expected canonical JSON")
  }
  contract
}
