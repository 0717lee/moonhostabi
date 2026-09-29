///|
test "checked verification rejects oversized bytes before report fingerprinting" {
  let oversized = Bytes::make(@wasm_adapter.MAX_ARTIFACT_BYTES + 1, 0)
  let rejected = try {
    ignore(
      verify_artifact_checked(
        oversized,
        InvalidBaseline("unused"),
        ContractNotProvided,
      ),
    )
    false
  } catch {
    @wasm_adapter.LimitExceeded("artifact bytes") => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "checked verification preserves normal report bytes and malformed diagnostics" {
  let malformed = b"\x00asm"
  let baseline = InvalidBaseline("unused")
  assert_eq(
    encode_verification_report(
      verify_artifact_checked(malformed, baseline, ContractNotProvided),
    ),
    encode_verification_report(
      verify_artifact(malformed, baseline, ContractNotProvided),
    ),
  )
}
