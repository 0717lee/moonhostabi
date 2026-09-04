///|
test "scalar imports and exports use the Wasm function index space" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.types.push(@wasm_types.SubType::func([], [F64]))
  wasm_module.types.push(@wasm_types.SubType::func([I64], [I64]))
  wasm_module.types.push(@wasm_types.SubType::func([I32, I32], [I32]))
  wasm_module.imports.push({
    mod_name: "env",
    name: "now",
    desc: @wasm_types.ImportDesc::Func(0),
  })
  wasm_module.funcs.push(2)
  wasm_module.funcs.push(1)
  wasm_module.exports.push({
    name: "add",
    desc: @wasm_types.ExportDesc::Func(1),
  })

  let abi = project_host_abi(wasm_module)

  inspect(abi.schema_version, content="1")
  inspect(abi.imports.length(), content="1")
  inspect(abi.exports.length(), content="1")
  inspect(abi.types.length(), content="0")
  inspect(abi.features.length(), content="0")
  inspect(abi.imports[0].stable_text(), content="func import env.now()->(f64)")
  inspect(
    abi.exports[0].stable_text(),
    content="func export add(i32,i32)->(i32)",
  )
}

///|
test "value types map without erasing unsupported variants" {
  inspect(map_value_type(I32, [0, 1]).stable_text(), content="i32")
  inspect(map_value_type(I64, [0, 1]).stable_text(), content="i64")
  inspect(map_value_type(F32, [0, 1]).stable_text(), content="f32")
  inspect(map_value_type(F64, [0, 1]).stable_text(), content="f64")
  inspect(map_value_type(V128, [0, 1]).stable_text(), content="v128")
  inspect(map_value_type(ExternRef, [0, 1]).stable_text(), content="externref")
  inspect(map_value_type(RefExtern, [0, 1]).stable_text(), content="externref")
  inspect(map_value_type(FuncRef, [0, 1]).stable_text(), content="funcref")
  inspect(
    map_value_type(RefStruct(1), [0, 7]).stable_text(),
    content="ref type[7]",
  )
  inspect(
    map_value_type(RefNullArray(1), [0, 7]).stable_text(),
    content="ref null type[7]",
  )
  inspect(
    map_value_type(AnyRef, [0, 1]).stable_text(),
    content="unknown(value_type.anyref)",
  )
}
