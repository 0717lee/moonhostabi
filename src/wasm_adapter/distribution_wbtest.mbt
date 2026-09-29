///|
test "bundled parser matches pristine upstream on the shared fixture subset" {
  for name in test_fixture_names() {
    // This compiler-produced fixture needs the singleton fix absent from 0.14.0.
    // Its expected self-reference is asserted explicitly in the test below.
    if name == "recursive" {
      continue
    }
    let bytes = @fs.read_file_to_bytes("fixtures/artifacts/" + name + ".wasm")
    assert_eq(
      parse_artifact_checked(bytes).to_string(),
      @upstream_parser.parse_module(bytes).to_string(),
    )
  }
}

///|
test "both parser entrypoints expose the owned malformed artifact error" {
  let legacy_reason = try parse_artifact(b"\x00asm") catch {
    InvalidArtifact(reason) => reason
    LimitExceeded(reason) => "unexpected limit: " + reason
  } noraise {
    _ => "accepted"
  }
  let checked_reason = try parse_artifact_checked(b"\x00asm") catch {
    InvalidArtifact(reason) => reason
    LimitExceeded(reason) => "unexpected limit: " + reason
  } noraise {
    _ => "accepted"
  }
  assert_eq(legacy_reason, "unexpected end of input")
  assert_eq(checked_reason, legacy_reason)
}

///|
test "both bundled parser entrypoints resolve implicit singleton self references" {
  let bytes = b"\x00asm\x01\x00\x00\x00\x01\x06\x01\x5f\x01\x63\x00\x00"
  for module_ in [parse_artifact(bytes), parse_artifact_checked(bytes)] {
    assert_eq(module_.types.length(), 1)
    guard module_.types[0].composite is Struct(value) else {
      fail("expected the singleton struct")
    }
    assert_eq(value.fields, [
      { storage_type: Val(RefNullStruct(0)), mutable: false, },
    ])
  }
}
