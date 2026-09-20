///|
test "resource lock and verify stdout are valid JSON" {
  let path = "_build/resource-cli-json.lock.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  let result = dispatch([
    "resource-lock-v3", "fixtures/artifacts/scalar.wasm", "--out", path,
  ])
  inspect(result.exit_code, content="0")
  assert_true(@json.valid(result.stdout))
  let verify = dispatch([
    "resource-verify", "fixtures/artifacts/scalar.wasm", "--against", path, "--format",
    "json",
  ])
  inspect(verify.exit_code, content="0")
  assert_true(@json.valid(verify.stdout))
  @fs.remove_file(path)
}

///|
test "resource verification detects a defined exported global value type change" {
  let before_path = "_build/resource-cli-global-i32.wasm"
  let after_path = "_build/resource-cli-global-i64.wasm"
  let lock_path = "_build/resource-cli-global.lock.json"
  if @fs.path_exists(lock_path) {
    @fs.remove_file(lock_path)
  }
  @fs.write_bytes_to_file(
    before_path, b"\x00asm\x01\x00\x00\x00\x06\x06\x01\x7f\x00\x41\x00\x0b\x07\x05\x01\x01g\x03\x00",
  )
  @fs.write_bytes_to_file(
    after_path, b"\x00asm\x01\x00\x00\x00\x06\x06\x01\x7e\x00\x42\x00\x0b\x07\x05\x01\x01g\x03\x00",
  )
  let result = dispatch(["resource-lock-v3", before_path, "--out", lock_path])
  inspect(result.exit_code, content="0")
  let verify = dispatch([
    "resource-verify", after_path, "--against", lock_path, "--format", "json",
  ])
  inspect(verify.exit_code, content="2")
  for path in [before_path, after_path, lock_path] {
    @fs.remove_file(path)
  }
}

///|
test "resource report formats preserve exit codes and legacy tag baselines fail closed" {
  let path = "_build/resource-cli-legacy-tag.lock.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  let result = dispatch([
    "resource-lock-v3", "fixtures/artifacts/resources.wasm", "--out", path,
  ])
  inspect(result.exit_code, content="0")
  for format in ["json", "text", "markdown"] {
    let verify = dispatch([
      "resource-verify", "fixtures/artifacts/resources.wasm", "--against", path,
      "--format", format,
    ])
    inspect(verify.exit_code, content="3")
    assert_true(verify.stdout.contains("unknown"))
    if format == "json" {
      assert_true(@json.valid(verify.stdout))
    }
  }
  @fs.remove_file(path)
}

///|
test "resource contract mismatched to artifact is rejected before output publication" {
  let path = "_build/resource-cli-match.contract.json"
  let output = "_build/resource-cli-mismatch-must-not-exist"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  assert_false(@fs.path_exists(output))
  let result = dispatch([
    "resource-contract", "fixtures/artifacts/resources.wasm", "--out", path,
  ])
  inspect(result.exit_code, content="0")
  let generated = dispatch([
    "generate", "fixtures/artifacts/resources-global-type-changed.wasm", "--resource-contract",
    path, "--out", output,
  ])
  assert_true(generated.exit_code != 0)
  assert_true(generated.stderr.contains("MHA_CONTRACT_INVALID"))
  assert_false(@fs.path_exists(output))
  @fs.remove_file(path)
}

///|
test "new resource command grammar is explicit and rejects unknown formats" {
  assert_true(
    parse_command(["resource-lock-v4", "a.wasm", "--out", "a.json"])
    is Some(ResourceLockV4(_, _)),
  )
  assert_true(
    parse_command(["resource-contract", "a.wasm", "--out", "a.json"])
    is Some(ResourceContract(_, _)),
  )
  assert_true(
    parse_command([
      "resource-verify", "a.wasm", "--against", "a.json", "--format", "csv",
    ])
    is None,
  )
  assert_true(
    parse_command([
      "generate", "a.wasm", "--contract", "functions.json", "--resource-contract",
      "resources.json", "--out", "out",
    ])
    is Some(Generate(_, Some(_), Some(_), _, Fresh)),
  )
}

///|
test "resource baseline decoder rejects malformed and unsupported wire formats" {
  for
    text in [
      "{", "[]", "{}", "{\"lockfileVersion\":99}", "{\"lockfileVersion\":4}", "{\"lockfileVersion\":3}",
    ] {
    let rejected = try {
      ignore(resource_baseline(text))
      false
    } catch {
      CliExecutionError(code, _) => {
        assert_eq(code, MHA_LOCKFILE_INVALID)
        true
      }
    }
    assert_true(rejected)
  }
  let artifact = @fs.read_file_to_bytes("fixtures/artifacts/resources.wasm")
  let surface = resource_projection(artifact)
  let decoded = resource_baseline(
    @resource.encode_resource_lockfile_v4(
      @resource.create_resource_lockfile_v4(surface, artifact),
    ),
  )
  assert_eq(decoded, surface)
  let malformed_artifact = try {
    ignore(resource_projection(b"not wasm"))
    false
  } catch {
    CliExecutionError(code, _) => {
      assert_eq(code, "MHA_RESOURCE_INVALID")
      true
    }
  }
  assert_true(malformed_artifact)
}

///|
test "resource generation validates contract version schema and legacy migration" {
  let bytes = @fs.read_file_to_bytes(
    "fixtures/artifacts/resources-escaped.wasm",
  )
  let surface = resource_projection(bytes)
  for
    text in [
      "{", "[]", "{}", "{\"schemaVersion\":99}", "{\"schemaVersion\":5}", "{\"schemaVersion\":4}",
    ] {
    let rejected = try {
      ignore(resource_contract_for_surface(text, surface))
      false
    } catch {
      CliExecutionError(code, _) => {
        assert_eq(code, MHA_CONTRACT_INVALID)
        true
      }
    }
    assert_true(rejected)
  }
  let legacy = legacy_resource_surface(
    surface,
    @wasm_adapter.parse_artifact(bytes),
  )
  let legacy_contract = @resource.encode_resource_contract(
    @resource.create_resource_contract(legacy),
  )
  let lifted = resource_contract_for_surface(legacy_contract, surface)
  assert_eq(lifted.schema_version, 5)
  assert_true(@resource.validate_resource_contract_v5(surface, lifted))
  let tagged_bytes = @fs.read_file_to_bytes("fixtures/artifacts/resources.wasm")
  let tagged = resource_projection(tagged_bytes)
  let legacy_tagged = legacy_resource_surface(
    tagged,
    @wasm_adapter.parse_artifact(tagged_bytes),
  )
  let tagged_contract = @resource.encode_resource_contract(
    @resource.create_resource_contract(legacy_tagged),
  )
  let rejected = try {
    ignore(resource_contract_for_surface(tagged_contract, tagged))
    false
  } catch {
    CliExecutionError(code, message) => {
      assert_eq(code, MHA_CONTRACT_INVALID)
      assert_true(message.contains("regenerate"))
      true
    }
  }
  assert_true(rejected)
}
