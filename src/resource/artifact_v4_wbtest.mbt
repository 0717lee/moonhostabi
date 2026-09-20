///|
fn memory_artifact_fixture(sections : Array[(Int, Bytes)]) -> Bytes {
  let bytes : Array[Byte] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]
  for section in sections {
    bytes.push(section.0.to_byte())
    // Test payloads are deliberately small enough for a single-byte length.
    bytes.push(section.1.length().to_byte())
    for byte in section.1 {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes)
}

///|
fn reference_global_artifact(prefix : Byte, heap_type : Byte) -> Bytes {
  memory_artifact_fixture([
    (
      2,
      Bytes::from_array([
        0x01, 0x03, 0x65, 0x6e, 0x76, 0x01, 0x67, 0x03, prefix, heap_type, 0x00,
      ]),
    ),
  ])
}

///|
test "artifact v4 never approves references whose nullability the parser loses" {
  // exn, noextern, nofunc and noexn all lose this distinction in wasm_core 0.14.
  for heap_type in [0x69, 0x72, 0x73, 0x74] {
    let nullable = project_resource_artifact(
      reference_global_artifact(0x63, heap_type.to_byte()),
    )
    let nonnullable = project_resource_artifact(
      reference_global_artifact(0x64, heap_type.to_byte()),
    )
    let report = compare_resource_surfaces(nullable, nonnullable)
    assert_eq(report.exit_code, 3)
    assert_eq(report.classification, "unknown")
    assert_false(report.compatible)
    assert_true(nullable.globals.is_empty())
    assert_true(nonnullable.globals.is_empty())
    assert_true(nullable.unsupported[0].contains("nullability"))
    assert_false(
      validate_resource_contract_v5(
        nullable,
        create_resource_contract_v5(nullable),
      ),
    )
  }
}

///|
test "artifact v4 rejects invalid imported tag attributes" {
  let artifact = memory_artifact_fixture([
    (1, b"\x01\x60\x00\x00"),
    (2, b"\x01\x01e\x01e\x04\x01\x00"),
  ])
  assert_true(
    try {
      ignore(project_resource_artifact(artifact))
      false
    } catch {
      InvalidResource(_) => true
    },
  )
}

///|
test "artifact v4 rejects invalid defined tag attributes" {
  let artifact = memory_artifact_fixture([
    (1, b"\x01\x60\x00\x00"),
    (13, b"\x01\x01\x00"),
    (7, b"\x01\x01e\x04\x00"),
  ])
  assert_true(
    try {
      ignore(project_resource_artifact(artifact))
      false
    } catch {
      InvalidResource(_) => true
    },
  )
  let valid = project_resource_artifact(
    memory_artifact_fixture([
      (1, b"\x01\x60\x00\x00"),
      (13, b"\x01\x00\x00"),
      (7, b"\x01\x01e\x04\x00"),
    ]),
  )
  assert_true(valid.unsupported.is_empty())
  assert_eq(valid.tags.length(), 1)
  assert_eq(valid.tags[0].params, [])
}

///|
test "artifact v4 flags lost table and tag reference nullability" {
  let surface = project_resource_artifact(
    memory_artifact_fixture([
      (1, b"\x01\x60\x01\x63\x69\x00"),
      (2, b"\x02\x03env\x01t\x01\x63\x69\x00\x00\x03env\x01e\x04\x00\x00"),
    ]),
  )
  assert_true(surface.tables.is_empty())
  assert_true(surface.tags.is_empty())
  assert_eq(surface.unsupported.length(), 2)
  for reason in surface.unsupported {
    assert_true(reason.contains("nullability"))
  }
  assert_eq(compare_resource_surfaces(surface, surface).exit_code, 3)
}

///|
test "artifact v4 distinguishes ordinary and shared memory" {
  let ordinary = project_resource_artifact(
    memory_artifact_fixture([
      (5, b"\x01\x01\x01\x04"),
      (7, b"\x01\x03mem\x02\x00"),
    ]),
  )
  let shared = project_resource_artifact(
    memory_artifact_fixture([
      (5, b"\x01\x03\x01\x04"),
      (7, b"\x01\x03mem\x02\x00"),
    ]),
  )
  assert_eq(ordinary.memories.length(), 1)
  assert_eq(ordinary.memories[0].path, "exports[\"mem\"]")
  assert_eq(ordinary.memories[0].minimum_pages, 1L)
  assert_eq(ordinary.memories[0].maximum_pages, Some(4L))
  assert_false(ordinary.memories[0].shared)
  assert_true(shared.memories[0].shared)
  assert_true(ordinary.unsupported.is_empty())
  assert_true(shared.unsupported.is_empty())
  assert_not_eq(
    resource_surface_v4_sha256(ordinary),
    resource_surface_v4_sha256(shared),
  )
}

