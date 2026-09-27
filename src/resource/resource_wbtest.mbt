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
  let decoded = decode_memory_contract(encode_memory_contract(contract))
  inspect(decoded == contract, content="true")
  let fractional = encode_memory_contract(contract).replace(
    old="\"minimumPages\":1",
    new="\"minimumPages\":1.5",
  )
  inspect(
    try {
      ignore(decode_memory_contract(fractional))
      false
    } catch {
      _ => true
    },
    content="true",
  )
}

///|
test "resource lockfile v2 is deterministic" {
  let empty_abi = ResourceAbi::{
    schema_version: 2,
    memories: [],
    unsupported: [],
  }
  let first = encode_lockfile(create_lockfile(empty_abi, b"artifact"))
  let second = encode_lockfile(create_lockfile(empty_abi, b"artifact"))
  inspect(first == second, content="true")
  inspect(first.contains("\"lockfileVersion\":2"), content="true")
  inspect(
    create_lockfile(empty_abi, b"artifact").schema_sha256.length(),
    content="64",
  )
  let lockfile = create_lockfile(empty_abi, b"artifact")
  inspect(
    decode_lockfile(encode_lockfile(lockfile)) == lockfile,
    content="true",
  )
  inspect(
    try {
      ignore(decode_lockfile(encode_lockfile(lockfile) + " "))
      false
    } catch {
      _ => true
    },
    content="true",
  )
  let bad_hash = encode_lockfile(lockfile).replace(
    old=lockfile.artifact_sha256,
    new="not-a-sha",
  )
  inspect(
    try {
      ignore(decode_lockfile(bad_hash))
      false
    } catch {
      _ => true
    },
    content="true",
  )

  let memory_z : MemoryResource = {
    path: "exports[z]",
    module_name: None,
    name: "z",
    minimum_pages: 2L,
    maximum_pages: Some(4L),
    shared: false,
    memory64: false,
    page_size_log2: 16,
  }
  let memory_a : MemoryResource = {
    path: "exports[a]",
    module_name: None,
    name: "a",
    minimum_pages: 1L,
    maximum_pages: Some(2L),
    shared: false,
    memory64: false,
    page_size_log2: 16,
  }
  let reverse_abi = ResourceAbi::{
    schema_version: 2,
    memories: [memory_z, memory_a],
    unsupported: ["reason-z", "reason-a"],
  }
  let sorted_abi = ResourceAbi::{
    schema_version: 2,
    memories: [memory_a, memory_z],
    unsupported: ["reason-a", "reason-z"],
  }
  inspect(
    encode_canonical_abi(reverse_abi),
    content="{\"schemaVersion\":2,\"memories\":[{\"path\":\"exports[a]\",\"module\":null,\"name\":\"a\",\"minimumPages\":1,\"maximumPages\":2,\"shared\":false,\"memory64\":false,\"pageSizeLog2\":16},{\"path\":\"exports[z]\",\"module\":null,\"name\":\"z\",\"minimumPages\":2,\"maximumPages\":4,\"shared\":false,\"memory64\":false,\"pageSizeLog2\":16}],\"unsupported\":[\"reason-a\",\"reason-z\"]}",
  )
  let reverse_lockfile = create_lockfile(reverse_abi, b"artifact")
  let sorted_lockfile = create_lockfile(sorted_abi, b"artifact")
  inspect(
    encode_lockfile(reverse_lockfile) == encode_lockfile(sorted_lockfile),
    content="true",
  )
  inspect(
    reverse_lockfile.abi_sha256 == sorted_lockfile.abi_sha256,
    content="true",
  )
}

///|
test "complete resource surface v3 round trips all resource kinds" {
  let surface = ResourceSurface::{
    schema_version: 99,
    memories: [],
    tables: [
      {
        path: "imports[env.table]",
        module_name: Some("env"),
        name: "table",
        element_type: "externref",
        minimum_elements: 1L,
        maximum_elements: Some(8L),
        table64: false,
      },
    ],
    globals: [
      {
        path: "exports[counter]",
        module_name: None,
        name: "counter",
        value_type: "i32",
        mutable: true,
      },
    ],
    tags: [
      {
        path: "imports[env.fail]",
        module_name: Some("env"),
        name: "fail",
        type_index: 2L,
      },
    ],
    unsupported: ["exports[legacy]"],
  }
  let lockfile = create_resource_lockfile(surface, b"resource-artifact")
  let encoded = encode_resource_lockfile(lockfile)
  inspect(encoded.contains("\"tables\""), content="true")
  inspect(encoded.contains("\"globals\""), content="true")
  inspect(encoded.contains("\"tags\""), content="true")
  inspect(decode_resource_lockfile(encoded) == lockfile, content="true")
  let contract = create_resource_contract(surface)
  inspect(validate_resource_contract(surface, contract), content="true")
  inspect(
    decode_resource_contract(encode_resource_contract(contract)) == contract,
    content="true",
  )
}

///|
test "complete resource protocol rejects invalid limits and fingerprints" {
  let surface = ResourceSurface::{
    schema_version: 3,
    memories: [],
    tables: [
      {
        path: "exports[table]",
        module_name: None,
        name: "table",
        element_type: "funcref",
        minimum_elements: 2L,
        maximum_elements: Some(4L),
        table64: false,
      },
    ],
    globals: [],
    tags: [],
    unsupported: [],
  }
  let lockfile = create_resource_lockfile(surface, b"artifact")
  let bad_hash = encode_resource_lockfile(lockfile).replace(
    old=lockfile.abi_sha256,
    new="0000000000000000000000000000000000000000000000000000000000000000",
  )
  inspect(
    try {
      ignore(decode_resource_lockfile(bad_hash))
      false
    } catch {
      _ => true
    },
    content="true",
  )
  let invalid_surface : ResourceSurface = {
    ..surface,
    tables: [{ ..surface.tables[0], maximum_elements: Some(1L), }],
  }
  let invalid_lockfile = create_resource_lockfile(invalid_surface, b"artifact")
  inspect(
    try {
      ignore(
        decode_resource_lockfile(encode_resource_lockfile(invalid_lockfile)),
      )
      false
    } catch {
      InvalidResource(message) =>
        message ==
        "lockfile.abi.tables[0].maximumElements: must be at least minimumElements"
    },
    content="true",
  )
}
