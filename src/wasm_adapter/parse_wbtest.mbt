test "wasm_core 0.14 parses an empty core module" {
  let parsed = parse_artifact(b"\x00asm\x01\x00\x00\x00")
  inspect(parsed.imports.length(), content="0")
  inspect(parsed.exports.length(), content="0")
  let canonical = @wasm_types.compute_canonical_type_indices(
    parsed.types,
    type_rec_groups=parsed.type_rec_groups,
  )
  inspect(canonical.length(), content="0")
  let _ = parsed.func_type_at(0)
  let _ = @wasm_types.TypeEquivalenceContext::cross_module(
    parsed.types,
    parsed.types,
    rec_groups1=parsed.type_rec_groups,
    rec_groups2=parsed.type_rec_groups,
  )
}

test "wasm_core parser rejects truncated module" {
  let parse_error = try parse_artifact(b"\x00asm") catch {
    err => Some(err)
  } noraise {
    _ => None
  }
  guard parse_error is Some(err) else {
    fail("expected ParserError for a truncated Wasm module")
  }
  inspect(err.to_string(), content="unexpected end of input")
}
