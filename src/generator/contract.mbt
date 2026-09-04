///|
pub(all) suberror ContractError {
  InvalidContract(String)
} derive(Debug)

///|
pub impl Show for ContractError with fn output(self, logger) {
  match self {
    InvalidContract(message) => logger.write_string(message)
  }
}

///|
priv struct ContractSettings {
  externref_generic : String?
}

///|
fn[T] invalid_contract(message : String) -> T raise ContractError {
  raise InvalidContract(message)
}

///|
fn contract_json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn contract_require_keys(
  object : Map[String, Json],
  keys : Array[String],
  path : String,
) -> Unit raise ContractError {
  if object.length() != keys.length() {
    invalid_contract("\{path}: unexpected or missing fields")
  }
  for key in keys {
    if object.get(key) is None {
      invalid_contract("\{path}.\{key}: required field is missing")
    }
  }
}

///|
fn contract_value(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ContractError {
  match object.get(key) {
    Some(value) => value
    None => invalid_contract("\{path}.\{key}: required field is missing")
  }
}

///|
fn contract_string(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String raise ContractError {
  match contract_value(object, key, path) {
    String(value) => value
    _ => invalid_contract("\{path}.\{key}: expected string")
  }
}

///|
fn contract_strings(
  value : Json,
  path : String,
) -> Array[String] raise ContractError {
  guard value is Array(values) else {
    return invalid_contract("\{path}: expected string array")
  }
  let result : Array[String] = []
  for index, item in values {
    match item {
      String(text) => result.push(text)
      _ => invalid_contract("\{path}[\{index}]: expected string")
    }
  }
  result
}

///|
fn is_identifier_start(character : Char) -> Bool {
  (character >= 'a' && character <= 'z') ||
  (character >= 'A' && character <= 'Z') ||
  character == '_'
}

///|
fn is_identifier_continue(character : Char) -> Bool {
  is_identifier_start(character) || (character >= '0' && character <= '9')
}

///|
fn is_safe_typescript_identifier(value : String) -> Bool {
  if value.is_empty() ||
    [
      "abstract", "any", "as", "asserts", "async", "await", "bigint", "boolean",
      "break", "case", "catch", "class", "const", "constructor", "continue", "debugger",
      "declare", "default", "delete", "do", "else", "enum", "export", "extends",
      "false", "finally", "for", "from", "function", "get", "global", "if", "implements",
      "import", "in", "infer", "instanceof", "interface", "intrinsic", "is", "keyof",
      "let", "module", "namespace", "never", "new", "null", "number", "object", "of",
      "out", "override", "package", "private", "protected", "public", "readonly",
      "require", "return", "satisfies", "set", "static", "string", "super", "switch",
      "symbol", "this", "throw", "true", "try", "type", "typeof", "undefined", "unique",
      "unknown", "using", "var", "void", "while", "with", "yield",
    ].contains(value) {
    return false
  }
  let mut index = 0
  for character in value {
    if (index == 0 && !is_identifier_start(character)) ||
      (index > 0 && !is_identifier_continue(character)) {
      return false
    }
    index += 1
  }
  true
}

///|
fn function_signature(function : @model.AbiFunction) -> String {
  let params = function.params.map(fn(value) { value.stable_text() }).join(",")
  let results = function.results
    .map(fn(value) { value.stable_text() })
    .join(",")
  "(\{params})->(\{results})"
}

///|
fn is_make_closure(function : @model.AbiFunction) -> Bool {
  function.module_name == Some("moonbit:ffi") && function.name == "make_closure"
}

///|
fn unresolved_externref_locations(
  function : @model.AbiFunction,
  settings : ContractSettings,
) -> Array[String] {
  if settings.externref_generic is Some(_) {
    return []
  }
  let locations : Array[String] = []
  for index, value in function.params {
    if value == @model.ExternRef {
      locations.push("params[\{index}]")
    }
  }
  for index, value in function.results {
    if value == @model.ExternRef {
      locations.push("results[\{index}]")
    }
  }
  locations
}

///|
fn encode_contract_import(
  function : @model.AbiFunction,
  settings : ContractSettings,
) -> String {
  let module_name = function.module_name.unwrap_or("")
  let implementation = if is_make_closure(function) {
    "generated"
  } else {
    "required"
  }
  let unresolved = unresolved_externref_locations(function, settings)
  "{\"module\":\{contract_json_string(module_name)},\"name\":\{contract_json_string(function.name)},\"signature\":\{contract_json_string(function_signature(function))},\"implementation\":\{contract_json_string(implementation)},\"unresolvedSemanticNames\":[\{unresolved.map(fn(value) { contract_json_string(value) }).join(",")}]}"
}

///|
fn encode_contract(
  abi : @model.HostAbi,
  abi_sha256 : String,
  settings : ContractSettings,
) -> String {
  let imports = @model.sort_abi_functions(abi.imports)
  let generic = match settings.externref_generic {
    Some(value) => contract_json_string(value)
    None => "null"
  }
  "{\"schemaVersion\":1,\"abiSha256\":\{contract_json_string(abi_sha256)},\"externrefGeneric\":\{generic},\"imports\":[\{imports.map(fn(function) { encode_contract_import(function, settings) }).join(",")}]}\n"
}

///|
fn decode_contract_settings(
  abi : @model.HostAbi,
  abi_sha256 : String,
  text : String,
) -> ContractSettings raise ContractError {
  if text.length() > 1024 * 1024 {
    invalid_contract("contract: input exceeds 1 MiB limit")
  }
  let root : Json = @json.parse(text) catch {
    _ => invalid_contract("contract: invalid JSON")
  }
  guard root is Object(object) else {
    return invalid_contract("contract: expected object")
  }
  contract_require_keys(
    object,
    ["schemaVersion", "abiSha256", "externrefGeneric", "imports"],
    "contract",
  )
  guard contract_value(object, "schemaVersion", "contract")
    is Number(version, ..) &&
    version == 1.0 else {
    return invalid_contract("contract.schemaVersion: expected version 1")
  }
  if contract_string(object, "abiSha256", "contract") != abi_sha256 {
    invalid_contract("contract.abiSha256: contract does not match artifact ABI")
  }
  let externref_generic : String? = match
    contract_value(object, "externrefGeneric", "contract") {
    Null => None
    String(value) => {
      if !is_safe_typescript_identifier(value) {
        invalid_contract(
          "contract.externrefGeneric: expected a safe TypeScript identifier",
        )
      }
      Some(value)
    }
    _ => invalid_contract("contract.externrefGeneric: expected string or null")
  }
  let settings = ContractSettings::{ externref_generic, }
  guard contract_value(object, "imports", "contract") is Array(imports) else {
    return invalid_contract("contract.imports: expected array")
  }
  let expected = @model.sort_abi_functions(abi.imports)
  if imports.length() != expected.length() {
    invalid_contract("contract.imports: import count does not match ABI")
  }
  for index, value in imports {
    let path = "contract.imports[\{index}]"
    guard value is Object(import_object) else {
      return invalid_contract("\{path}: expected object")
    }
    contract_require_keys(
      import_object,
      [
        "module", "name", "signature", "implementation", "unresolvedSemanticNames",
      ],
      path,
    )
    let function = expected[index]
    let expected_implementation = if is_make_closure(function) {
      "generated"
    } else {
      "required"
    }
    if contract_string(import_object, "module", path) !=
      function.module_name.unwrap_or("") ||
      contract_string(import_object, "name", path) != function.name ||
      contract_string(import_object, "signature", path) !=
      function_signature(function) ||
      contract_string(import_object, "implementation", path) !=
      expected_implementation ||
      contract_strings(
        contract_value(import_object, "unresolvedSemanticNames", path),
        "\{path}.unresolvedSemanticNames",
      ) !=
      unresolved_externref_locations(function, settings) {
      invalid_contract("\{path}: import contract does not match ABI")
    }
  }
  settings
}

///|
fn resolve_contract_settings(
  abi : @model.HostAbi,
  abi_sha256 : String,
  contract : String?,
) -> ContractSettings raise ContractError {
  match contract {
    Some(text) => decode_contract_settings(abi, abi_sha256, text)
    None => ContractSettings::{ externref_generic: None }
  }
}
