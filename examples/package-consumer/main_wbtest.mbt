///|
test "public checked parser resolves a singleton recursive struct" {
  recursive_assertions()
}

///|
test "public checked parser preserves all 256 nested frames" {
  depth_assertions()
}

///|
test "public ArtifactError owns budget and malformed errors" {
  error_assertions()
}

///|
test "lock roundtrip and verification distinguish compatible and breaking ABI" {
  lock_verify_assertions()
}
