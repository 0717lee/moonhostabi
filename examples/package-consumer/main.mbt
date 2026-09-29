///|
fn join_bytes(parts : Array[Bytes]) -> Bytes {
  let output : Array[Byte] = []
  for part in parts {
    for byte in part {
      output.push(byte)
    }
  }
  Bytes::from_array(output)
}

///|
fn u32(value : Int) -> Bytes {
  let output : Array[Byte] = []
  let mut rest = value
  while rest >= 128 {
    output.push(((rest & 127) | 128).to_byte())
    rest = rest >> 7
  }
  output.push(rest.to_byte())
  Bytes::from_array(output)
}

///|
fn section(id : Int, payload : Bytes) -> Bytes {
  join_bytes([Bytes::from_array([id.to_byte()]), u32(payload.length()), payload])
}

///|
fn nested_artifact(depth : Int) -> Bytes {
  let parts = [b"\x00"] // No local declarations.
  for _ in 0..<depth {
    parts.push(b"\x02\x40")
  }
  parts.push(b"\x01") // A nop survives in the innermost block.
  for _ in 0..<depth {
    parts.push(b"\x0b")
  }
  parts.push(b"\x0b")
  let body = join_bytes(parts)
  join_bytes([
    b"\x00asm\x01\x00\x00\x00",
    section(1, b"\x01\x60\x00\x00"),
    section(3, b"\x01\x00"),
    section(10, join_bytes([b"\x01", u32(body.length()), body])),
  ])
}

///|
fn recursive_assertions() -> Unit raise {
  // An implicit singleton group containing a mutable nullable self-reference.
  let bytes = b"\x00asm\x01\x00\x00\x00\x01\x06\x01\x5f\x01\x63\x00\x01"
  let parsed = @wasm_adapter.parse_artifact_checked(bytes)
  assert_eq(parsed.types.length(), 1)
  match parsed.types[0].composite {
    Struct(struct_) => {
      assert_eq(struct_.fields.length(), 1)
      assert_true(struct_.fields[0].mutable)
      match struct_.fields[0].storage_type {
        Val(RefNullStruct(index)) => assert_eq(index, 0)
        _ => fail("singleton self-reference did not resolve to a struct")
      }
    }
    _ => fail("singleton recursive type was not a struct")
  }
}

///|
fn depth_assertions() -> Unit raise {
  let parsed = @wasm_adapter.parse_artifact_checked(nested_artifact(256))
  assert_eq(parsed.codes.length(), 1)
  let mut body = parsed.codes[0].body
  for _ in 0..<256 {
    assert_eq(body.length(), 1)
    body = match body[0] {
      Block(Empty, nested) => nested
      _ => fail("lost a nested block")
    }
  }
  assert_eq(body.length(), 1)
  assert_true(body[0] is Nop)
}

///|
fn error_assertions() -> Unit raise {
  let depth_error = try @wasm_adapter.parse_artifact_checked(nested_artifact(257)) catch {
    @wasm_adapter.ArtifactError::LimitExceeded(reason) => reason
    @wasm_adapter.ArtifactError::InvalidArtifact(_) => "wrong error class"
  } noraise {
    _ => "accepted"
  }
  assert_eq(depth_error, "expression depth")
  let malformed = try @wasm_adapter.parse_artifact_checked(b"\x00asm") catch {
    @wasm_adapter.ArtifactError::InvalidArtifact(_) => true
    @wasm_adapter.ArtifactError::LimitExceeded(_) => false
  } noraise {
    _ => false
  }
  assert_true(malformed)
}

///|
fn lock_verify_assertions() -> Unit raise {
  // Re-export an imported scalar function: a nonempty, observable public ABI.
  let bytes = join_bytes([
    b"\x00asm\x01\x00\x00\x00",
    section(1, b"\x01\x60\x01\x7f\x01\x7f"),
    section(2, b"\x01\x03env\x01f\x00\x00"),
    section(7, b"\x01\x01f\x00\x00"),
  ])
  let analysis = @projector.analyze_host_abi(
    @wasm_adapter.parse_artifact_checked(bytes),
    @projector.default_js_capability_policy(),
  )
  assert_true(analysis.diagnostics.is_empty())
  assert_eq(analysis.abi.imports.length(), 1)
  assert_eq(analysis.abi.exports.length(), 1)
  assert_eq(analysis.abi.exports[0].name, "f")
  assert_eq(analysis.abi.exports[0].params.length(), 1)
  assert_eq(analysis.abi.exports[0].params[0].stable_text(), "i32")
  let lock = @lockfile.create_lockfile(analysis.abi, bytes)
  let encoded = @lockfile.encode_lockfile(lock)
  let decoded = @lockfile.decode_lockfile(encoded)
  assert_eq(@lockfile.encode_lockfile(decoded), encoded)
  assert_eq(decoded.artifact_fingerprint(), @lockfile.sha256_hex(bytes))
  assert_eq(decoded.abi_fingerprint(), @lockfile.host_abi_sha256(analysis.abi))
  let baseline = @verification.decode_verification_baseline(encoded)
  let report = @verification.verify_artifact_checked(bytes, baseline, @verification.ContractNotProvided)
  assert_eq(report.outcome, @verification.VerificationCompatible)
  assert_eq(report.recommended_exit_code(), 0)
  assert_eq(report.provenance_artifact_match, Some(true))
  assert_eq(report.provenance_abi_match, Some(true))
  let breaking = @verification.verify_artifact_checked(
    b"\x00asm\x01\x00\x00\x00", baseline, @verification.ContractNotProvided,
  )
  assert_eq(breaking.outcome, @verification.VerificationBreaking)
  assert_eq(breaking.recommended_exit_code(), 2)
  assert_eq(breaking.provenance_artifact_match, Some(false))
  assert_eq(breaking.provenance_abi_match, Some(false))
}

///|
fn main raise {
  recursive_assertions()
  println("PACKAGE_CONSUMER_RECURSIVE=GO")
  depth_assertions()
  println("PACKAGE_CONSUMER_DEPTH_256=GO")
  error_assertions()
  println("PACKAGE_CONSUMER_OWNED_ERRORS=GO")
  lock_verify_assertions()
  println("PACKAGE_CONSUMER_LOCK_VERIFY=GO")
  println("PACKAGE_CONSUMER_SMOKE=GO")
}
