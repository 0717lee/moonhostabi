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

///|
test "function index lookup covers imported defined and invalid indices" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.types.push(@wasm_types.SubType::func([], [F64]))
  wasm_module.types.push(@wasm_types.SubType::func([], [I64]))
  wasm_module.types.push(@wasm_types.SubType::func([], [I32]))
  wasm_module.imports.push({
    mod_name: "clock",
    name: "now",
    desc: @wasm_types.ImportDesc::Func(0),
  })
  wasm_module.imports.push({
    mod_name: "clock",
    name: "ticks",
    desc: @wasm_types.ImportDesc::Func(1),
  })
  wasm_module.funcs.push(2)

  guard function_type_at_index(wasm_module, 0) is Some(first_import) else {
    fail("expected first imported function type")
  }
  guard function_type_at_index(wasm_module, 1) is Some(second_import) else {
    fail("expected second imported function type")
  }
  guard function_type_at_index(wasm_module, 2) is Some(defined) else {
    fail("expected defined function type")
  }
  debug_inspect(first_import.results, content="[F64]")
  debug_inspect(second_import.results, content="[I64]")
  debug_inspect(defined.results, content="[I32]")
  assert_true(function_type_at_index(wasm_module, -1) is None)
  assert_true(function_type_at_index(wasm_module, 3) is None)
}

///|
test "an exported imported function keeps its imported signature" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.types.push(@wasm_types.SubType::func([], [F64]))
  wasm_module.imports.push({
    mod_name: "clock",
    name: "now",
    desc: @wasm_types.ImportDesc::Func(0),
  })
  wasm_module.exports.push({
    name: "public_now",
    desc: @wasm_types.ExportDesc::Func(0),
  })

  let abi = project_host_abi(wasm_module)
  inspect(
    abi.exports[0].stable_text(),
    content="func export public_now()->(f64)",
  )
}

///|
test "all typed refs preserve canonical identity and nullability" {
  let canonical = [9]
  inspect(
    map_value_type(RefFuncTyped(0), canonical).stable_text(),
    content="ref type[9]",
  )
  inspect(
    map_value_type(RefNullFuncTyped(0), canonical).stable_text(),
    content="ref null type[9]",
  )
  inspect(
    map_value_type(RefStruct(0), canonical).stable_text(),
    content="ref type[9]",
  )
  inspect(
    map_value_type(RefNullStruct(0), canonical).stable_text(),
    content="ref null type[9]",
  )
  inspect(
    map_value_type(RefArray(0), canonical).stable_text(),
    content="ref type[9]",
  )
  inspect(
    map_value_type(RefNullArray(0), canonical).stable_text(),
    content="ref null type[9]",
  )
  inspect(
    map_value_type(RefStruct(-1), canonical).stable_text(),
    content="unknown(types[-1])",
  )
  inspect(
    map_value_type(RefNullArray(1), canonical).stable_text(),
    content="unknown(types[1])",
  )
}
