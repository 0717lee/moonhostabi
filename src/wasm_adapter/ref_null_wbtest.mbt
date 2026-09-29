///|
fn ref_null_module(heap_type : Bytes, extra_types : Array[Bytes]) -> Bytes {
  let type_parts = [test_u32(extra_types.length() + 1), b"\x60\x00\x00"]
  for type_def in extra_types {
    type_parts.push(type_def)
  }
  let body = test_join([b"\x00\xd0", heap_type, b"\x0b"])
  test_module([
    test_section(1, test_join(type_parts)),
    test_section(3, b"\x01\x00"),
    test_section(10, test_join([b"\x01", test_u32(body.length()), body])),
  ])
}

///|
fn ref_null_error(bytes : Bytes) -> String {
  try parse_artifact(bytes) catch {
    InvalidArtifact(reason) => reason
    LimitExceeded(reason) => "unexpected limit: " + reason
  } noraise {
    _ => "accepted"
  }
}

///|
test "ref.null resolves every abstract heap type" {
  // Signed LEB128 heap codes -16 through -23, then -15 through -12.
  let cases : Array[(Bytes, @wasm_types.ValueType)] = [
    (b"\x70", FuncRef),
    (b"\x6f", ExternRef),
    (b"\x6e", AnyRef),
    (b"\x6d", RefNullEq),
    (b"\x6c", RefNullI31),
    (b"\x6b", StructRef),
    (b"\x6a", ArrayRef),
    (b"\x69", ExnRef),
    (b"\x71", NullRef),
    (b"\x72", NullExternRef),
    (b"\x73", NullFuncRef),
    (b"\x74", NullExnRef),
  ]
  for case in cases {
    let (heap_type, value_type) = case
    let parsed = parse_artifact(ref_null_module(heap_type, []))
    assert_eq(parsed.codes[0].body, [RefNull(value_type)])
  }
}

///|
test "ref.null resolves typed function struct and array heap types" {
  let function = parse_artifact(ref_null_module(test_u32(1), [b"\x60\x00\x00"]))
  assert_eq(function.codes[0].body, [RefNull(RefNullFuncTyped(1))])

  let structure = parse_artifact(ref_null_module(test_u32(1), [b"\x5f\x00"]))
  assert_eq(structure.codes[0].body, [RefNull(RefNullStruct(1))])

  let array = parse_artifact(ref_null_module(test_u32(1), [b"\x5e\x7f\x00"]))
  assert_eq(array.codes[0].body, [RefNull(RefNullArray(1))])
}

///|
test "ref.null rejects invalid negative heap types and out-of-range indices" {
  // Invalid codes immediately outside the supported abstract range.
  for heap_type in [b"\x68", b"\x75"] {
    assert_eq(
      ref_null_error(ref_null_module(heap_type, [])),
      "invalid heap type",
    )
  }
  assert_eq(
    ref_null_error(ref_null_module(test_u32(2), [b"\x60\x00\x00"])),
    "invalid heap type",
  )
}
