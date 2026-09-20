///|
fn strict_i64(value : Json, path : String) -> Int64 raise ResourceError {
  match value {
    Number(_, repr=Some(text)) => {
      let number = @string.parse_int64(text[:]) catch {
        _ => return invalid_resource("\{path}: expected signed 64-bit integer")
      }
      if "\{number}" != text {
        invalid_resource("\{path}: expected canonical integer")
      }
      number
    }
    Number(number, repr=None) => {
      // The JSON parser omits repr for exactly represented small integers.
      if number < -9007199254740991.0 || number > 9007199254740991.0 {
        invalid_resource("\{path}: missing exact integer representation")
      }
      let integer = number.to_int64()
      if integer.to_double() != number {
        invalid_resource("\{path}: expected integer")
      }
      integer
    }
    _ => invalid_resource("\{path}: expected integer")
  }
}

///|
fn strict_field_i64(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise ResourceError {
  strict_i64(required(value, key, path), "\{path}.\{key}")
}

///|
fn strict_optional_i64(
  value : Map[String, Json],
  key : String,
  path : String,
) -> Int64? raise ResourceError {
  match required(value, key, path) {
    Null => None
    item => Some(strict_i64(item, "\{path}.\{key}"))
  }
}

///|
fn valid_resource_type(value : String) -> Bool {
  match value {
    "i32"
    | "i64"
    | "f32"
    | "f64"
    | "v128"
    | "funcref"
    | "externref"
    | "(ref func)"
    | "(ref extern)"
    | "anyref"
    | "exnref"
    | "structref"
    | "arrayref"
    | "(ref any)"
    | "(ref eq)"
    | "eqref"
    | "(ref i31)"
    | "i31ref"
    | "(ref struct)"
    | "(ref array)"
    | "(ref none)"
    | "nullref"
    | "nullfuncref"
    | "nullexnref"
    | "nullexternref" => true
    _ => false
  }
}

///|
fn validate_resource_identity(
  path : String,
  module_name : String?,
  name : String,
  seen : Map[String, Bool],
) -> Unit raise ResourceError {
  if path != resource_path(module_name, name) {
    invalid_resource("\{path}: path does not match module and name")
  }
  if seen.get(path) is Some(_) {
    invalid_resource("\{path}: duplicate resource identity")
  }
  seen[path] = true
}

///|
fn validate_limits(
  minimum : Int64,
  maximum : Int64?,
  bound : Int64?,
  path : String,
) -> Unit raise ResourceError {
  if minimum < 0L {
    invalid_resource("\{path}: minimum must be non-negative")
  }
  match maximum {
    Some(maximum) if maximum < minimum =>
      invalid_resource("\{path}: maximum must be at least minimum")
    _ => ()
  }
  match bound {
    Some(bound) => {
      if minimum > bound {
        invalid_resource("\{path}: minimum exceeds address space")
      }
      match maximum {
        Some(maximum) if maximum > bound =>
          invalid_resource("\{path}: maximum exceeds address space")
        _ => ()
      }
    }
    None => ()
  }
}

///|
fn validate_surface_v4(surface : ResourceSurfaceV4) -> Unit raise ResourceError {
  if surface.schema_version != 4 {
    invalid_resource("surface.schemaVersion: expected version 4")
  }
  let seen : Map[String, Bool] = Map([])
  for value in surface.memories {
    validate_resource_identity(value.path, value.module_name, value.name, seen)
    if value.page_size_log2 < 0 || value.page_size_log2 > 30 {
      invalid_resource(
        "\{value.path}.pageSizeLog2: expected integer between 0 and 30",
      )
    }
    let bits = (if value.memory64 { 64 } else { 32 }) - value.page_size_log2
    validate_limits(
      value.minimum_pages,
      value.maximum_pages,
      if bits < 63 {
        Some(1L << bits)
      } else {
        None
      },
      value.path,
    )
    if value.shared && value.maximum_pages is None {
      invalid_resource("\{value.path}: shared memory requires maximumPages")
    }
  }
  for value in surface.tables {
    validate_resource_identity(value.path, value.module_name, value.name, seen)
    validate_limits(
      value.minimum_elements,
      value.maximum_elements,
      if value.table64 {
        None
      } else {
        Some(4294967295L)
      },
      value.path,
    )
    if !valid_resource_type(value.element_type) ||
      ["i32", "i64", "f32", "f64", "v128"].contains(value.element_type) {
      invalid_resource(
        "\{value.path}.elementType: expected canonical reference type",
      )
    }
  }
  for value in surface.globals {
    validate_resource_identity(value.path, value.module_name, value.name, seen)
    if !valid_resource_type(value.value_type) {
      invalid_resource("\{value.path}.valueType: expected canonical value type")
    }
  }
  for value in surface.tags {
    validate_resource_identity(value.path, value.module_name, value.name, seen)
    if !value.results.is_empty() {
      invalid_resource(
        "\{value.path}.results: tag signatures must have no results",
      )
    }
    for param in value.params {
      if !valid_resource_type(param) {
        invalid_resource("\{value.path}.params: expected canonical value type")
      }
    }
  }
  let unsupported_seen : Map[String, Bool] = Map([])
  for reason in surface.unsupported {
    if reason.is_empty() || unsupported_seen.get(reason) is Some(_) {
      invalid_resource("surface.unsupported: empty or duplicate reason")
    }
    unsupported_seen[reason] = true
  }
}

///|
fn decode_memory_v4(
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
  let page = strict_field_i64(object, "pageSizeLog2", path)
  if page < 0L || page > 30L {
    invalid_resource("\{path}.pageSizeLog2: expected integer between 0 and 30")
  }
  {
    path: string_value(object, "path", path),
    module_name: nullable_module_v4(object, path),
    name: string_value(object, "name", path),
    minimum_pages: strict_field_i64(object, "minimumPages", path),
    maximum_pages: strict_optional_i64(object, "maximumPages", path),
    shared: bool_value(object, "shared", path),
    memory64: bool_value(object, "memory64", path),
    page_size_log2: page.to_int(),
  }
}

///|
fn nullable_module_v4(
  object : Map[String, Json],
  path : String,
) -> String? raise ResourceError {
  match required(object, "module", path) {
    Null => None
    String(value) => Some(value)
    _ => invalid_resource("\{path}.module: expected string or null")
  }
}

///|
fn decode_surface_fields_v4(
  root : Map[String, Json],
  path : String,
) -> ResourceSurfaceV4 raise ResourceError {
  let memories : Array[MemoryResource] = []
  for index, value in array_value(root, "memories", path) {
    memories.push(decode_memory_v4(value, "\{path}.memories[\{index}]"))
  }
  let tables : Array[TableResource] = []
  for index, value in array_value(root, "tables", path) {
    let at = "\{path}.tables[\{index}]"
    let object = object(value, at)
    keys(
      object,
      [
        "path", "module", "name", "elementType", "minimumElements", "maximumElements",
        "table64",
      ],
      at,
    )
    tables.push({
      path: string_value(object, "path", at),
      module_name: nullable_module_v4(object, at),
      name: string_value(object, "name", at),
      element_type: string_value(object, "elementType", at),
      minimum_elements: strict_field_i64(object, "minimumElements", at),
      maximum_elements: strict_optional_i64(object, "maximumElements", at),
      table64: bool_value(object, "table64", at),
    })
  }
  let globals : Array[GlobalResource] = []
  for index, value in array_value(root, "globals", path) {
    let at = "\{path}.globals[\{index}]"
    let object = object(value, at)
    keys(object, ["path", "module", "name", "valueType", "mutable"], at)
    globals.push({
      path: string_value(object, "path", at),
      module_name: nullable_module_v4(object, at),
      name: string_value(object, "name", at),
      value_type: string_value(object, "valueType", at),
      mutable: bool_value(object, "mutable", at),
    })
  }
  let tags : Array[TagSignatureResource] = []
  for index, value in array_value(root, "tags", path) {
    let at = "\{path}.tags[\{index}]"
    let object = object(value, at)
    keys(object, ["path", "module", "name", "params", "results"], at)
    tags.push({
      path: string_value(object, "path", at),
      module_name: nullable_module_v4(object, at),
      name: string_value(object, "name", at),
      params: strings_array(object, "params", at),
      results: strings_array(object, "results", at),
    })
  }
  let surface : ResourceSurfaceV4 = {
    schema_version: 4,
    memories,
    tables,
    globals,
    tags,
    unsupported: strings_array(root, "unsupported", path),
  }
  validate_surface_v4(surface)
  surface
}

///|
fn decode_surface_v4(
  value : Json,
  path : String,
) -> ResourceSurfaceV4 raise ResourceError {
  let root = object(value, path)
  keys(
    root,
    ["schemaVersion", "memories", "tables", "globals", "tags", "unsupported"],
    path,
  )
  if strict_field_i64(root, "schemaVersion", path) != 4L {
    invalid_resource("\{path}.schemaVersion: expected version 4")
  }
  decode_surface_fields_v4(root, path)
}

///|
pub fn decode_resource_lockfile_v4(
  text : String,
) -> ResourceLockfileV4 raise ResourceError {
  let root = object(parse_json(text), "lockfile")
  keys(
    root,
    ["lockfileVersion", "schemaSha256", "artifactSha256", "abiSha256", "abi"],
    "lockfile",
  )
  if strict_field_i64(root, "lockfileVersion", "lockfile") != 4L {
    invalid_resource("lockfile.lockfileVersion: expected version 4")
  }
  let lockfile : ResourceLockfileV4 = {
    lockfile_version: 4,
    schema_sha256: string_value(root, "schemaSha256", "lockfile"),
    artifact_sha256: string_value(root, "artifactSha256", "lockfile"),
    abi_sha256: string_value(root, "abiSha256", "lockfile"),
    abi: decode_surface_v4(required(root, "abi", "lockfile"), "lockfile.abi"),
  }
  if lockfile.schema_sha256 != sha256_text("moonhostabi.resource.lock/v4") ||
    !is_sha256(lockfile.artifact_sha256) ||
    lockfile.abi_sha256 != resource_surface_v4_sha256(lockfile.abi) {
    invalid_resource("lockfile: fingerprint mismatch")
  }
  if encode_resource_lockfile_v4(lockfile) != text {
    invalid_resource("lockfile: expected canonical JSON")
  }
  lockfile
}

///|
pub fn decode_resource_contract_v5(
  text : String,
) -> ResourceContractV5 raise ResourceError {
  let root = object(parse_json(text), "contract")
  keys(
    root,
    [
      "schemaVersion", "abiSha256", "memories", "tables", "globals", "tags", "unsupported",
    ],
    "contract",
  )
  if strict_field_i64(root, "schemaVersion", "contract") != 5L {
    invalid_resource("contract.schemaVersion: expected version 5")
  }
  let surface = decode_surface_fields_v4(root, "contract")
  let contract = create_resource_contract_v5(surface)
  if string_value(root, "abiSha256", "contract") != contract.abi_sha256 {
    invalid_resource("contract: fingerprint mismatch")
  }
  if encode_resource_contract_v5(contract) != text {
    invalid_resource("contract: expected canonical JSON")
  }
  contract
}
