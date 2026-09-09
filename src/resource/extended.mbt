///|
/// A table crossing a compiled Wasm host boundary.
pub(all) struct TableResource {
  path : String
  module_name : String?
  name : String
  element_type : String
  minimum_elements : Int64
  maximum_elements : Int64?
  table64 : Bool
} derive(Eq, Debug)

///|
/// A global crossing a compiled Wasm host boundary.
pub(all) struct GlobalResource {
  path : String
  module_name : String?
  name : String
  value_type : String
  mutable : Bool
} derive(Eq, Debug)

///|
/// An exception tag crossing a compiled Wasm host boundary.
pub(all) struct TagResource {
  path : String
  module_name : String?
  name : String
  type_index : Int64
} derive(Eq, Debug)

///|
/// Complete resource ABI surface used by the resource protocol v3.
///
/// The existing `ResourceAbi` and memory contract remain stable. This surface
/// adds first-class table/global/tag entries for callers that need a complete
/// host-resource lock and contract.
pub(all) struct ResourceSurface {
  schema_version : Int
  memories : Array[MemoryResource]
  tables : Array[TableResource]
  globals : Array[GlobalResource]
  tags : Array[TagResource]
  unsupported : Array[String]
} derive(Eq, Debug)

///|
/// Contract for all resources in a `ResourceSurface` (schema v4).
pub(all) struct ResourceContract {
  schema_version : Int
  abi_sha256 : String
  memories : Array[MemoryResource]
  tables : Array[TableResource]
  globals : Array[GlobalResource]
  tags : Array[TagResource]
  unsupported : Array[String]
} derive(Eq, Debug)

///|
/// Resource lockfile carrying a complete resource surface (schema v3).
pub(all) struct ResourceLockfileV3 {
  lockfile_version : Int
  schema_sha256 : String
  artifact_sha256 : String
  abi_sha256 : String
  abi : ResourceSurface
} derive(Eq, Debug)

///|
fn encode_table_resource(value : TableResource) -> String {
  let module_json = match value.module_name {
    Some(name) => json_string(name)
    None => "null"
  }
  "{\"path\":\{json_string(value.path)},\"module\":\{module_json},\"name\":\{json_string(value.name)},\"elementType\":\{json_string(value.element_type)},\"minimumElements\":\{value.minimum_elements},\"maximumElements\":\{json_optional_i64(value.maximum_elements)},\"table64\":\{json_bool(value.table64)}}"
}

///|
fn encode_tables(values : Array[TableResource]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.path.compare(right.path) })
  "[\{sorted.map(fn(value) { encode_table_resource(value) }).join(",")}]"
}

///|
fn encode_global_resource(value : GlobalResource) -> String {
  let module_json = match value.module_name {
    Some(name) => json_string(name)
    None => "null"
  }
  "{\"path\":\{json_string(value.path)},\"module\":\{module_json},\"name\":\{json_string(value.name)},\"valueType\":\{json_string(value.value_type)},\"mutable\":\{json_bool(value.mutable)}}"
}

///|
fn encode_globals(values : Array[GlobalResource]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.path.compare(right.path) })
  "[\{sorted.map(fn(value) { encode_global_resource(value) }).join(",")}]"
}

///|
fn encode_tag_resource(value : TagResource) -> String {
  let module_json = match value.module_name {
    Some(name) => json_string(name)
    None => "null"
  }
  "{\"path\":\{json_string(value.path)},\"module\":\{module_json},\"name\":\{json_string(value.name)},\"typeIndex\":\{value.type_index}}"
}

///|
fn encode_tags(values : Array[TagResource]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.path.compare(right.path) })
  "[\{sorted.map(fn(value) { encode_tag_resource(value) }).join(",")}]"
}

