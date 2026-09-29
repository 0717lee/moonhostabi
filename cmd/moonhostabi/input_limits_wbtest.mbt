///|
test "bounded input reads accept exact bytes and reject one over" {
  let path = "_build/bounded-input-test.bin"
  @fs.write_bytes_to_file(path, b"\x00\xffab")
  defer (@fs.remove_file(path) catch { _ => () })
  assert_eq(read_bytes(path, limit=4), b"\x00\xffab")
  let error = try {
    ignore(read_bytes(path, limit=3))
    "accepted"
  } catch {
    CliExecutionError(code, _) => code
  }
  assert_eq(error, "MHA_INPUT_TOO_LARGE")
  @fs.write_bytes_to_file(path, b"")
  assert_eq(read_bytes(path, limit=0), b"")
}

///|
test "bounded input reads keep missing files distinct from budget rejection" {
  let error = try {
    ignore(read_bytes("_build/absent-bounded-input.bin", limit=1))
    "accepted"
  } catch {
    CliExecutionError(code, _) => code
  }
  assert_eq(error, MHA_INPUT_IO)
}

///|
test "resource commands retain explicit structural input limit classification" {
  let path = "_build/locals-over-budget.wasm"
  // One function declares 65,537 locals in a compact RLE group.
  @fs.write_bytes_to_file(
    path, b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x08\x01\x06\x01\x81\x80\x04\x7f\x0b",
  )
  defer (@fs.remove_file(path) catch { _ => () })
  for
    args in [
      ["inspect", path, "--format", "json"],
      ["resource-lock-v4", path, "--out", "_build/unused-budget-lock"],
      ["resource-contract", path, "--out", "_build/unused-budget-contract"],
    ] {
    let result = dispatch(args)
    assert_eq(result.exit_code, 3)
    assert_eq(result.stdout, "")
    assert_true(result.stderr.contains("MHA_INPUT_LIMIT"))
  }
}

///|
test "contract and resource baseline reads preserve I/O versus decoding errors" {
  let missing = "_build/absent-budget-document.json"
  let generate = dispatch([
    "generate", "fixtures/artifacts/externref.wasm", "--contract", missing, "--out",
    "_build/unused-budget-output",
  ])
  assert_eq(generate.exit_code, 3)
  assert_true(generate.stderr.contains("MHA_INPUT_IO"))
  let verify = dispatch([
    "resource-verify", "fixtures/artifacts/resources.wasm", "--against", missing,
    "--format", "json",
  ])
  assert_eq(verify.exit_code, 3)
  assert_true(verify.stderr.contains("MHA_INPUT_IO"))
  let invalid = "_build/budget-document-invalid-utf8.json"
  @fs.write_bytes_to_file(invalid, b"\xff")
  defer (@fs.remove_file(invalid) catch { _ => () })
  let invalid_contract = dispatch([
    "generate", "fixtures/artifacts/externref.wasm", "--contract", invalid, "--out",
    "_build/unused-budget-output",
  ])
  assert_true(invalid_contract.stderr.contains("MHA_CONTRACT_INVALID"))
  let invalid_baseline = dispatch([
    "resource-verify", "fixtures/artifacts/resources.wasm", "--against", invalid,
    "--format", "json",
  ])
  assert_true(invalid_baseline.stderr.contains("MHA_LOCKFILE_INVALID"))
}

///|
test "oversized generated files fail before publication" {
  let path = "_build/oversized-generated-output.bin"
  assert_false(@fs.path_exists(path))
  defer (@fs.remove_file(path) catch { _ => () })
  let code = try {
    write_new_file(path, Bytes::make(8 * 1024 * 1024 + 1, 0))
    "accepted"
  } catch {
    CliExecutionError(code, _) => code
  }
  assert_eq(code, "MHA_OUTPUT_LIMIT")
  assert_false(@fs.path_exists(path))
}

///|
test "oversized contract and resource baseline preserve input limit errors" {
  let path = "_build/oversized-input-document.json"
  @fs.write_bytes_to_file(
    path,
    Bytes::make(@wasm_adapter.MAX_ARTIFACT_BYTES + 1, 32),
  )
  defer (@fs.remove_file(path) catch { _ => () })
  for
    args in [
      [
        "generate", "fixtures/artifacts/externref.wasm", "--contract", path, "--out",
        "_build/unused-budget-output",
      ],
      [
        "resource-verify", "fixtures/artifacts/resources.wasm", "--against", path,
        "--format", "json",
      ],
    ] {
    let result = dispatch(args)
    assert_eq(result.exit_code, 3)
    assert_eq(result.stdout, "")
    assert_true(result.stderr.contains("MHA_INPUT_TOO_LARGE"))
  }
}

///|
test "oversized generated contract cleans staging and keeps target absent" {
  let output = "_build/oversized-contract-output"
  assert_false(@fs.path_exists(output))
  let generated = transaction_fixture()
  let bytes = Bytes::make(1024 * 1024 + 1, 97)
  let oversized = { ..generated, contract: @utf8.decode(bytes[:]), }
  let error = publish_error(output, oversized, Fresh, None)
  assert_true(error.has_prefix("MHA_OUTPUT_LIMIT:"))
  assert_false(@fs.path_exists(output))
  assert_true(transaction_siblings("oversized-contract-output").is_empty())
}
