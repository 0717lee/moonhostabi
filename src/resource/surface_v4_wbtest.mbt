///|
fn resource_test_module(
  param : @wasm_types.ValueType,
  offset : Bool,
) -> @wasm_types.Module {
  let wasm = @wasm_types.Module::Module()
  if offset {
    wasm.types.push(@wasm_types.SubType::func([], []))
  }
  wasm.types.push(@wasm_types.SubType::func([param], []))
  wasm.tables.push({
    type_: {
      elem_type: ExternRef,
      limits: { min: 2L, max: Some(8L), },
      is_table64: false,
    },
    init: None,
  })
  wasm.globals.push({ type_: { value_type: I64, mutable: true, }, init: [], })
  wasm.tags.push({ type_idx: if offset { 1 } else { 0 }, })
  wasm.exports.push({ name: "table", desc: @wasm_types.ExportDesc::Table(0), })
  wasm.exports.push({
    name: "counter",
    desc: @wasm_types.ExportDesc::Global(0),
  })
  wasm.exports.push({ name: "fail", desc: @wasm_types.ExportDesc::Tag(0), })
  wasm
}

///|
test "surface v4 retains defined export metadata" {
  let surface = project_resource_surface(resource_test_module(I32, false))
  assert_eq(surface.tables[0].element_type, "externref")
  assert_eq(surface.tables[0].minimum_elements, 2L)
  assert_eq(surface.globals[0].value_type, "i64")
  assert_true(surface.globals[0].mutable)
  assert_eq(surface.tags[0].params, ["i32"])
}

///|
test "surface v4 detects same-index tag changes and ignores type renumbering" {
  let before = project_resource_surface(resource_test_module(I32, false))
  let changed = project_resource_surface(resource_test_module(I64, false))
  let renumbered = project_resource_surface(resource_test_module(I32, true))
  assert_not_eq(
    resource_surface_v4_sha256(before),
    resource_surface_v4_sha256(changed),
  )
  assert_eq(
    resource_surface_v4_sha256(before),
    resource_surface_v4_sha256(renumbered),
  )
}

///|
test "surface v4 codec round trips contracts and locks" {
  let surface = project_resource_surface(resource_test_module(I32, false))
  let lockfile = create_resource_lockfile_v4(surface, b"artifact")
  let contract = create_resource_contract_v5(surface)
  assert_eq(
    decode_resource_lockfile_v4(encode_resource_lockfile_v4(lockfile)),
    lockfile,
  )
  assert_eq(
    decode_resource_contract_v5(encode_resource_contract_v5(contract)),
    contract,
  )
  assert_true(validate_resource_contract_v5(surface, contract))
  let changed = project_resource_surface(resource_test_module(I64, false))
  assert_false(validate_resource_contract_v5(changed, contract))
}

///|
fn expect_v4_lock_rejected(text : String) -> Unit raise {
  assert_true(
    try {
      ignore(decode_resource_lockfile_v4(text))
      false
    } catch {
      _ => true
    },
  )
}

