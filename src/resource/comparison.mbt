///|
pub(all) struct ResourceChange {
  path : String
  before : String?
  after : String?
  classification : String
  recommendation : String
} derive(Eq, Debug)

///|
pub(all) struct ResourceComparison {
  schema_version : Int
  classification : String
  compatible : Bool
  exit_code : Int
  changes : Array[ResourceChange]
} derive(Eq, Debug)

///|
fn resource_fields(surface : ResourceSurfaceV4) -> Map[String, String] {
  let fields : Map[String, String] = Map([])
  for value in surface.memories {
    let path = "memories[\{json_string(value.path)}]"
    fields["\{path}.minimumPages"] = "\{value.minimum_pages}"
    fields["\{path}.maximumPages"] = json_optional_i64(value.maximum_pages)
    fields["\{path}.shared"] = json_bool(value.shared)
    fields["\{path}.memory64"] = json_bool(value.memory64)
    fields["\{path}.pageSizeLog2"] = "\{value.page_size_log2}"
  }
  for value in surface.tables {
    let path = "tables[\{json_string(value.path)}]"
    fields["\{path}.elementType"] = json_string(value.element_type)
    fields["\{path}.minimumElements"] = "\{value.minimum_elements}"
    fields["\{path}.maximumElements"] = json_optional_i64(
      value.maximum_elements,
    )
    fields["\{path}.table64"] = json_bool(value.table64)
  }
  for value in surface.globals {
    let path = "globals[\{json_string(value.path)}]"
    fields["\{path}.valueType"] = json_string(value.value_type)
    fields["\{path}.mutable"] = json_bool(value.mutable)
  }
  for value in surface.tags {
    let path = "tags[\{json_string(value.path)}]"
    fields["\{path}.params"] = encode_type_sequence(value.params)
    fields["\{path}.results"] = encode_type_sequence(value.results)
  }
  fields
}

///|
/// Conservatively classify any resource change as breaking. Unsupported or
/// malformed surfaces have unknown compatibility, even when fingerprints match.
pub fn compare_resource_surfaces(
  before : ResourceSurfaceV4,
  after : ResourceSurfaceV4,
) -> ResourceComparison {
  let changes : Array[ResourceChange] = []
  let mut unknown = false
  for entry in [("before", before), ("after", after)] {
    let (label, surface) = entry
    validate_surface_v4(surface) catch {
      error => {
        unknown = true
        changes.push({
          path: label,
          before: None,
          after: Some(json_string(Show::to_string(error))),
          classification: "unknown",
          recommendation: "Regenerate a valid resource lock from the original Wasm artifact.",
        })
      }
    }
  }
  if !before.unsupported.is_empty() || !after.unsupported.is_empty() {
    unknown = true
    changes.push({
      path: "unsupported",
      before: Some(encode_strings(before.unsupported)),
      after: Some(encode_strings(after.unsupported)),
      classification: "unknown",
      recommendation: "Resolve unsupported resource metadata before accepting compatibility.",
    })
  }
  let old_fields = resource_fields(before)
  let new_fields = resource_fields(after)
  let all_paths : Map[String, Bool] = Map([])
  for key, _ in old_fields {
    all_paths[key] = true
  }
  for key, _ in new_fields {
    all_paths[key] = true
  }
  for path, _ in all_paths {
    let old_value = old_fields.get(path)
    let new_value = new_fields.get(path)
    if old_value != new_value {
      changes.push({
        path,
        before: old_value,
        after: new_value,
        classification: "breaking",
        recommendation: "Review the host resource binding and regenerate its contract before deployment.",
      })
    }
  }
  changes.sort_by(fn(left, right) { left.path.compare(right.path) })
  let classification = if unknown {
    "unknown"
  } else if changes.is_empty() {
    "compatible"
  } else {
    "breaking"
  }
  {
    schema_version: 1,
    classification,
    compatible: classification == "compatible",
    exit_code: if unknown {
      3
    } else if changes.is_empty() {
      0
    } else {
      2
    },
    changes,
  }
}

///|
fn json_optional_string(value : String?) -> String {
  match value {
    Some(value) => json_string(value)
    None => "null"
  }
}

