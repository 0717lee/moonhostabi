///|
test "checked parser enforces code body size before bundled parse" {
  let bytes = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x04\x01\x01\x00\x0b"
  // wasm_core 0.14.0 ignores code_size and accepts this one-byte body.
  let _ = parse_artifact(bytes)
  let rejected = try parse_artifact_checked(bytes) catch {
    InvalidArtifact(_) => true
    LimitExceeded(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "signature budget leaves invalid indices to projection validation" {
  let parsed = @wasm_types.Module::empty()
  parsed.imports.push({ mod_name: "env", name: "invalid", desc: Func(-1), })
  parsed.funcs.push(42)
  parsed.exports.push({ name: "negative", desc: Func(-1), })
  parsed.exports.push({ name: "missing", desc: Func(99), })
  parsed.exports.push({ name: "missing_type", desc: Func(1), })
  parsed.imports.push({ mod_name: "env", name: "invalid_tag", desc: Tag(-1), })
  parsed.tags.push({ type_idx: 42, })
  parsed.exports.push({ name: "negative_tag", desc: Tag(-1), })
  parsed.exports.push({ name: "missing_tag", desc: Tag(99), })
  parsed.exports.push({ name: "missing_tag_type", desc: Tag(1), })
  check_public_signature_budget(parsed, 0)
}

///|
fn test_join(parts : Array[Bytes]) -> Bytes {
  let out : Array[Byte] = []
  for part in parts {
    for byte in part {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
fn test_u32(value : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut remaining = value
  while remaining >= 128 {
    out.push(((remaining & 127) | 128).to_byte())
    remaining = remaining >> 7
  }
  out.push(remaining.to_byte())
  Bytes::from_array(out)
}

///|
fn test_section(id : Int, payload : Bytes) -> Bytes {
  test_join([
    Bytes::from_array([id.to_byte()]),
    test_u32(payload.length()),
    payload,
  ])
}

///|
fn test_module(sections : Array[Bytes]) -> Bytes {
  test_join([b"\x00asm\x01\x00\x00\x00", test_join(sections)])
}

///|
fn test_code(bodies : Array[Bytes], data_count? : Bool = false) -> Bytes {
  let functions = [test_u32(bodies.length())]
  let codes = [test_u32(bodies.length())]
  for body in bodies {
    functions.push(b"\x00")
    codes.push(test_u32(body.length()))
    codes.push(body)
  }
  let sections = [
    test_section(1, b"\x01\x60\x00\x00"),
    test_section(3, test_join(functions)),
  ]
  if data_count {
    sections.push(test_section(12, b"\x00"))
  }
  sections.push(test_section(10, test_join(codes)))
  test_module(sections)
}

///|
fn test_nested(depth : Int) -> Bytes {
  let parts : Array[Bytes] = []
  for _ in 0..<depth {
    parts.push(b"\x02\x40")
  }
  for _ in 0..<=depth {
    parts.push(b"\x0b")
  }
  test_join(parts)
}

///|
fn test_limit(
  bytes : Bytes,
  limits : PreflightLimits,
  expected : String,
) -> Unit raise {
  let reason = try preflight_artifact(bytes, limits) catch {
    LimitExceeded(reason) => reason
    InvalidArtifact(reason) => "invalid: " + reason
  } noraise {
    _ => "accepted"
  }
  assert_eq(reason, expected)
}

///|
fn test_invalid(bytes : Bytes) -> Unit raise {
  let rejected = try parse_artifact_checked(bytes) catch {
    InvalidArtifact(_) => true
    LimitExceeded(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "preflight budget boundaries include actual types and all declared items" {
  let empty = test_module([])
  preflight_artifact(empty, preflight_limits(bytes=8))
  test_limit(empty, preflight_limits(bytes=7), "artifact bytes")

  // One rec group contains three actual types.
  let rec_types = test_module([
    test_section(1, b"\x01\x4e\x03\x60\x00\x00\x5f\x00\x5e\x7f\x00"),
  ])
  preflight_artifact(rec_types, preflight_limits(types=3))
  test_limit(rec_types, preflight_limits(types=2), "types")
  let parsed = parse_artifact_checked(rec_types)
  assert_eq(parsed.types.length(), 3)
  assert_eq(parsed.type_rec_groups, [0, 0, 0])

  // Section + rec group + type + 2 params + 1 result = 6 items.
  let signature = test_module([test_section(1, b"\x01\x60\x02\x7f\x7e\x01\x7f")])
  preflight_artifact(signature, preflight_limits(items=6))
  test_limit(signature, preflight_limits(items=5), "declared items")
  // Two individual sections must share the same budget.
  let globals = test_module([
    test_section(4, b"\x01\x70\x00\x00"),
    test_section(6, b"\x01\x7f\x00\x0b"),
  ])
  preflight_artifact(globals, preflight_limits(items=4))
  test_limit(globals, preflight_limits(items=3), "declared items")
}

///|
test "compressed locals are checked before expansion and accumulate across functions" {
  let one = test_code([b"\x01\x05\x7f\x0b"])
  preflight_artifact(one, preflight_limits(function_locals=5))
  test_limit(one, preflight_limits(function_locals=4), "function locals")
  let aggregate = test_code([b"\x01\x02\x7f\x0b", b"\x01\x02\x7f\x0b"])
  preflight_artifact(aggregate, preflight_limits(locals=4))
  test_limit(aggregate, preflight_limits(locals=3), "module locals")
  // A tiny input can claim 2^32 - 1 locals. Never send it to the unbounded parser.
  test_limit(
    test_code([b"\x01\xff\xff\xff\xff\x0f\x7f\x0b"]),
    preflight_limits(),
    "function locals",
  )
}

///|
test "all initializer and code expressions share iterative depth checks" {
  let expr = test_nested(3)
  let cases = [
    test_code([test_join([b"\x00", expr])]),
    test_module([
      test_section(4, test_join([b"\x01\x40\x00\x70\x00\x00", expr])),
    ]),
    test_module([test_section(6, test_join([b"\x01\x7f\x00", expr]))]),
    test_module([test_section(9, test_join([b"\x01\x00", expr, b"\x00"]))]),
    test_module([test_section(9, test_join([b"\x01\x05\x70\x01", expr]))]),
    test_module([test_section(11, test_join([b"\x01\x00", expr, b"\x00"]))]),
  ]
  for bytes in cases {
    preflight_artifact(bytes, preflight_limits(depth=3))
    test_limit(bytes, preflight_limits(depth=2), "expression depth")
  }
  // Verify the production boundary without entering the AST parser.
  preflight_artifact(
    test_code([test_join([b"\x00", test_nested(256)])]),
    preflight_limits(),
  )
  test_limit(
    test_code([test_join([b"\x00", test_nested(257)])]),
    preflight_limits(),
    "expression depth",
  )
}

///|
test "instruction and immediate-vector budgets are module wide" {
  // Two global expressions each contain nop + end.
  let globals = test_module([
    test_section(6, b"\x02\x7f\x00\x01\x0b\x7f\x00\x01\x0b"),
  ])
  preflight_artifact(globals, preflight_limits(instructions=4))
  test_limit(globals, preflight_limits(instructions=3), "instructions")
  let functions = test_code([b"\x00\x01\x0b", b"\x00\x01\x0b"])
  preflight_artifact(functions, preflight_limits(instructions=4))
  test_limit(functions, preflight_limits(instructions=3), "instructions")
  // Base 7 items + two br_table labels.
  let branches = test_code([b"\x00\x0e\x02\x00\x00\x00\x0b"])
  preflight_artifact(branches, preflight_limits(items=9))
  test_limit(branches, preflight_limits(items=8), "declared items")
  // Base 7 items + two catch handlers.
  let catches = test_code([b"\x00\x1f\x40\x02\x02\x00\x03\x00\x0b\x0b"])
  preflight_artifact(catches, preflight_limits(items=9))
  test_limit(catches, preflight_limits(items=8), "declared items")
}

///|
test "malformed LEB and section body crossings fail closed" {
  for
    suffix in [
      b"\x01\x80", // truncated section length
       b"\x01\x80\x80\x80\x80\x10", // u32 overflow
       b"\x01\x80\x80\x80\x80\x80\x00", // too many bytes
       b"\x01\x02\x01\x60\x00\x00", // type crosses section end
       b"\x00\x01\x02\x61\x62", // custom name crosses section end
       b"\x06\x03\x01\x7f\x00\x0b", // global end is outside section
       b"\x01\xff\xff\xff\xff\x0f", // unsigned huge section
       b"\x0e\x00", // unknown section
       b"\x01\x01\x00\x01\x01\x00", // duplicate section
       b"\x03\x02\x01\x00", // missing code section
       b"\x0c\x01\x01", // data count mismatch
    ] {
    test_invalid(test_module([suffix]))
  }
  for
    body in [
      b"\x00", // missing end
       b"\x00\x0b\x01", // trailing byte after end
       b"\x00\x41\x80\x80\x80\x80\x08\x0b", // signed i32 overflow
       b"\x00\x42\x80\x80\x80\x80\x80\x80\x80\x80\x80\x01\x0b", // signed i64 overflow
       b"\x00\x43\x00\x00\x0b", // short f32
       b"\x00\x05\x0b", // else outside if
       b"\x00\x04\x40\x05\x05\x0b\x0b", // repeated else
       b"\x00\x06\x0b", // unsupported opcode
       b"\x00\xfd\x9a\x01\x0b", // reserved SIMD opcode 154
       b"\x00\xfe\x04\x00\x00\x0b", // unknown atomic opcode
       b"\x00\xfc\x08\x00\x00\x0b", // memory.init needs data count
       b"\x00\x28\x80\x00\x0b", // malformed memarg
       b"\x00\xfd\x0c\x00\x0b", // short v128.const
    ] {
    test_invalid(test_code([body]))
  }
  test_invalid(
    test_module([
      test_section(1, b"\x01\x60\x00\x00"),
      test_section(3, b"\x02\x00\x00"),
      // First body cannot steal the second body's end opcode.
      test_section(10, b"\x02\x01\x00\x02\x00\x0b"),
    ]),
  )
}

///|
test "checked errors preserve upstream diagnostics after structural preflight" {
  // A bounded UTF-8 string is checked by upstream after the allocation guard.
  let bytes = test_module([test_section(0, b"\x01\xff")])
  preflight_artifact(bytes, preflight_limits())
  let message = try parse_artifact_checked(bytes) catch {
    InvalidArtifact(reason) => reason
    LimitExceeded(reason) => "limit: " + reason
  } noraise {
    _ => "accepted"
  }
  assert_eq(message, "malformed UTF-8 encoding")
}

///|
fn test_same(bytes : Bytes) -> Unit raise {
  // This checks preflight transparency, not an independent parser oracle.
  assert_eq(
    parse_artifact_checked(bytes).to_string(),
    parse_artifact(bytes).to_string(),
  )
}

///|
test "scalar control memory and prefixed immediate layouts preserve parsing" {
  for
    opcode in [
      0x08, 0x0c, 0x0d, 0x10, 0x12, 0x14, 0x15, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25,
      0x26, 0x3f, 0x40, 0xd2, 0xd5, 0xd6,
    ] {
    test_same(test_code([test_join([b"\x00", test_u32(opcode), b"\x00\x0b"])]))
  }
  for
    body in [
      b"\x00\x04\x40\x01\x05\x01\x0b\x0b", // if/else
       b"\x00\x02\x63\x00\x03\x00\x0b\x0b\x0b", // ref block and indexed loop
       b"\x00\x1f\x40\x04\x00\x00\x00\x01\x00\x00\x02\x00\x03\x00\x0b\x0b", b"\x00\x0e\x02\x00\x00\x00\x0b", // br_table
       b"\x00\x11\x00\x00\x13\x00\x00\x0b", // indirect calls
       b"\x00\x41\x80\x80\x80\x80\x78\x0b", // i32 minimum
       b"\x00\x42\x80\x80\x80\x80\x80\x80\x80\x80\x80\x7f\x0b", // i64 minimum
       b"\x00\x43\x00\x00\x00\x00\x44\x00\x00\x00\x00\x00\x00\x00\x00\x0b", b"\x00\x28\x40\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01\x0b", // u64 max offset
       b"\x00\xd0\x70\x0b",
    ] {
    test_same(test_code([body]))
  }
  for opcode in 0x28..<=0x3e {
    test_same(test_code([Bytes::from_array([0, opcode.to_byte(), 0, 0, 0x0b])]))
  }
  for opcode in 0x45..<=0xc4 {
    test_same(test_code([Bytes::from_array([0, opcode.to_byte(), 0x0b])]))
  }
  for opcode in 0..<=30 {
    let immediate = match opcode {
      0 | 1 | 6 | 7 | 11 | 12 | 13 | 14 | 16 => b"\x00"
      2 | 3 | 4 | 5 | 8 | 9 | 10 | 17 | 18 | 19 => b"\x00\x00"
      20 | 21 | 22 | 23 => b"\x70"
      24 | 25 => b"\x00\x70\x70"
      _ => b""
    }
    test_same(
      test_code([test_join([b"\x00\xfb", test_u32(opcode), immediate, b"\x0b"])]),
    )
  }
  for
    opcode in [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 21, 22,
    ] {
    let immediate = match opcode {
      8 | 10 | 12 | 14 => b"\x00\x00"
      9 | 11 | 13 | 15 | 16 | 17 => b"\x00"
      _ => b""
    }
    test_same(
      test_code(
        [test_join([b"\x00\xfc", test_u32(opcode), immediate, b"\x0b"])],
        data_count=true,
      ),
    )
  }
}

///|
test "supported SIMD and atomic immediate layouts preserve parsing" {
  let reserved = [
    154, 162, 165, 166, 175, 176, 178, 179, 180, 187, 194, 197, 198, 207, 208, 210,
    211, 212, 226, 238,
  ]
  for opcode in 0..<=275 {
    if reserved.contains(opcode) {
      continue
    }
    let immediate = if opcode <= 11 || opcode == 92 || opcode == 93 {
      b"\x00\x00"
    } else if opcode == 12 || opcode == 13 {
      b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    } else if opcode >= 21 && opcode <= 34 {
      b"\x00"
    } else if opcode >= 84 && opcode <= 91 {
      b"\x00\x00\x00"
    } else {
      b""
    }
    test_same(
      test_code([test_join([b"\x00\xfd", test_u32(opcode), immediate, b"\x0b"])]),
    )
  }
  for opcode in 0..<=0x4e {
    if opcode > 3 && opcode < 0x10 {
      continue
    }
    let immediate = if opcode == 3 { b"\x00" } else { b"\x00\x00" }
    test_same(
      test_code([test_join([b"\x00\xfe", test_u32(opcode), immediate, b"\x0b"])]),
    )
  }
}

///|
test "limits flags noncanonical LEB and all element encodings preserve parsing" {
  for flags in [0, 1, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15] {
    let parts = [b"\x01", test_u32(flags), b"\x00"]
    if (flags & 1) != 0 {
      parts.push(b"\x01")
    }
    if (flags & 8) != 0 {
      parts.push(b"\x10")
    }
    test_same(test_module([test_section(5, test_join(parts))]))
  }
  for flags in [0, 1, 4, 5] {
    let parts = [b"\x01\x70", test_u32(flags), b"\x00"]
    if (flags & 1) != 0 {
      parts.push(b"\x01")
    }
    test_same(test_module([test_section(4, test_join(parts))]))
  }
  for flags in 0..<=7 {
    let parts = [b"\x01", test_u32(flags)]
    if (flags & 1) == 0 {
      if (flags & 2) != 0 {
        parts.push(b"\x00")
      }
      parts.push(b"\x41\x00\x0b")
    }
    if flags >= 1 && flags <= 3 {
      parts.push(b"\x00")
    }
    if flags >= 5 {
      parts.push(b"\x70")
    }
    parts.push(b"\x01")
    parts.push(if (flags & 4) != 0 { b"\xd0\x70\x0b" } else { b"\x00" })
    test_same(test_module([test_section(9, test_join(parts))]))
  }
  test_same(test_module([b"\x00\x81\x80\x80\x80\x00\x00"]))
}

///|
fn test_fixture_names() -> Array[String] {
  [
    "breaking_v1", "breaking_v2", "externref", "rec-a", "rec-reindexed", "recursive",
    "resources-changed", "resources-escaped", "resources-global-type-changed", "resources-imports-start-changed",
    "resources-imports", "resources-reindexed", "resources-table-type-changed", "resources-tag-signature-changed",
    "resources", "scalar",
  ]
}

///|
test "preflight preserves the bundled parser representation for all 16 artifacts" {
  for name in test_fixture_names() {
    let bytes = @fs.read_file_to_bytes("fixtures/artifacts/" + name + ".wasm")
    assert_eq(
      parse_artifact_checked(bytes).to_string(),
      parse_artifact(bytes).to_string(),
    )
  }
}

///|
fn test_bounded_outcome(bytes : Bytes) -> Unit raise {
  let limits = preflight_limits(
    types=32,
    items=256,
    locals=64,
    function_locals=32,
    instructions=512,
    depth=16,
  )
  preflight_artifact(bytes, limits) catch {
    _ => return
  }
  try parse_artifact_checked(bytes) catch {
    _ => return
  } noraise {
    parsed => assert_eq(parsed.to_string(), parse_artifact(bytes).to_string())
  }
}

///|
test "bounded mutation corpus terminates with errors or unchanged ASTs" {
  let mut cases = 0
  for name in test_fixture_names() {
    let original = @fs.read_file_to_bytes(
      "fixtures/artifacts/" + name + ".wasm",
    )
    // Deterministic single-byte mutations include LEB, counts, and opcode bytes.
    for offset = 8; offset < original.length(); offset = offset + 7 {
      for replacement in [0, 0x0b, 0x40, 0x7f, 0x80, 0xff] {
        let changed = original.to_array()
        changed[offset] = replacement.to_byte()
        let bytes = Bytes::from_array(changed)
        test_bounded_outcome(bytes)
        cases += 1
      }
    }
  }
  assert_true(cases > 2000)
}

///|
test "public signature expansion counts repeated exports and imported functions" {
  let parsed = @wasm_types.Module::empty()
  parsed.types.push(@wasm_types.SubType::func([I32, I64], [I32]))
  parsed.types.push(@wasm_types.SubType::func([I32], []))
  parsed.imports.push({ mod_name: "env", name: "f", desc: Func(0), })
  parsed.funcs.push(1)
  parsed.exports.push({ name: "first", desc: Func(0), })
  parsed.exports.push({ name: "second", desc: Func(0), })
  parsed.exports.push({ name: "defined", desc: Func(1), })
  // Imported signature 3 + repeated exports 3 + 3 + defined signature 1.
  check_public_signature_budget(parsed, 10)
  let rejected = try check_public_signature_budget(parsed, 9) catch {
    LimitExceeded(reason) => reason == "public signature slots"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "checked entry enforces production signature expansion budget" {
  fn public_surface(params : Int) -> Bytes {
    let signature = [b"\x01\x60", test_u32(params)]
    for _ in 0..<params {
      signature.push(b"\x7f")
    }
    signature.push(b"\x00")
    let exports = [test_u32(64)]
    for _ in 0..<64 {
      exports.push(b"\x00\x00\x00")
    }
    test_module([
      test_section(1, test_join(signature)),
      test_section(3, b"\x01\x00"),
      test_section(7, test_join(exports)),
      test_section(10, b"\x01\x02\x00\x0b"),
    ])
  }
  let _ = parse_artifact_checked(public_surface(2048))
  let rejected = try parse_artifact_checked(public_surface(2049)) catch {
    LimitExceeded(reason) => reason == "public signature slots"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "checked entry safely parses the production nesting boundary" {
  let parsed = parse_artifact_checked(
    test_code([test_join([b"\x00", test_nested(256)])]),
  )
  assert_eq(parsed.codes.length(), 1)
  let rejected = try
    parse_artifact_checked(test_code([test_join([b"\x00", test_nested(257)])]))
  catch {
    LimitExceeded(reason) => reason == "expression depth"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "checked short header preserves legacy malformed diagnostic" {
  let message = try parse_artifact_checked(b"\x00asm") catch {
    InvalidArtifact(reason) => reason
    LimitExceeded(reason) => reason
  } noraise {
    _ => "accepted"
  }
  assert_eq(message, "unexpected end of input")
}

///|
test "missing end at the instruction budget remains an invalid artifact" {
  let rejected = try
    preflight_artifact(
      test_code([b"\x00\x01"]),
      preflight_limits(instructions=1),
    )
  catch {
    InvalidArtifact(_) => true
    LimitExceeded(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "public signature budget combines imported and exported functions and tags" {
  let parsed = @wasm_types.Module::empty()
  parsed.types.push(@wasm_types.SubType::func([I32, I64, F32], []))
  parsed.types.push(@wasm_types.SubType::func([I32], []))
  parsed.imports.push({ mod_name: "env", name: "f", desc: Func(0), })
  parsed.imports.push({ mod_name: "env", name: "t", desc: Tag(1), })
  parsed.tags.push({ type_idx: 0, })
  parsed.exports.push({ name: "function", desc: Func(0), })
  parsed.exports.push({ name: "imported_tag", desc: Tag(0), })
  parsed.exports.push({ name: "defined_tag", desc: Tag(1), })
  // Imported slots 3 + 1, exported slots 3 + 1 + 3 share one budget.
  check_public_signature_budget(parsed, 11)
  let rejected = try check_public_signature_budget(parsed, 10) catch {
    LimitExceeded(reason) => reason == "public signature slots"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "checked entry enforces production shared tag signature expansion budget" {
  fn public_tags(params : Int) -> Bytes {
    let signature = [b"\x01\x60", test_u32(params)]
    for _ in 0..<params {
      signature.push(b"\x7f")
    }
    signature.push(b"\x00")
    let exports = [test_u32(64)]
    for _ in 0..<64 {
      exports.push(b"\x00\x04\x00")
    }
    test_module([
      test_section(1, test_join(signature)),
      test_section(13, b"\x01\x00\x00"),
      test_section(7, test_join(exports)),
    ])
  }
  let _ = parse_artifact_checked(public_tags(2048))
  let rejected = try parse_artifact_checked(public_tags(2049)) catch {
    LimitExceeded(reason) => reason == "public signature slots"
    InvalidArtifact(_) => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}
