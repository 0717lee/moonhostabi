///|
fn type_policy_artifact(count : Int, boundary : String) -> Bytes {
  let types = [test_u32(count)]
  for index in 0..<count {
    types.push(
      if boundary == "typed" && index == 0 {
        b"\x5f\x00"
      } else if boundary == "typed" && index == 1 {
        b"\x60\x01\x63\x00\x00"
      } else if boundary == "super" && index == 0 {
        b"\x50\x00\x60\x00\x00"
      } else if boundary == "super" && index == 1 {
        b"\x50\x01\x00\x60\x00\x00"
      } else if index == 0 || index % 3 == 0 {
        b"\x60\x00\x00"
      } else if index % 3 == 1 {
        b"\x5f\x00"
      } else {
        b"\x5e\x7f\x00"
      },
    )
  }
  test_module([
    test_section(1, test_join(types)),
    test_section(
      2,
      test_join([
        b"\x01\x03env\x01f\x00",
        test_u32(if boundary == "scalar" { 0 } else { 1 }),
      ]),
    ),
  ])
}

///|
test "scalar boundary permits bounded private types beyond canonicalization budget" {
  for count in [1644, 2048] {
    let bytes = type_policy_artifact(count, "scalar")
    let parsed = parse_artifact_checked(bytes)
    assert_eq(parsed.types.length(), count)
    assert_false(host_abi_needs_type_canonicalization(parsed))
    assert_eq(parsed.to_string(), parse_artifact(bytes).to_string())
  }
  let rejected = try
    parse_artifact_checked(type_policy_artifact(2049, "scalar"))
  catch {
    LimitExceeded(reason) => reason == "types"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "typed public boundary and scalar supertypes retain canonicalization budget" {
  for boundary in ["typed", "super"] {
    let parsed = parse_artifact_checked(type_policy_artifact(1024, boundary))
    assert_eq(parsed.types.length(), 1024)
    assert_true(host_abi_needs_type_canonicalization(parsed))
    let rejected = try
      parse_artifact_checked(type_policy_artifact(1025, boundary))
    catch {
      LimitExceeded(reason) => reason == "canonicalization types"
      InvalidArtifact(_) => false
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "canonicalization predicate covers every indexed reference and scalar projection" {
  let scalar = @wasm_types.Module::empty()
  scalar.types.push(
    @wasm_types.SubType::func(
      [
        I32,
        I64,
        F32,
        F64,
        V128,
        ExternRef,
        RefExtern,
        FuncRef,
        RefFunc,
        AnyRef,
        ExnRef,
        StructRef,
        ArrayRef,
        RefAny,
        RefEq,
        RefNullEq,
        RefI31,
        RefNullI31,
        RefStructAbs,
        RefArrayAbs,
        RefNone,
        NullRef,
        NullFuncRef,
        NullExnRef,
        NullExternRef,
      ],
      [],
    ),
  )
  scalar.imports.push({ mod_name: "env", name: "f", desc: Func(0), })
  assert_false(host_abi_needs_type_canonicalization(scalar))
  let indexed_refs : Array[@wasm_types.ValueType] = [
    RefFuncTyped(99),
    RefNullFuncTyped(99),
    RefStruct(99),
    RefNullStruct(99),
    RefArray(99),
    RefNullArray(99),
  ]
  for value_type in indexed_refs {
    for as_result in [false, true] {
      let typed = @wasm_types.Module::empty()
      typed.types.push(
        @wasm_types.SubType::func(
          if as_result {
            []
          } else {
            [value_type]
          },
          if as_result {
            [value_type]
          } else {
            []
          },
        ),
      )
      typed.imports.push({ mod_name: "env", name: "f", desc: Func(0), })
      assert_true(host_abi_needs_type_canonicalization(typed))
    }
  }
}

///|
test "canonicalization predicate follows exported function index space only" {
  let module_ = @wasm_types.Module::empty()
  module_.types.push(@wasm_types.SubType::func([], []))
  module_.types.push(@wasm_types.SubType::func([RefNullStruct(2)], []))
  module_.types.push(@wasm_types.SubType::simple(Struct({ fields: [], })))
  module_.imports.push({ mod_name: "env", name: "tag", desc: Tag(1), })
  module_.imports.push({ mod_name: "env", name: "f", desc: Func(0), })
  module_.funcs.push(1)
  // Private typed function and a tag do not affect the function host ABI.
  assert_false(host_abi_needs_type_canonicalization(module_))
  module_.exports.push({ name: "reexported", desc: Func(0), })
  assert_false(host_abi_needs_type_canonicalization(module_))
  module_.exports.push({ name: "defined", desc: Func(1), })
  assert_true(host_abi_needs_type_canonicalization(module_))
}

///|
test "canonicalization predicate conservatively preserves invalid public models" {
  for type_index in [-1, 0, 1] {
    let module_ = @wasm_types.Module::empty()
    module_.types.push(@wasm_types.SubType::simple(Struct({ fields: [], })))
    module_.imports.push({
      mod_name: "env",
      name: "invalid",
      desc: Func(type_index),
    })
    assert_true(host_abi_needs_type_canonicalization(module_))
  }
  for function_index in [-1, 0, 1] {
    let module_ = @wasm_types.Module::empty()
    module_.funcs.push(42)
    module_.exports.push({ name: "invalid", desc: Func(function_index), })
    assert_true(host_abi_needs_type_canonicalization(module_))
  }
}