///|
pub fn encode_resource_comparison(report : ResourceComparison) -> String {
  let changes = report.changes
    .map(fn(change) {
      "{\"path\":\{json_string(change.path)},\"before\":\{json_optional_string(change.before)},\"after\":\{json_optional_string(change.after)},\"classification\":\{json_string(change.classification)},\"recommendation\":\{json_string(change.recommendation)}}"
    })
    .join(",")
  "{\"schemaVersion\":\{report.schema_version},\"classification\":\{json_string(report.classification)},\"compatible\":\{json_bool(report.compatible)},\"exitCode\":\{report.exit_code},\"changes\":[\{changes}]}"
}

///|
fn display_value(value : String?) -> String {
  match value {
    Some(value) => value
    None => "(absent)"
  }
}

///|
pub fn render_resource_comparison_text(report : ResourceComparison) -> String {
  let rows = [
    "resource compatibility: \{report.classification} (exit \{report.exit_code})",
  ]
  for change in report.changes {
    rows.push(
      "\{change.path}: \{display_value(change.before)} -> \{display_value(change.after)} [\{change.classification}]",
    )
    rows.push("  \{change.recommendation}")
  }
  rows.join("\n") + "\n"
}

///|
fn markdown_cell(value : String) -> String {
  value
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="|", new="&#124;")
  .replace(old="`", new="&#96;")
  .replace(old="\r", new="&#13;")
  .replace(old="\n", new="&#10;")
  .replace(old="\\", new="&#92;")
}

///|
pub fn render_resource_comparison_markdown(
  report : ResourceComparison,
) -> String {
  let rows = [
    "Resource compatibility: **\{report.classification}** (exit \{report.exit_code}).",
  ]
  if !report.changes.is_empty() {
    rows.push("")
    rows.push("| Field | Before | After | Classification | Recommendation |")
    rows.push("| --- | --- | --- | --- | --- |")
    for change in report.changes {
      rows.push(
        "| \{markdown_cell(change.path)} | \{markdown_cell(display_value(change.before))} | \{markdown_cell(display_value(change.after))} | \{markdown_cell(change.classification)} | \{markdown_cell(change.recommendation)} |",
      )
    }
  }
  rows.join("\n") + "\n"
}

///|
fn legacy_value_type(value : String) -> String? {
  match value {
    "I32" => Some("i32")
    "I64" => Some("i64")
    "F32" => Some("f32")
    "F64" => Some("f64")
    "V128" => Some("v128")
    "FuncRef" => Some("funcref")
    "ExternRef" => Some("externref")
    "RefFunc" => Some("(ref func)")
    "RefExtern" => Some("(ref extern)")
    _ => if valid_resource_type(value) { Some(value) } else { None }
  }
}

///|
/// Lift legacy identities and known value spellings without inventing missing
/// exception signatures. Legacy tags or unknown descriptors remain unsupported.
pub fn lift_legacy_surface(surface : ResourceSurface) -> ResourceSurfaceV4 {
  let lifted : ResourceSurfaceV4 = {
    schema_version: 4,
    memories: [],
    tables: [],
    globals: [],
    tags: [],
    unsupported: surface.unsupported.copy(),
  }
  if surface.schema_version != 3 {
    lifted.unsupported.push("legacy surface: expected schema version 3")
  }
  for value in surface.memories {
    lifted.memories.push({
      ..value,
      path: resource_path(value.module_name, value.name),
    })
  }
  for value in surface.tables {
    let path = resource_path(value.module_name, value.name)
    match legacy_value_type(value.element_type) {
      Some(element_type) => lifted.tables.push({ ..value, path, element_type, })
      None =>
        lifted.unsupported.push(
          "\{path}: legacy table element type cannot be normalized",
        )
    }
  }
  for value in surface.globals {
    let path = resource_path(value.module_name, value.name)
    match legacy_value_type(value.value_type) {
      Some(value_type) => lifted.globals.push({ ..value, path, value_type, })
      None =>
        lifted.unsupported.push(
          "\{path}: legacy global value type cannot be normalized",
        )
    }
  }
  for value in surface.tags {
    lifted.unsupported.push(
      "\{resource_path(value.module_name, value.name)}: legacy tag signature unavailable",
    )
  }
  lifted
}
