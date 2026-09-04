///|
pub(all) struct GenerationResult {
  typescript : String
  contract : String
  abi_sha256 : String
  diagnostics : Array[@model.Diagnostic]
} derive(Eq, Debug)

///|
fn generator_diagnostic(path : String, message : String) -> @model.Diagnostic {
  @model.Diagnostic::{
    code: @model.MHA_PROJECT_UNREPRESENTABLE,
    severity: @model.Error,
    path,
    message,
    byte_offset: None,
  }
}

///|
fn validate_value_type(
  value : @model.AbiValueType,
  path : String,
  diagnostics : Array[@model.Diagnostic],
) -> Unit {
  match value {
    @model.TypedRef(type_id, _) =>
      diagnostics.push(
        generator_diagnostic(
          path,
          "typed GC reference \{type_id} cannot be represented by the JavaScript adapter",
        ),
      )
    @model.V128 =>
      diagnostics.push(
        generator_diagnostic(
          path, "v128 cannot be represented by the JavaScript adapter",
        ),
      )
    @model.Unknown(source) =>
      diagnostics.push(
        generator_diagnostic(path, "unsupported ABI value type at \{source}"),
      )
    _ => ()
  }
}

///|
fn validate_function(
  function : @model.AbiFunction,
  path : String,
  diagnostics : Array[@model.Diagnostic],
) -> Unit {
  for index, value in function.params {
    validate_value_type(value, "\{path}.params[\{index}]", diagnostics)
  }
  for index, value in function.results {
    validate_value_type(value, "\{path}.results[\{index}]", diagnostics)
  }
  if is_make_closure(function) &&
    !(function.params == [@model.FuncRef, @model.ExternRef] &&
    function.results == [@model.FuncRef]) {
    diagnostics.push(@model.Diagnostic::{
      code: @model.MHA_ADAPTER_MISMATCH,
      severity: @model.Error,
      path,
      message: "moonbit:ffi.make_closure has an unsupported signature",
      byte_offset: None,
    })
  }
}

///|
fn validate_generator_abi(abi : @model.HostAbi) -> Array[@model.Diagnostic] {
  let diagnostics : Array[@model.Diagnostic] = []
  let imports = @model.sort_abi_functions(abi.imports)
  let exports = @model.sort_abi_functions(abi.exports)
  for function in imports {
    let module_name = function.module_name.unwrap_or("")
    validate_function(
      function,
      "imports[\{module_name}.\{function.name}]",
      diagnostics,
    )
  }
  for function in exports {
    validate_function(function, "exports[\{function.name}]", diagnostics)
  }
  diagnostics
}

///|
fn typescript_type(value : @model.AbiValueType, generic : String) -> String {
  match value {
    @model.I32 | @model.F32 | @model.F64 => "number"
    @model.I64 => "bigint"
    @model.ExternRef => generic
    @model.FuncRef => "(...args: unknown[]) => unknown"
    @model.V128 | @model.TypedRef(_, _) | @model.Unknown(_) => "never"
  }
}

///|
fn typescript_parameters(
  values : Array[@model.AbiValueType],
  generic : String,
  prefix : String,
) -> String {
  let parameters : Array[String] = []
  for index, value in values {
    parameters.push("\{prefix}\{index}: \{typescript_type(value, generic)}")
  }
  parameters.join(", ")
}

///|
fn typescript_result(
  values : Array[@model.AbiValueType],
  generic : String,
) -> String {
  match values {
    [] => "void"
    [value] => typescript_type(value, generic)
    _ =>
      "[\{values.map(fn(value) { typescript_type(value, generic) }).join(", ")}]"
  }
}

///|
fn typescript_function_type(
  function : @model.AbiFunction,
  generic : String,
  parameter_prefix : String,
) -> String {
  "(\{typescript_parameters(function.params, generic, parameter_prefix)}) => \{typescript_result(function.results, generic)}"
}

///|
fn sorted_import_modules(imports : Array[@model.AbiFunction]) -> Array[String] {
  let modules : Array[String] = []
  for function in imports {
    let module_name = function.module_name.unwrap_or("")
    if modules.last() != Some(module_name) {
      modules.push(module_name)
    }
  }
  modules
}

///|
fn has_make_closure(imports : Array[@model.AbiFunction]) -> Bool {
  for function in imports {
    if is_make_closure(function) {
      return true
    }
  }
  false
}

///|
fn append_host_import_type(
  lines : Array[String],
  imports : Array[@model.AbiFunction],
  generic : String,
) -> Unit {
  lines.push("export type HostImports<\{generic} = unknown> = {")
  for module_name in sorted_import_modules(imports) {
    lines.push("  \{contract_json_string(module_name)}: {")
    for function in imports {
      if function.module_name.unwrap_or("") == module_name {
        lines.push(
          "    \{contract_json_string(function.name)}: \{typescript_function_type(function, generic, "arg")};",
        )
      }
    }
    lines.push("  };")
  }
  lines.push("};")
}

