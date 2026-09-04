///|
test "CLI failure categories reserve stable exit codes" {
  inspect(exit_code_for_failure(Usage), content="1")
  inspect(exit_code_for_failure(BreakingAbi), content="2")
  inspect(exit_code_for_failure(InvalidArtifact), content="3")
  inspect(exit_code_for_failure(AdapterMismatch), content="4")
  inspect(exit_code_for_failure(RuntimeFailure), content="5")
}

///|
test "missing command returns a usage error" {
  let result = dispatch([])
  inspect(result.exit_code, content="1")
  inspect(result.stderr.contains("usage:"), content="true")
}

///|
test "argument parsing is pure and order-sensitive" {
  guard parse_command(["inspect", "module.wasm", "--format", "json"])
    is Some(Inspect(path)) else {
    fail("expected inspect command")
  }
  inspect(path, content="module.wasm")
  assert_true(
    parse_command(["inspect", "module.wasm", "json", "--format"]) is None,
  )
}

///|
test "inspect emits machine-assertable scalar ABI JSON" {
  let result = dispatch([
    "inspect", "fixtures/artifacts/scalar.wasm", "--format", "json",
  ])
  inspect(result.exit_code, content="0")
  guard @json.parse(result.stdout)
    is Object(
      {
        "schemaVersion": Number(schema, ..),
        "imports": Array(imports),
        "exports": Array(exports),
        "types": Array(types),
        "features": Array(features),
        ..
      }
    ) else {
    fail("expected canonical ABI JSON object")
  }
  inspect(schema, content="1")
  inspect(imports.length(), content="0")
  inspect(exports.length(), content="2")
  inspect(types.length(), content="0")
  inspect(features.length(), content="0")
  guard exports[0]
    is Object(
      {
        "name": String(first_name),
        "params": Array(first_params),
        "results": Array(first_results),
        ..
      }
    ) else {
    fail("expected first exported function")
  }
  inspect(first_name, content="add")
  debug_inspect(first_params, content="[String(\"i32\"), String(\"i32\")]")
  debug_inspect(first_results, content="[String(\"i32\")]")
  guard exports[1]
    is Object(
      {
        "name": String(second_name),
        "params": Array(second_params),
        "results": Array(second_results),
        ..
      }
    ) else {
    fail("expected second exported function")
  }
  inspect(second_name, content="answer")
  debug_inspect(second_params, content="[]")
  debug_inspect(second_results, content="[String(\"i64\")]")
}

///|
test "lock and check preserve the baseline and classify breaking ABI" {
  let lock_path = "_build/task10-breaking.lock.json"
  if @fs.path_exists(lock_path) {
    @fs.remove_file(lock_path)
  }
  let locked = dispatch([
    "lock", "fixtures/artifacts/breaking_v1.wasm", "--out", lock_path,
  ])
  inspect(locked.exit_code, content="0")
  inspect(@fs.is_file(lock_path), content="true")
  let before = @fs.read_file_to_bytes(lock_path)
  inspect(@json.valid(@utf8.decode(before[:])), content="true")
  let overwrite = dispatch([
    "lock", "fixtures/artifacts/breaking_v2.wasm", "--out", lock_path,
  ])
  inspect(overwrite.exit_code, content="3")
  inspect(@fs.read_file_to_bytes(lock_path) == before, content="true")

  let compatible = dispatch([
    "check", "fixtures/artifacts/breaking_v1.wasm", "--against", lock_path,
  ])
  inspect(compatible.exit_code, content="0")

  let breaking = dispatch([
    "check", "fixtures/artifacts/breaking_v2.wasm", "--against", lock_path,
  ])
  inspect(breaking.exit_code, content="2")
  inspect(breaking.stdout.contains("MHA_SIGNATURE_CHANGED"), content="true")
  inspect(breaking.stdout.contains("exports[add].params"), content="true")
  inspect(@fs.read_file_to_bytes(lock_path) == before, content="true")
  @fs.remove_file(lock_path)
}

///|
test "malformed and unsupported artifacts exit three" {
  let malformed_path = "_build/task10-malformed.wasm"
  @fs.write_bytes_to_file(malformed_path, b"\x00asm")
  let malformed = dispatch(["inspect", malformed_path, "--format", "json"])
  inspect(malformed.exit_code, content="3")
  inspect(malformed.stderr.contains("MHA_PARSE_MALFORMED"), content="true")
  @fs.remove_file(malformed_path)

  let unsupported = dispatch([
    "inspect", "fixtures/artifacts/recursive.wasm", "--format", "json",
  ])
  inspect(unsupported.exit_code, content="3")
  inspect(
    unsupported.stderr.contains("MHA_PROJECT_UNREPRESENTABLE"),
    content="true",
  )
}

///|
test "I/O errors are not mislabeled as malformed Wasm" {
  let missing = dispatch([
    "inspect", "_build/definitely-missing-task10.wasm", "--format", "json",
  ])
  inspect(missing.exit_code, content="3")
  inspect(missing.stderr.contains("MHA_INPUT_IO"), content="true")
  inspect(missing.stderr.contains("MHA_PARSE_MALFORMED"), content="false")
}

///|
test "artifact provenance is evidence rather than compatibility identity" {
  let path = "_build/task10-provenance.lock.json"
  if @fs.path_exists(path) {
    @fs.remove_file(path)
  }
  let wasm_module = @wasm_adapter.parse_artifact(
    @fs.read_file_to_bytes("fixtures/artifacts/breaking_v1.wasm"),
  )
  let analysis = @projector.analyze_host_abi(
    wasm_module,
    @projector.default_js_capability_policy(),
  )
  let different_provenance = @lockfile.create_lockfile(
    analysis.abi,
    b"not-the-current-artifact",
  )
  @fs.write_bytes_to_file(
    path,
    @utf8.encode(@lockfile.encode_lockfile(different_provenance)),
  )
  let result = dispatch([
    "check", "fixtures/artifacts/breaking_v1.wasm", "--against", path,
  ])
  inspect(result.exit_code, content="0")
  inspect(
    result.stdout.contains("\"classification\":\"compatible\""),
    content="true",
  )
  @fs.remove_file(path)
}
