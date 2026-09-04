test "wasm_core 0.14 parses an empty core module" {
  let module = parse_artifact(b"\x00asm\x01\x00\x00\x00")
  inspect(module.imports.length(), content="0")
  inspect(module.exports.length(), content="0")
  let canonical = @wasm_types.compute_canonical_type_indices(
    module.types,
    type_rec_groups=module.type_rec_groups,
  )
  inspect(canonical.length(), content="0")
  let _ = module.func_type_at(0)
  let _ = @wasm_types.TypeEquivalenceContext::cross_module(
    module.types,
    module.types,
    rec_groups1=module.type_rec_groups,
    rec_groups2=module.type_rec_groups,
  )
}

test "wasm_core parser rejects truncated module" {
  let raised = try {
    let _ = parse_artifact(b"\x00asm")
    false
  } catch {
    _ => true
  }
  inspect(raised, content="true")
}
