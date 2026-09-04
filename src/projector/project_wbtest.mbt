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

///|
test "MoonBit make_closure import is recorded as a feature" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.types.push(
    @wasm_types.SubType::func([FuncRef, ExternRef], [FuncRef]),
  )
  wasm_module.imports.push({
    mod_name: "moonbit:ffi",
    name: "make_closure",
    desc: @wasm_types.ImportDesc::Func(0),
  })

  let abi = project_host_abi(wasm_module)

  debug_inspect(abi.features, content="[\"moonbit.make_closure\"]")
}

///|
test "MoonBit make_closure feature requires a function import" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.imports.push({
    mod_name: "moonbit:ffi",
    name: "make_closure",
    desc: @wasm_types.ImportDesc::Global(@wasm_types.GlobalType::{
      value_type: I32,
      mutable: false,
    }),
  })

  let abi = project_host_abi(wasm_module)

  debug_inspect(abi.features, content="[]")
}

///|
test "MoonBit externref remains opaque and uses an explicit symbolic name" {
  let default_policy = default_js_capability_policy()
  let (unnamed, unnamed_diagnostic) = classify_js_value_type(
    @model.ExternRef,
    "imports[host.echo].params[0]",
    default_policy,
  )
  debug_inspect(unnamed, content="Opaque(\"unknown\")")
  assert_true(unnamed_diagnostic is None)

  let named_policy = JsCapabilityPolicy::{
    allow_typed_gc_refs: false,
    allow_v128: false,
    externref_symbol: Some("HostToken"),
  }
  let (named, named_diagnostic) = classify_js_value_type(
    @model.ExternRef,
    "imports[host.echo].params[0]",
    named_policy,
  )
  debug_inspect(named, content="Opaque(\"HostToken\")")
  assert_true(named_diagnostic is None)
}

///|
test "MoonBit typed GC refs and v128 fail JavaScript representation by default" {
  let policy = default_js_capability_policy()
  let (_, typed_ref_diagnostic) = classify_js_value_type(
    @model.TypedRef("type[4]", false),
    "imports[host.consume].params[0]",
    policy,
  )
  let (_, v128_diagnostic) = classify_js_value_type(
    @model.V128,
    "imports[host.consume].params[1]",
    policy,
  )
  guard typed_ref_diagnostic is Some(typed_ref_error) else {
    fail("expected typed GC ref diagnostic")
  }
  guard v128_diagnostic is Some(v128_error) else {
    fail("expected v128 diagnostic")
  }
  inspect(typed_ref_error.code, content="MHA_PROJECT_UNREPRESENTABLE")
  inspect(typed_ref_error.path, content="imports[host.consume].params[0]")
  inspect(v128_error.code, content="MHA_PROJECT_UNREPRESENTABLE")
  inspect(v128_error.path, content="imports[host.consume].params[1]")
}

///|
test "MoonBit analysis diagnoses unrepresentable public boundary values" {
  let wasm_module = @wasm_types.Module::Module()
  wasm_module.types.push(
    @wasm_types.SubType::simple(
      @wasm_types.CompositeType::Struct(@wasm_types.StructType::{ fields: [] }),
    ),
  )
  wasm_module.types.push(@wasm_types.SubType::func([RefStruct(0), V128], []))
  wasm_module.imports.push({
    mod_name: "host",
    name: "consume",
    desc: @wasm_types.ImportDesc::Func(1),
  })

  let analysis = analyze_host_abi(wasm_module, default_js_capability_policy())

  inspect(analysis.abi.imports.length(), content="1")
  inspect(analysis.diagnostics.length(), content="2")
  inspect(
    analysis.diagnostics[0].path,
    content="imports[host.consume].params[0]",
  )
  inspect(
    analysis.diagnostics[1].path,
    content="imports[host.consume].params[1]",
  )
}

///|
test "MoonBit capability policy can explicitly allow typed refs and v128" {
  let policy = JsCapabilityPolicy::{
    allow_typed_gc_refs: true,
    allow_v128: true,
    externref_symbol: None,
  }
  let (typed_ref, typed_ref_diagnostic) = classify_js_value_type(
    @model.TypedRef("type[4]", true),
    "exports.value.results[0]",
    policy,
  )
  let (v128, v128_diagnostic) = classify_js_value_type(
    @model.V128,
    "exports.vector.results[0]",
    policy,
  )
  debug_inspect(typed_ref, content="Opaque(\"type[4]\")")
  debug_inspect(v128, content="Opaque(\"v128\")")
  assert_true(typed_ref_diagnostic is None)
  assert_true(v128_diagnostic is None)
}