///|
fn expect_v4_surface_rejected(surface : ResourceSurfaceV4) -> Unit raise {
  expect_v4_lock_rejected(
    encode_resource_lockfile_v4(
      create_resource_lockfile_v4(surface, b"artifact"),
    ),
  )
  assert_true(
    try {
      ignore(
        decode_resource_contract_v5(
          encode_resource_contract_v5(create_resource_contract_v5(surface)),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(compare_resource_surfaces(surface, surface).exit_code, 3)
}

///|
test "surface v4 rejects noncanonical documents fields hashes and numbers" {
  let surface = project_resource_surface(resource_test_module(I32, false))
  let lockfile = create_resource_lockfile_v4(surface, b"artifact")
  let encoded = encode_resource_lockfile_v4(lockfile)
  expect_v4_lock_rejected(encoded + " ")
  expect_v4_lock_rejected(
    encoded.replace(old="\"lockfileVersion\":4", new="\"lockfileVersion\":4.0"),
  )
  expect_v4_lock_rejected(
    encoded.replace(old="\"minimumElements\":2", new="\"minimumElements\":2e0"),
  )
  expect_v4_lock_rejected(
    encoded.replace(old="\"minimumElements\":2", new="\"minimumElements\":2.5"),
  )
  expect_v4_lock_rejected(
    encoded.replace(
      old="\"minimumElements\":2",
      new="\"minimumElements\":9223372036854775808",
    ),
  )
  expect_v4_lock_rejected(
    encoded.replace(old="\"minimumElements\":2", new="\"minimumElements\":-0"),
  )
  expect_v4_lock_rejected(
    encoded.replace(
      old="\"minimumElements\":2",
      new="\"minimumElements\":2,\"extra\":true",
    ),
  )
  expect_v4_lock_rejected(
    encoded.replace(
      old="\"minimumElements\":2",
      new="\"minimumElements\":2,\"minimumElements\":2",
    ),
  )
  expect_v4_lock_rejected(
    encoded.replace(old=lockfile.artifact_sha256, new="invalid"),
  )
  expect_v4_lock_rejected(
    encoded.replace(old=lockfile.abi_sha256, new=sha256_text("wrong")),
  )
  expect_v4_lock_rejected(
    encoded.replace(old=lockfile.schema_sha256, new=sha256_text("wrong schema")),
  )
  expect_v4_lock_rejected(encoded.replace(old="\"tables\":", new="\"TABLES\":"))
  let contract = create_resource_contract_v5(surface)
  assert_true(
    try {
      ignore(
        decode_resource_contract_v5(
          encode_resource_contract_v5(contract).replace(
            old=contract.abi_sha256,
            new=sha256_text("wrong"),
          ),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "surface v4 rejects invalid paths duplicate identities types and limits" {
  let surface = project_resource_surface(resource_test_module(I32, false))
  let table = surface.tables[0]
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, path: "exports[table]", }],
  })
  expect_v4_surface_rejected({ ..surface, tables: [table, table], })
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, minimum_elements: -1L, }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, maximum_elements: Some(1L), }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, maximum_elements: Some(4294967296L), }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, element_type: "unknown", }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tables: [{ ..table, element_type: "i32", }],
  })
  expect_v4_surface_rejected({
    ..surface,
    globals: [{ ..surface.globals[0], value_type: "I64", }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tags: [{ ..surface.tags[0], params: ["RefStruct(0)"], }],
  })
  expect_v4_surface_rejected({
    ..surface,
    tags: [{ ..surface.tags[0], results: ["i32"], }],
  })
  expect_v4_surface_rejected({ ..surface, unsupported: ["same", "same"], })
  expect_v4_surface_rejected({ ..surface, unsupported: [""], })
}

///|
test "surface v4 memory validation and exact 64-bit integers" {
  let memory : MemoryResource = {
    path: resource_path(None, "memory"),
    module_name: None,
    name: "memory",
    minimum_pages: 1L,
    maximum_pages: Some(2L),
    shared: false,
    memory64: false,
    page_size_log2: 16,
  }
  let surface : ResourceSurfaceV4 = {
    schema_version: 4,
    memories: [memory],
    tables: [],
    globals: [],
    tags: [],
    unsupported: [],
  }
  let contract = create_resource_contract_v5(surface)
  assert_eq(
    decode_resource_contract_v5(encode_resource_contract_v5(contract)),
    contract,
  )
  expect_v4_surface_rejected({
    ..surface,
    memories: [{ ..memory, minimum_pages: -1L, }],
  })
  expect_v4_surface_rejected({
    ..surface,
    memories: [{ ..memory, maximum_pages: Some(0L), }],
  })
  expect_v4_surface_rejected({
    ..surface,
    memories: [{ ..memory, maximum_pages: Some(65537L), }],
  })
  expect_v4_surface_rejected({
    ..surface,
    memories: [{ ..memory, shared: true, maximum_pages: None, }],
  })
  expect_v4_surface_rejected({
    ..surface,
    memories: [{ ..memory, page_size_log2: 31, }],
  })
  let table : TableResource = {
    path: resource_path(None, "wide"),
    module_name: None,
    name: "wide",
    element_type: "funcref",
    minimum_elements: 9007199254740993L,
    maximum_elements: Some(9223372036854775807L),
    table64: true,
  }
  let wide = create_resource_lockfile_v4(
    { ..surface, tables: [table], },
    b"wide",
  )
  assert_eq(
    decode_resource_lockfile_v4(encode_resource_lockfile_v4(wide)),
    wide,
  )
}

