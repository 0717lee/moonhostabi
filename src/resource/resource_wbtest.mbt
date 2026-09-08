///|
test "resource ABI canonicalization and memory contract" {
  let abi = ResourceAbi::{
    schema_version: 99,
    memories: [
      {
        path: "exports[memory]",
        module_name: None,
        name: "memory",
        minimum_pages: 1L,
        maximum_pages: Some(4L),
        shared: false,
        memory64: false,
        page_size_log2: 16,
      },
    ],
    unsupported: ["exports[tag]"],
  }
  let encoded = encode_canonical_abi(abi)
  inspect(encoded.contains("\"schemaVersion\":99"), content="true")
  inspect(abi_sha256(abi).length(), content="64")
  let contract = create_memory_contract(abi)
  inspect(contract.schema_version, content="3")
  inspect(validate_memory_contract(abi, contract), content="true")
  inspect(
    encode_memory_contract(contract).contains("\"memories\""),
    content="true",
  )
  inspect(
    generate_memory_contract(abi).contains("\"schemaVersion\":3"),
    content="true",
  )
}

///|
test "resource lockfile v2 is deterministic" {
  let abi = ResourceAbi::{ schema_version: 2, memories: [], unsupported: [], }
  let first = encode_lockfile(create_lockfile(abi, b"artifact"))
  let second = encode_lockfile(create_lockfile(abi, b"artifact"))
  inspect(first == second, content="true")
  inspect(first.contains("\"lockfileVersion\":2"), content="true")
  inspect(
    create_lockfile(abi, b"artifact").schema_sha256.length(),
    content="64",
  )
}