///|
fn append_module_export_type(
  lines : Array[String],
  exports : Array[@model.AbiFunction],
  generic : String,
) -> Unit {
  lines.push("export type ModuleExports<\{generic} = unknown> = {")
  for function in exports {
    lines.push(
      "  \{contract_json_string(function.name)}: \{typescript_function_type(function, generic, "arg")};",
    )
  }
  lines.push("};")
}

///|
fn append_make_closure_helper(lines : Array[String]) -> Unit {
  lines.push("export function makeMoonBitClosure<TContext>(")
  lines.push("  fn: (...args: unknown[]) => unknown,")
  lines.push("  context: TContext,")
  lines.push("): (...args: unknown[]) => unknown {")
  lines.push("  return (...args: unknown[]) => fn(context, ...args);")
  lines.push("}")
}

///|
fn throwing_stub(function : @model.AbiFunction) -> Array[String] {
  let params : Array[String] = []
  for index in 0..<function.params.length() {
    params.push("_arg\{index}")
  }
  let module_name = function.module_name.unwrap_or("")
  let message = "MHA_ADAPTER_MISMATCH: missing host import \{module_name}.\{function.name} \{function_signature(function)}"
  [
    "\{contract_json_string(function.name)}: (\{params.join(", ")}) => {",
    "  throw new Error(\{contract_json_string(message)});",
    "},",
  ]
}

///|
fn append_host_import_factory(
  lines : Array[String],
  imports : Array[@model.AbiFunction],
  generic : String,
) -> Unit {
  lines.push(
    "export function createHostImports<\{generic} = unknown>(): HostImports<\{generic}> {",
  )
  if imports.is_empty() {
    lines.push("  return {};")
    lines.push("}")
    return
  }
  lines.push("  return {")
  for module_name in sorted_import_modules(imports) {
    lines.push("    \{contract_json_string(module_name)}: {")
    for function in imports {
      if function.module_name.unwrap_or("") == module_name {
        if is_make_closure(function) {
          lines.push(
            "      \{contract_json_string(function.name)}: (fn, context) => makeMoonBitClosure(fn, context),",
          )
        } else {
          let stub = throwing_stub(function)
          lines.push("      \{stub[0]}")
          lines.push("      \{stub[1]}")
          lines.push("      \{stub[2]}")
        }
      }
    }
    lines.push("    },")
  }
  lines.push("  };")
  lines.push("}")
}

///|
fn render_typescript(
  abi : @model.HostAbi,
  abi_sha256 : String,
  settings : ContractSettings,
) -> String {
  let imports = @model.sort_abi_functions(abi.imports)
  let exports = @model.sort_abi_functions(abi.exports)
  let generic = settings.externref_generic.unwrap_or("TExtern")
  let lines : Array[String] = [
    "// Generated by MoonHostABI. Do not edit.",
    "// ABI SHA-256: \{abi_sha256}",
    "",
  ]
  append_host_import_type(lines, imports, generic)
  lines.push("")
  append_module_export_type(lines, exports, generic)
  if has_make_closure(imports) {
    lines.push("")
    append_make_closure_helper(lines)
  }
  lines.push("")
  append_host_import_factory(lines, imports, generic)
  lines.push("")
  lines.push("export async function instantiate<\{generic} = unknown>(")
  lines.push("  bytes: BufferSource,")
  lines.push("  imports: HostImports<\{generic}>,")
  lines.push("): Promise<ModuleExports<\{generic}>> {")
  lines.push("  const result = await WebAssembly.instantiate(bytes, imports);")
  lines.push(
    "  return result.instance.exports as unknown as ModuleExports<\{generic}>;",
  )
  lines.push("}")
  lines.join("\n") + "\n"
}

///|
pub fn generate_typescript_adapter(
  abi : @model.HostAbi,
  contract : String?,
) -> GenerationResult raise ContractError {
  let canonical_abi = @lockfile.canonicalize_host_abi(abi)
  let abi_sha256 = @lockfile.host_abi_sha256(canonical_abi)
  let settings = resolve_contract_settings(canonical_abi, abi_sha256, contract)
  let diagnostics = validate_generator_abi(canonical_abi)
  let normalized_contract = encode_contract(canonical_abi, abi_sha256, settings)
  let typescript = if diagnostics.is_empty() {
    render_typescript(canonical_abi, abi_sha256, settings)
  } else {
    ""
  }
  { typescript, contract: normalized_contract, abi_sha256, diagnostics }
}