///|
test "surface v4 projections resolve imported reexports and independent indices" {
  let wasm = resource_test_module(I32, false)
  wasm.imports.push({
    mod_name: "env",
    name: "function",
    desc: @wasm_types.ImportDesc::Func(0),
  })
  wasm.imports.push({
    mod_name: "env",
    name: "table",
    desc: @wasm_types.ImportDesc::Table({
      elem_type: FuncRef,
      limits: { min: 4L, max: Some(6L), },
      is_table64: false,
    }),
  })
  wasm.imports.push({
    mod_name: "env",
    name: "global",
    desc: @wasm_types.ImportDesc::Global({ value_type: F64, mutable: false, }),
  })
  wasm.types.push(@wasm_types.SubType::func([I64], []))
  wasm.imports.push({
    mod_name: "env",
    name: "tag",
    desc: @wasm_types.ImportDesc::Tag(1),
  })
  // Existing exports at index zero now re-export the imported resources.
  wasm.exports.push({
    name: "defined-table",
    desc: @wasm_types.ExportDesc::Table(1),
  })
  wasm.exports.push({
    name: "defined-global",
    desc: @wasm_types.ExportDesc::Global(1),
  })
  wasm.exports.push({
    name: "defined-tag",
    desc: @wasm_types.ExportDesc::Tag(1),
  })
  let surface = project_resource_surface(wasm)
  assert_eq(surface.tables[1].element_type, "funcref")
  assert_eq(surface.tables[1].minimum_elements, 4L)
  assert_eq(surface.tables[2].element_type, "externref")
  assert_eq(surface.globals[1].value_type, "f64")
  assert_eq(surface.globals[2].value_type, "i64")
  assert_eq(surface.tags[1].params, ["i64"])
  assert_eq(surface.tags[2].params, ["i32"])
}