///|
test "artifact v4 resolves imported and defined memory index spaces" {
  let surface = project_resource_artifact(
    memory_artifact_fixture([
      (1, b"\x01\x60\x00\x00"),
      (
        2, b"\x05\x03env\x01f\x00\x00\x03env\x01t\x01\x70\x00\x01\x03env\x01g\x03\x7f\x00\x03env\x01e\x04\x00\x00\x03env\x01m\x02\x03\x02\x08",
      ),
      (5, b"\x01\x01\x03\x09"),
      (7, b"\x02\x05alias\x02\x00\x05local\x02\x01"),
    ]),
  )
  assert_eq(surface.memories.length(), 3)
  assert_eq(surface.memories[0].path, "imports[\"env\"][\"m\"]")
  assert_eq(surface.memories[1].path, "exports[\"alias\"]")
  assert_eq(surface.memories[1].minimum_pages, 2L)
  assert_eq(surface.memories[1].maximum_pages, Some(8L))
  assert_true(surface.memories[0].shared)
  assert_true(surface.memories[1].shared)
  assert_eq(surface.memories[2].minimum_pages, 3L)
  assert_false(surface.memories[2].shared)
  assert_eq(surface.tables.length(), 1)
  assert_eq(surface.globals.length(), 1)
  assert_eq(surface.tags.length(), 1)
  assert_true(surface.unsupported.is_empty())
}

///|
test "artifact v4 reads memory64 custom page sizes without shifting later memories" {
  let surface = project_resource_artifact(
    memory_artifact_fixture([
      (
        5, b"\x03\x0f\x80\x80\x80\x80\x10\x80\x80\x80\x80\x20\x00\x08\x03\x00\x00\x04",
      ),
      (7, b"\x03\x04wide\x02\x00\x05small\x02\x01\x05plain\x02\x02"),
    ]),
  )
  assert_eq(surface.memories[0].minimum_pages, 4294967296L)
  assert_eq(surface.memories[0].maximum_pages, Some(8589934592L))
  assert_eq(surface.memories[0].page_size_log2, 0)
  assert_true(surface.memories[0].shared)
  assert_true(surface.memories[0].memory64)
  assert_eq(surface.memories[1].minimum_pages, 3L)
  assert_eq(surface.memories[1].maximum_pages, None)
  assert_eq(surface.memories[1].page_size_log2, 0)
  assert_false(surface.memories[1].shared)
  assert_eq(surface.memories[2].minimum_pages, 4L)
  assert_eq(surface.memories[2].page_size_log2, 16)
  assert_false(surface.memories[2].shared)
}

///|
test "artifact v4 retains unrelated unsupported resource metadata" {
  let surface = project_resource_artifact(
    memory_artifact_fixture([
      (1, b"\x01\x60\x00\x00"),
      (2, b"\x02\x03env\x01g\x03\x63\x00\x00\x03env\x01m\x02\x00\x01"),
    ]),
  )
  assert_eq(surface.memories.length(), 1)
  assert_false(surface.memories[0].shared)
  assert_eq(surface.unsupported, [
    "imports[\"env\"][\"g\"]: typed global reference requires structural type normalization",
  ])
}

///|
test "artifact v4 rejects malformed or missing memory metadata" {
  let malformed = [
    b"\x00asm",
    memory_artifact_fixture([(5, b"\x01\x03\x01")]),
    memory_artifact_fixture([(5, b"\x01\x02\x01")]),
    memory_artifact_fixture([(5, b"\x01\x08\x01")]),
    memory_artifact_fixture([
      (5, b"\x01\x01\x05\x02"),
      (7, b"\x01\x03mem\x02\x00"),
    ]),
    memory_artifact_fixture([(7, b"\x01\x03mem\x02\x00")]),
    memory_artifact_fixture([(5, b"\x01\x00\x01"), (7, b"\x01\x03mem\x02\x01")]),
  ]
  for bytes in malformed {
    let rejected = try {
      ignore(project_resource_artifact(bytes))
      false
    } catch {
      InvalidResource(_) => true
    }
    assert_true(rejected)
  }
}
