///|
/// A memory crossing a compiled Wasm host boundary.
pub(all) struct MemoryResource {
  path : String
  module_name : String?
  name : String
  minimum_pages : Int64
  maximum_pages : Int64?
  shared : Bool
  memory64 : Bool
  page_size_log2 : Int
} derive(Eq, Debug)

///|
/// The standalone resource ABI surface. Function ABI remains in HostAbi v1.
pub(all) struct ResourceAbi {
  schema_version : Int
  memories : Array[MemoryResource]
  unsupported : Array[String]
} derive(Eq, Debug)

///|
/// Explicit memory contract consumed by a host runtime.
pub(all) struct MemoryContract {
  schema_version : Int
  abi_sha256 : String
  memories : Array[MemoryResource]
} derive(Eq, Debug)

///|
/// Resource lockfile that fingerprints the canonical resource surface.
pub(all) struct ResourceLockfile {
  lockfile_version : Int
  schema_sha256 : String
  artifact_sha256 : String
  abi_sha256 : String
  abi : ResourceAbi
} derive(Eq, Debug)

///|
fn json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn json_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn json_optional_i64(value : Int64?) -> String {
  match value {
    Some(number) => "\{number}"
    None => "null"
  }
}

///|
fn encode_memory(value : MemoryResource) -> String {
  let module_json = match value.module_name {
    Some(name) => json_string(name)
    None => "null"
  }
  "{\"path\":\{json_string(value.path)},\"module\":\{module_json},\"name\":\{json_string(value.name)},\"minimumPages\":\{value.minimum_pages},\"maximumPages\":\{json_optional_i64(value.maximum_pages)},\"shared\":\{json_bool(value.shared)},\"memory64\":\{json_bool(value.memory64)},\"pageSizeLog2\":\{value.page_size_log2}}"
}

///|
fn encode_memories(values : Array[MemoryResource]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.path.compare(right.path) })
  "[\{sorted.map(fn(value) { encode_memory(value) }).join(",")}]"
}

///|
fn encode_strings(values : Array[String]) -> String {
  let sorted = values.copy()
  sorted.sort_by(fn(left, right) { left.compare(right) })
  "[\{sorted.map(fn(value) { json_string(value) }).join(",")}]"
}

///|
/// Return canonical JSON for the resource ABI.
pub fn encode_canonical_abi(abi : ResourceAbi) -> String {
  "{\"schemaVersion\":\{abi.schema_version},\"memories\":\{encode_memories(abi.memories)},\"unsupported\":\{encode_strings(abi.unsupported)}}"
}

///|
/// Return the SHA-256 fingerprint of the canonical resource ABI.
pub fn abi_sha256(abi : ResourceAbi) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding.encode(@encoding.UTF8, encode_canonical_abi(abi))),
  )
}

///|
/// Create a v2 resource lockfile from an artifact and its memory surface.
pub fn create_lockfile(abi : ResourceAbi, artifact : Bytes) -> ResourceLockfile {
  let canonical = ResourceAbi::{
    schema_version: 2,
    memories: abi.memories,
    unsupported: abi.unsupported,
  }
  ResourceLockfile::{
    lockfile_version: 2,
    schema_sha256: abi_sha256(ResourceAbi::{
      schema_version: 2,
      memories: [],
      unsupported: [],
    }),
    artifact_sha256: @crypto.bytes_to_hex_string(@crypto.sha256(artifact)),
    abi_sha256: abi_sha256(canonical),
    abi: canonical,
  }
}

///|
/// Encode a canonical v2 resource lockfile.
pub fn encode_lockfile(lockfile : ResourceLockfile) -> String {
  "{\"lockfileVersion\":\{lockfile.lockfile_version},\"schemaSha256\":\{json_string(lockfile.schema_sha256)},\"artifactSha256\":\{json_string(lockfile.artifact_sha256)},\"abiSha256\":\{json_string(lockfile.abi_sha256)},\"abi\":\{encode_canonical_abi(lockfile.abi)}}"
}

///|
/// Create a memory contract bound to a resource ABI fingerprint.
pub fn create_memory_contract(abi : ResourceAbi) -> MemoryContract {
  let canonical = ResourceAbi::{
    schema_version: 2,
    memories: abi.memories,
    unsupported: abi.unsupported,
  }
  MemoryContract::{
    schema_version: 3,
    abi_sha256: abi_sha256(canonical),
    memories: canonical.memories,
  }
}

///|
/// Encode a canonical memory contract (schema v3).
pub fn encode_memory_contract(contract : MemoryContract) -> String {
  "{\"schemaVersion\":\{contract.schema_version},\"abiSha256\":\{json_string(contract.abi_sha256)},\"memories\":\{encode_memories(contract.memories)}}"
}

///|
/// Generate a canonical memory contract JSON document from a resource ABI.
pub fn generate_memory_contract(abi : ResourceAbi) -> String {
  encode_memory_contract(create_memory_contract(abi))
}

///|
/// Validate that a memory contract matches the resource ABI.
pub fn validate_memory_contract(
  abi : ResourceAbi,
  contract : MemoryContract,
) -> Bool {
  let canonical = ResourceAbi::{
    schema_version: 2,
    memories: abi.memories,
    unsupported: abi.unsupported,
  }
  contract.schema_version == 3 &&
  contract.abi_sha256 == abi_sha256(canonical) &&
  encode_memories(contract.memories) == encode_memories(canonical.memories)
}
