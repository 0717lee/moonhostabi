///|
test "expression frames retain ordered siblings branches and catch handlers" {
  let bytes = test_code([
    b"\x00\x41\x07\x02\x40\x03\x40\x04\x40\x41\x01\x05\x41\x02\x0b\x1f\x40\x04\x00\x00\x01\x01\x02\x03\x02\x04\x03\x05\x01\x0b\x0b\x41\x08\x0b\x04\x40\x41\x09\x0b\x41\x03\x0b",
  ])
  let expected : Array[@wasm_types.Instruction] = [
    I32Const(7),
    Block(Empty, [
      Loop(Empty, [
        If(Empty, [I32Const(1)], [I32Const(2)]),
        TryTable(
          Empty,
          [Catch(0, 1), CatchRef(2, 3), CatchAll(4), CatchAllRef(5)],
          [Nop],
        ),
      ]),
      I32Const(8),
    ]),
    If(Empty, [I32Const(9)], []),
    I32Const(3),
  ]
  assert_eq(parse_artifact_checked(bytes).codes[0].body, expected)
}

///|
test "expression parser retains legacy misplaced else and truncation errors" {
  for
    body in [
      b"\x00\x05\x0b", b"\x00\x02\x40\x05\x0b\x0b", b"\x00\x04\x40\x05\x05\x0b\x0b",
    ] {
    let outcome = try parse_artifact(test_code([body])) catch {
      InvalidArtifact(reason) => reason
      LimitExceeded(reason) => "unexpected limit: " + reason
    } noraise {
      _ => "accepted"
    }
    assert_eq(outcome, "unknown opcode 0x5 at current position")
  }
  for body in [b"\x00\x02\x40", b"\x00\x04\x40\x05", b"\x00\x1f\x40\x00"] {
    let outcome = try parse_artifact(test_code([body])) catch {
      InvalidArtifact(reason) => reason
      LimitExceeded(reason) => "unexpected limit: " + reason
    } noraise {
      _ => "accepted"
    }
    assert_eq(outcome, "unexpected end of input")
  }
}

///|
test "iterative expression parser safely retains 256 nested control frames" {
  for
    delimiters in [
      (b"\x02\x40", b"\x0b"),
      (b"\x03\x40", b"\x0b"),
      (b"\x04\x40", b"\x05\x01\x0b"),
      (b"\x1f\x40\x01\x02\x00", b"\x0b"),
    ] {
    let (opening, closing) = delimiters
    let parts = [b"\x00"]
    for _ in 0..<256 {
      parts.push(opening)
    }
    parts.push(b"\x01")
    for _ in 0..<256 {
      parts.push(closing)
    }
    parts.push(b"\x0b")
    let parsed = parse_artifact_checked(test_code([test_join(parts)]))
    let mut body = parsed.codes[0].body
    for _ in 0..<256 {
      assert_eq(body.length(), 1)
      body = match body[0] {
        Block(Empty, nested) | Loop(Empty, nested) => nested
        If(Empty, nested, otherwise) => {
          assert_eq(otherwise, [@wasm_types.Instruction::Nop])
          nested
        }
        TryTable(Empty, handlers, nested) => {
          assert_eq(handlers, [@wasm_types.CatchHandler::CatchAll(0)])
          nested
        }
        _ => fail("lost nested control frame")
      }
    }
    assert_eq(body, [@wasm_types.Instruction::Nop])
  }
}