///|
/// Return canonical JSON for a complete resource surface.
pub fn encode_resource_surface(surface : ResourceSurface) -> String {
  "{\"schemaVersion\":\{surface.schema_version},\"memories\":\{encode_memories(surface.memories)},\"tables\":\{encode_tables(surface.tables)},\"globals\":\{encode_globals(surface.globals)},\"tags\":\{encode_tags(surface.tags)},\"unsupported\":\{encode_strings(surface.unsupported)}}"
}

///|
/// Return the SHA-256 fingerprint of a complete resource surface.
pub fn resource_surface_sha256(surface : ResourceSurface) -> String {
  sha256_text(encode_resource_surface(surface))
}

///|
/// Create a complete resource lockfile (lockfile schema v3).
pub fn create_resource_lockfile(
  surface : ResourceSurface,
  artifact : Bytes,
) -> ResourceLockfileV3 {
  let canonical = ResourceSurface::{
    schema_version: 3,
    memories: surface.memories,
    tables: surface.tables,
    globals: surface.globals,
    tags: surface.tags,
    unsupported: surface.unsupported,
  }
  ResourceLockfileV3::{
    lockfile_version: 3,
    schema_sha256: sha256_text("moonhostabi.resource.lock/v3"),
    artifact_sha256: @crypto.bytes_to_hex_string(@crypto.sha256(artifact)),
    abi_sha256: resource_surface_sha256(canonical),
    abi: canonical,
  }
}

///|
/// Encode a canonical complete resource lockfile.
pub fn encode_resource_lockfile(lockfile : ResourceLockfileV3) -> String {
  "{\"lockfileVersion\":\{lockfile.lockfile_version},\"schemaSha256\":\{json_string(lockfile.schema_sha256)},\"artifactSha256\":\{json_string(lockfile.artifact_sha256)},\"abiSha256\":\{json_string(lockfile.abi_sha256)},\"abi\":\{encode_resource_surface(lockfile.abi)}}"
}

///|
/// Create a complete resource contract (contract schema v4).
pub fn create_resource_contract(surface : ResourceSurface) -> ResourceContract {
  let canonical = ResourceSurface::{
    schema_version: 3,
    memories: surface.memories,
    tables: surface.tables,
    globals: surface.globals,
    tags: surface.tags,
    unsupported: surface.unsupported,
  }
  ResourceContract::{
    schema_version: 4,
    abi_sha256: resource_surface_sha256(canonical),
    memories: canonical.memories,
    tables: canonical.tables,
    globals: canonical.globals,
    tags: canonical.tags,
    unsupported: canonical.unsupported,
  }
}

///|
/// Encode a canonical complete resource contract.
pub fn encode_resource_contract(contract : ResourceContract) -> String {
  "{\"schemaVersion\":\{contract.schema_version},\"abiSha256\":\{json_string(contract.abi_sha256)},\"memories\":\{encode_memories(contract.memories)},\"tables\":\{encode_tables(contract.tables)},\"globals\":\{encode_globals(contract.globals)},\"tags\":\{encode_tags(contract.tags)},\"unsupported\":\{encode_strings(contract.unsupported)}}"
}

///|
/// Validate a complete resource contract against its surface.
pub fn validate_resource_contract(
  surface : ResourceSurface,
  contract : ResourceContract,
) -> Bool {
  let canonical = ResourceSurface::{
    schema_version: 3,
    memories: surface.memories,
    tables: surface.tables,
    globals: surface.globals,
    tags: surface.tags,
    unsupported: surface.unsupported,
  }
  contract.schema_version == 4 &&
  contract.abi_sha256 == resource_surface_sha256(canonical) &&
  encode_memories(contract.memories) == encode_memories(canonical.memories) &&
  encode_tables(contract.tables) == encode_tables(canonical.tables) &&
  encode_globals(contract.globals) == encode_globals(canonical.globals) &&
  encode_tags(contract.tags) == encode_tags(canonical.tags) &&
  encode_strings(contract.unsupported) == encode_strings(canonical.unsupported)
}
