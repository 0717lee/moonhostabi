///|
fn resource_projection(
  artifact : Bytes,
) -> @resource.ResourceSurfaceV4 raise CliExecutionError {
  @resource.project_resource_artifact(artifact) catch {
    error => raise CliExecutionError("MHA_RESOURCE_INVALID", error.to_string())
  }
}

///|
// V3 remains a legacy index-based format. Its tag entries must not be treated
// as semantic signature evidence by resource-verify.
fn legacy_resource_surface(
  surface : @resource.ResourceSurfaceV4,
  wasm_module : @wasm_types.Module,
) -> @resource.ResourceSurface {
  let tags : Array[@resource.TagResource] = []
  let tag_indices : Array[Int] = []
  for imported in wasm_module.imports {
    if imported.desc is @wasm_types.Tag(index) {
      tag_indices.push(index)
      tags.push(@resource.TagResource::{
        path: "imports[\{imported.mod_name}.\{imported.name}]",
        module_name: Some(imported.mod_name),
        name: imported.name,
        type_index: index.to_int64(),
      })
    }
  }
  for tag in wasm_module.tags {
    tag_indices.push(tag.type_idx)
  }
  for exported in wasm_module.exports {
    if exported.desc is @wasm_types.Tag(index) &&
      index >= 0 &&
      index < tag_indices.length() {
      tags.push(@resource.TagResource::{
        path: "exports[\{exported.name}]",
        module_name: None,
        name: exported.name,
        type_index: tag_indices[index].to_int64(),
      })
    }
  }
  @resource.ResourceSurface::{
    schema_version: 3,
    memories: surface.memories,
    tables: surface.tables,
    globals: surface.globals,
    tags,
    unsupported: surface.unsupported,
  }
}

///|
fn resource_baseline(
  text : String,
) -> @resource.ResourceSurfaceV4 raise CliExecutionError {
  let root = @json.parse(text) catch {
    error => raise CliExecutionError(MHA_LOCKFILE_INVALID, error.to_string())
  }
  match root {
    { "lockfileVersion": Number(version, ..), .. } =>
      if version == 4.0 {
        let lock = @resource.decode_resource_lockfile_v4(text) catch {
          error =>
            raise CliExecutionError(MHA_LOCKFILE_INVALID, error.to_string())
        }
        lock.abi
      } else if version == 3.0 {
        let lock = @resource.decode_resource_lockfile(text) catch {
          error =>
            raise CliExecutionError(MHA_LOCKFILE_INVALID, error.to_string())
        }
        @resource.lift_legacy_surface(lock.abi)
      } else {
        raise CliExecutionError(
          MHA_LOCKFILE_INVALID,
          "expected resource lockfile version 3 or 4",
        )
      }
    _ =>
      raise CliExecutionError(
        MHA_LOCKFILE_INVALID,
        "missing resource lockfile version",
      )
  }
}

///|
fn resource_contract_for_surface(
  text : String,
  surface : @resource.ResourceSurfaceV4,
) -> @resource.ResourceContractV5 raise CliExecutionError {
  let root = @json.parse(text) catch {
    error => raise CliExecutionError(MHA_CONTRACT_INVALID, error.to_string())
  }
  let decoded = match root {
    { "schemaVersion": Number(version, ..), .. } =>
      if version == 5.0 {
        @resource.decode_resource_contract_v5(text) catch {
          error =>
            raise CliExecutionError(MHA_CONTRACT_INVALID, error.to_string())
        }
      } else if version == 4.0 {
        let legacy = @resource.decode_resource_contract(text) catch {
          error =>
            raise CliExecutionError(MHA_CONTRACT_INVALID, error.to_string())
        }
        let lifted = @resource.lift_legacy_surface(@resource.ResourceSurface::{
          schema_version: 3,
          memories: legacy.memories,
          tables: legacy.tables,
          globals: legacy.globals,
          tags: legacy.tags,
          unsupported: legacy.unsupported,
        })
        if !lifted.unsupported.is_empty() {
          raise CliExecutionError(
            MHA_CONTRACT_INVALID,
            "legacy resource contract lacks semantic type evidence; regenerate with resource-contract",
          )
        }
        @resource.create_resource_contract_v5(lifted)
      } else {
        raise CliExecutionError(
          MHA_CONTRACT_INVALID,
          "expected resource contract version 4 or 5",
        )
      }
    _ =>
      raise CliExecutionError(
        MHA_CONTRACT_INVALID,
        "missing resource contract version",
      )
  }
  if !surface.unsupported.is_empty() ||
    !@resource.validate_resource_contract_v5(surface, decoded) {
    raise CliExecutionError(
      MHA_CONTRACT_INVALID,
      "resource contract does not match the artifact resource surface or contains unsupported types",
    )
  }
  decoded
}
