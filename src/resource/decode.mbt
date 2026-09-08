///|
/// Errors returned when decoding the standalone resource protocol.
pub(all) suberror ResourceError {
  InvalidResource(String)
} derive(Debug)

///|
pub impl Show for ResourceError with fn output(self, logger) {
  match self {
    InvalidResource(message) => logger.write_string(message)
  }
}

///|
fn[T] invalid_resource(message : String) -> T raise ResourceError {
  raise InvalidResource(message)
}

///|
fn object(value : Json, path : String) -> Map[String, Json] raise ResourceError {
  match value {
    Object(value) => value
    _ => invalid_resource("\{path}: expected object")
  }
}

///|
fn keys(
  value : Map[String, Json],
  expected : Array[String],
  path : String,
) -> Unit raise ResourceError {
  if value.length() != expected.length() {
    invalid_resource("\{path}: unexpected or missing fields")
  }
  for key in expected {
    if value.get(key) is None {
      invalid_resource("\{path}.\{key}: required field is missing")
    }
  }
}

///|
fn required(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ResourceError {
  match value.get(key) {
    Some(item) => item
    None => invalid_resource("\{path}.\{key}: required field is missing")
  }
}

///|
fn string_value(
  value : Map[String, Json],
  key : String,
  path : String,
) -> String raise ResourceError {
  match required(value, key, path) {
    String(text) => text
    _ => invalid_resource("\{path}.\{key}: expected string")
  }
}

///|
fn bool_value(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise ResourceError {
  match required(value, key, path) {
    True => true
    False => false
    _ => invalid_resource("\{path}.\{key}: expected boolean")
  }
}

///|
fn int64_value(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise ResourceError {
  match required(value, key, path) {
    Number(number, ..) => {
      let value = number.to_int64()
      if value.to_double() != number {
        invalid_resource("\{path}.\{key}: expected integer")
      }
      value
    }
    _ => invalid_resource("\{path}.\{key}: expected integer")
  }
}

///|
fn optional_int64(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Int64? raise ResourceError {
  match required(value, key, path) {
    Null => None
    Number(number, ..) => {
      let value = number.to_int64()
      if value.to_double() != number {
        invalid_resource("\{path}.\{key}: expected integer or null")
      }
      Some(value)
    }
    _ => invalid_resource("\{path}.\{key}: expected integer or null")
  }
}

///|
fn decode_memory(
  value : Json,
  path : String,
) -> MemoryResource raise ResourceError {
  let object = object(value, path)
  keys(
    object,
    [
      "path", "module", "name", "minimumPages", "maximumPages", "shared", "memory64",
      "pageSizeLog2",
    ],
    path,
  )
  let module_name = match required(object, "module", path) {
    Null => None
    String(text) => Some(text)
    _ => invalid_resource("\{path}.module: expected string or null")
  }
  MemoryResource::{
    path: string_value(object, "path", path),
    module_name,
    name: string_value(object, "name", path),
    minimum_pages: int64_value(object, "minimumPages", path),
    maximum_pages: optional_int64(object, "maximumPages", path),
    shared: bool_value(object, "shared", path),
    memory64: bool_value(object, "memory64", path),
    page_size_log2: int64_value(object, "pageSizeLog2", path).to_int(),
  }
}

///|
fn array_value(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ResourceError {
  match required(value, key, path) {
    Array(values) => values
    _ => invalid_resource("\{path}.\{key}: expected array")
  }
}

///|
fn decode_abi(value : Json, path : String) -> ResourceAbi raise ResourceError {
  let object = object(value, path)
  keys(object, ["schemaVersion", "memories", "unsupported"], path)
  guard required(object, "schemaVersion", path) is Number(version, ..) &&
    version == 2.0 else {
    return invalid_resource("\{path}.schemaVersion: expected version 2")
  }
  let memories : Array[MemoryResource] = []
  for index, item in array_value(object, "memories", path) {
    memories.push(decode_memory(item, "\{path}.memories[\{index}]"))
  }
  let unsupported : Array[String] = []
  for index, item in array_value(object, "unsupported", path) {
    match item {
      String(text) => unsupported.push(text)
      _ => invalid_resource("\{path}.unsupported[\{index}]: expected string")
    }
  }
  ResourceAbi::{ schema_version: 2, memories, unsupported, }
}

///|
fn parse_json(text : String) -> Json raise ResourceError {
  @json.parse(text) catch {
    _ => invalid_resource("resource: invalid JSON")
  }
}

///|
fn is_sha256(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for character in value {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Decode and validate a canonical resource lockfile v2.
pub fn decode_lockfile(text : String) -> ResourceLockfile raise ResourceError {
  let root = object(parse_json(text), "lockfile")
  keys(
    root,
    ["lockfileVersion", "schemaSha256", "artifactSha256", "abiSha256", "abi"],
    "lockfile",
  )
  guard required(root, "lockfileVersion", "lockfile") is Number(version, ..) &&
    version == 2.0 else {
    return invalid_resource("lockfile.lockfileVersion: expected version 2")
  }
  let lockfile = ResourceLockfile::{
    lockfile_version: 2,
    schema_sha256: string_value(root, "schemaSha256", "lockfile"),
    artifact_sha256: string_value(root, "artifactSha256", "lockfile"),
    abi_sha256: string_value(root, "abiSha256", "lockfile"),
    abi: decode_abi(required(root, "abi", "lockfile"), "lockfile.abi"),
  }
  if !is_sha256(lockfile.schema_sha256) ||
    !is_sha256(lockfile.artifact_sha256) ||
    !is_sha256(lockfile.abi_sha256) ||
    lockfile.schema_sha256 != sha256_text("moonhostabi.resource.lock/v2") ||
    lockfile.abi_sha256 != abi_sha256(lockfile.abi) {
    invalid_resource("lockfile: fingerprint mismatch")
  }
  if encode_lockfile(lockfile) != text {
    invalid_resource("lockfile: expected canonical JSON")
  }
  lockfile
}

///|
/// Decode and validate a canonical memory contract v3.
pub fn decode_memory_contract(
  text : String,
) -> MemoryContract raise ResourceError {
  let root = object(parse_json(text), "contract")
  keys(root, ["schemaVersion", "abiSha256", "memories"], "contract")
  guard required(root, "schemaVersion", "contract") is Number(version, ..) &&
    version == 3.0 else {
    return invalid_resource("contract.schemaVersion: expected version 3")
  }
  let memories : Array[MemoryResource] = []
  for index, item in array_value(root, "memories", "contract") {
    memories.push(decode_memory(item, "contract.memories[\{index}]"))
  }
  let contract = MemoryContract::{
    schema_version: 3,
    abi_sha256: string_value(root, "abiSha256", "contract"),
    memories,
  }
  if encode_memory_contract(contract) != text {
    invalid_resource("contract: expected canonical JSON")
  }
  contract
}
