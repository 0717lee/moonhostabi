///|
test "ABI functions sort by module, name, and function kind" {
  let imported = AbiFunction::{
    module_name: Some("z_host"),
    name: "echo",
    params: [ExternRef],
    results: [ExternRef],
  }
  let exported = AbiFunction::{
    module_name: None,
    name: "add",
    params: [I32, I32],
    results: [I32],
  }
  let sorted = sort_abi_functions([imported, exported])
  inspect(sorted[0].stable_text(), content="func export add(i32,i32)->(i32)")
  inspect(
    sorted[1].stable_text(),
    content="func import z_host.echo(externref)->(externref)",
  )
}

///|
test "unknown ABI values retain their Wasm type path" {
  let value = AbiValueType::Unknown("types[7].struct.fields[1]")
  inspect(value.stable_text(), content="unknown(types[7].struct.fields[1])")
}

///|
test "diagnostics preserve stable machine fields" {
  let diagnostic = Diagnostic::{
    code: MHA_PROJECT_UNREPRESENTABLE,
    severity: Error,
    path: "exports.render.params[0]",
    message: "typed GC ref is not JavaScript-representable",
    byte_offset: Some(42),
  }
  inspect(diagnostic.code, content="MHA_PROJECT_UNREPRESENTABLE")
  debug_inspect(diagnostic.severity, content="Error")
  inspect(diagnostic.path, content="exports.render.params[0]")
  debug_inspect(diagnostic.byte_offset, content="Some(42)")
}

///|
test "all initial diagnostic codes are stable" {
  inspect(MHA_PARSE_MALFORMED, content="MHA_PARSE_MALFORMED")
  inspect(MHA_PARSE_UNSUPPORTED, content="MHA_PARSE_UNSUPPORTED")
  inspect(MHA_PROJECT_UNREPRESENTABLE, content="MHA_PROJECT_UNREPRESENTABLE")
  inspect(MHA_PROJECT_UNSUPPORTED_ITEM, content="MHA_PROJECT_UNSUPPORTED_ITEM")
  inspect(MHA_IMPORT_ADDED, content="MHA_IMPORT_ADDED")
  inspect(MHA_EXPORT_REMOVED, content="MHA_EXPORT_REMOVED")
  inspect(MHA_SIGNATURE_CHANGED, content="MHA_SIGNATURE_CHANGED")
  inspect(MHA_GC_TYPE_CHANGED, content="MHA_GC_TYPE_CHANGED")
  inspect(MHA_ADAPTER_MISMATCH, content="MHA_ADAPTER_MISMATCH")
  inspect(MHA_RUNTIME_FAILURE, content="MHA_RUNTIME_FAILURE")
}
