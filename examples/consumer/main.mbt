///|
fn consume(v1_path : String, v2_path : String, output : String) -> Unit raise {
  let v1 = @fs.read_file_to_bytes(v1_path)
  let v2 = @fs.read_file_to_bytes(v2_path)
  let analysis = @projector.analyze_host_abi(
    @wasm_adapter.parse_artifact_checked(v1),
    @projector.default_js_capability_policy(),
  )
  assert_true(analysis.diagnostics.is_empty())
  // This app exposes scalar functions only; public resources need a resource contract.
  assert_true(analysis.resources.is_empty())
  let lock_text = @lockfile.encode_lockfile(
    @lockfile.create_lockfile(analysis.abi, v1),
  )
  let lock_path = "\{output}/pricing.lock.json"
  @fs.write_string_to_file(lock_path, lock_text)
  let baseline = @verification.decode_verification_baseline(
    @fs.read_file_to_string(lock_path),
  )
  let contract = @contract.create_contract_draft(analysis.abi)
  let compatible = @verification.verify_artifact_checked(
    v1,
    baseline,
    @verification.ContractText(@contract.encode_contract(contract)),
  )
  @fs.write_string_to_file(
    "\{output}/v1.report.json",
    @verification.encode_verification_report(compatible),
  )
  assert_eq(compatible.outcome, @verification.VerificationCompatible)
  assert_eq(compatible.recommended_exit_code(), 0)
  assert_eq(compatible.provenance_artifact_match, Some(true))
  println("CONSUMER_V1_EXIT=\{compatible.recommended_exit_code()}")

  // Compare ABI first: a stale v1 contract would instead produce adapterMismatch.
  let breaking = @verification.verify_artifact_checked(
    v2,
    baseline,
    @verification.ContractNotProvided,
  )
  @fs.write_string_to_file(
    "\{output}/v2.report.json",
    @verification.encode_verification_report(breaking),
  )
  assert_eq(breaking.outcome, @verification.VerificationBreaking)
  assert_eq(breaking.recommended_exit_code(), 2)
  println("CONSUMER_V2_EXIT=\{breaking.recommended_exit_code()}")

  let generated = @generator.generate_typescript_adapter(analysis.abi, contract)
  assert_true(generated.diagnostics.is_empty())
  assert_false(generated.typescript.is_empty())
  @fs.create_dir("\{output}/generated")
  @fs.write_string_to_file(
    "\{output}/generated/adapter.ts",
    generated.typescript,
  )
  @fs.write_string_to_file(
    "\{output}/generated/moonhostabi.contract.json",
    generated.contract,
  )
  @fs.write_string_to_file(
    "\{output}/generated/moonhostabi.manifest.json",
    generated.manifest,
  )
  println("CONSUMER_SDK=GO")
}

///|
fn main {
  try {
    let args = @env.args()
    assert_eq(args.length(), 4)
    consume(args[1], args[2], args[3])
  } catch {
    error => {
      println("CONSUMER_SDK_ERROR=\{error}")
      @sys.exit(1)
    }
  }
}