///|
test "surface v4 rejects invalid indices and tag signatures" {
  let wasm = @wasm_types.Module::Module()
  wasm.exports.push({ name: "bad", desc: @wasm_types.ExportDesc::Table(0), })
  assert_true(
    try {
      ignore(project_resource_surface(wasm))
      false
    } catch {
      _ => true
    },
  )
  wasm.exports.clear()
  wasm.exports.push({ name: "bad", desc: @wasm_types.ExportDesc::Global(-1), })
  assert_true(
    try {
      ignore(project_resource_surface(wasm))
      false
    } catch {
      _ => true
    },
  )
  wasm.exports.clear()
  wasm.imports.push({
    mod_name: "env",
    name: "tag",
    desc: @wasm_types.ImportDesc::Tag(0),
  })
  assert_true(
    try {
      ignore(project_resource_surface(wasm))
      false
    } catch {
      _ => true
    },
  )
  wasm.types.push(@wasm_types.SubType::func([], [I32]))
  assert_true(
    try {
      ignore(project_resource_surface(wasm))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "surface v4 unsupported resources remain unknown" {
  let wasm = @wasm_types.Module::Module()
  wasm.imports.push({
    mod_name: "env",
    name: "table",
    desc: @wasm_types.ImportDesc::Table({
      elem_type: RefNullStruct(0),
      limits: { min: 0L, max: None, },
      is_table64: false,
    }),
  })
  wasm.imports.push({
    mod_name: "env",
    name: "global",
    desc: @wasm_types.ImportDesc::Global({
      value_type: RefNullArray(0),
      mutable: false,
    }),
  })
  wasm.types.push(@wasm_types.SubType::func([RefNullFuncTyped(0)], []))
  wasm.imports.push({
    mod_name: "env",
    name: "tag",
    desc: @wasm_types.ImportDesc::Tag(0),
  })
  wasm.imports.push({
    mod_name: "env",
    name: "memory",
    desc: @wasm_types.ImportDesc::Memory({
      limits: { min: 1L, max: None, },
      is_memory64: false,
      page_size_log2: 16,
    }),
  })
  let surface = project_resource_surface(wasm)
  assert_eq(surface.unsupported.length(), 4)
  assert_eq(surface.memories.length(), 0)
  assert_eq(surface.tables.length(), 0)
  assert_eq(surface.globals.length(), 0)
  assert_eq(surface.tags.length(), 0)
  let report = compare_resource_surfaces(surface, surface)
  assert_eq(report.classification, "unknown")
  assert_eq(report.exit_code, 3)
  assert_false(
    validate_resource_contract_v5(surface, create_resource_contract_v5(surface)),
  )
}

///|
test "surface v4 resource identity is unambiguous and accepts empty wasm names" {
  let wasm = @wasm_types.Module::Module()
  for entry in [("a.b", "c"), ("a", "b.c"), ("", "")] {
    let (module_name, name) = entry
    wasm.imports.push({
      mod_name: module_name,
      name,
      desc: @wasm_types.ImportDesc::Global({ value_type: I32, mutable: false, }),
    })
  }
  let surface = project_resource_surface(wasm)
  assert_not_eq(surface.globals[0].path, surface.globals[1].path)
  let lockfile = create_resource_lockfile_v4(surface, b"identity")
  let decoded = decode_resource_lockfile_v4(
    encode_resource_lockfile_v4(lockfile),
  )
  assert_eq(
    encode_resource_surface_v4(decoded.abi),
    encode_resource_surface_v4(surface),
  )
  wasm.imports.push(wasm.imports[0])
  assert_true(
    try {
      ignore(project_resource_surface(wasm))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "resource comparison reports stable fields values and conservative classes" {
  let before = project_resource_surface(resource_test_module(I32, false))
  let after = project_resource_surface(resource_test_module(I64, false))
  let report = compare_resource_surfaces(before, after)
  assert_eq(report.exit_code, 2)
  assert_eq(report.changes.length(), 1)
  assert_eq(report.changes[0].path, "tags[\"exports[\\\"fail\\\"]\"].params")
  assert_eq(report.changes[0].before, Some("[\"i32\"]"))
  assert_eq(report.changes[0].after, Some("[\"i64\"]"))
  assert_true(
    encode_resource_comparison(report).contains(
      "\"classification\":\"breaking\"",
    ),
  )
  assert_true(render_resource_comparison_text(report).contains("[breaking]"))
  assert_true(
    render_resource_comparison_markdown(report).contains(
      "| Field | Before | After |",
    ),
  )
  assert_eq(compare_resource_surfaces(before, before).exit_code, 0)
  let renamed : ResourceSurfaceV4 = {
    ..before,
    tags: [{ ..before.tags[0], name: "new", path: resource_path(None, "new"), }],
  }
  assert_eq(compare_resource_surfaces(before, renamed).exit_code, 2)
  let uncertain : ResourceSurfaceV4 = {
    ..after,
    unsupported: ["unsupported GC type"],
  }
  assert_eq(compare_resource_surfaces(before, uncertain).exit_code, 3)
  let escaped : ResourceComparison = {
    schema_version: 1,
    classification: "breaking",
    compatible: false,
    exit_code: 2,
    changes: [
      {
        path: "a|b`\n<c>",
        before: Some("\r"),
        after: None,
        classification: "breaking",
        recommendation: "check|it",
      },
    ],
  }
  let markdown = render_resource_comparison_markdown(escaped)
  assert_true(markdown.contains("a&#124;b&#96;&#10;&lt;c&gt;"))
  assert_true(markdown.contains("check&#124;it"))
}

///|
test "legacy lift normalizes identities and refuses missing tag signatures" {
  let legacy : ResourceSurface = {
    schema_version: 3,
    memories: [],
    tables: [
      {
        path: "imports[env.table]",
        module_name: Some("env"),
        name: "table",
        element_type: "ExternRef",
        minimum_elements: 1L,
        maximum_elements: None,
        table64: false,
      },
    ],
    globals: [],
    tags: [],
    unsupported: [],
  }
  let lifted = lift_legacy_surface(legacy)
  assert_eq(lifted.tables[0].path, resource_path(Some("env"), "table"))
  assert_eq(lifted.tables[0].element_type, "externref")
  assert_eq(compare_resource_surfaces(lifted, lifted).exit_code, 0)
  let missing = lift_legacy_surface({
    ..legacy,
    tags: [
      {
        path: "exports[fail]",
        module_name: None,
        name: "fail",
        type_index: 0L,
      },
    ],
  })
  assert_eq(compare_resource_surfaces(missing, missing).exit_code, 3)
  let unknown = lift_legacy_surface({
    ..legacy,
    tables: [{ ..legacy.tables[0], element_type: "unknown", }],
  })
  assert_eq(compare_resource_surfaces(unknown, unknown).exit_code, 3)
  // Legacy wire encodings retain their historical schema and type-index field.
  assert_true(
    encode_resource_lockfile(
      create_resource_lockfile(
        {
          ..legacy,
          tags: [
            {
              path: "exports[fail]",
              module_name: None,
              name: "fail",
              type_index: 0L,
            },
          ],
        },
        b"old",
      ),
    ).contains("\"typeIndex\":0"),
  )
}
