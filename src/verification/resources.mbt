///|
/// Stable diagnostic codes for changes to non-function host resources.
pub const MHA_RESOURCE_ADDED : String = "MHA_RESOURCE_ADDED"

///|
pub const MHA_RESOURCE_REMOVED : String = "MHA_RESOURCE_REMOVED"

///|
pub const MHA_RESOURCE_CHANGED : String = "MHA_RESOURCE_CHANGED"

///|
/// Compare the resource surface independently from the function ABI surface.
///
/// Resource additions, removals, and contract changes are breaking by default:
/// a host must explicitly account for every table, memory, global, and tag at
/// the boundary. The comparison is deterministic and does not depend on Wasm
/// indices because `stable_text` is derived from the projected surface.
pub fn compare_resources(
  baseline : Array[@model.AbiResource],
  current : Array[@model.AbiResource],
) -> @compat.CompatibilityReport {
  let changes : Array[@compat.AbiChange] = []
  for previous in baseline {
    let mut found = false
    for next in current {
      if previous.module_name == next.module_name &&
        previous.name == next.name &&
        previous.kind == next.kind {
        found = true
        if previous.details != next.details {
          changes.push(@compat.AbiChange::{
            classification: @compat.Breaking,
            code: MHA_RESOURCE_CHANGED,
            path: "resources[\{previous.stable_text()}]",
            message: "resource contract details changed",
          })
        }
      }
    }
    if !found {
      changes.push(@compat.AbiChange::{
        classification: @compat.Breaking,
        code: MHA_RESOURCE_REMOVED,
        path: "resources[\{previous.stable_text()}]",
        message: "host resource was removed",
      })
    }
  }
  for next in current {
    let mut found = false
    for previous in baseline {
      if previous.module_name == next.module_name &&
        previous.name == next.name &&
        previous.kind == next.kind {
        found = true
      }
    }
    if !found {
      changes.push(@compat.AbiChange::{
        classification: @compat.Breaking,
        code: MHA_RESOURCE_ADDED,
        path: "resources[\{next.stable_text()}]",
        message: "host resource was added",
      })
    }
  }
  changes.sort_by(fn(left, right) {
    let path_order = left.path.compare(right.path)
    if path_order != 0 {
      path_order
    } else {
      let code_order = left.code.compare(right.code)
      if code_order != 0 {
        code_order
      } else {
        left.message.compare(right.message)
      }
    }
  })
  {
    classification: if changes.is_empty() {
      @compat.Compatible
    } else {
      @compat.Breaking
    },
    changes,
  }
}

///|
/// Compare resources and return a report only when a baseline was supplied.
pub fn optional_resource_report(
  baseline : Array[@model.AbiResource]?,
  current : Array[@model.AbiResource],
) -> @compat.CompatibilityReport? {
  match baseline {
    Some(value) => Some(compare_resources(value, current))
    None => None
  }
}

///|
test "resource compatibility reports memory table global and tag changes" {
  let baseline = [
    @model.AbiResource::{
      module_name: None,
      name: "memory",
      kind: @model.Memory,
      details: "min=1",
    },
    @model.AbiResource::{
      module_name: None,
      name: "table",
      kind: @model.Table,
      details: "elem=externref,min=1",
    },
    @model.AbiResource::{
      module_name: Some("env"),
      name: "global",
      kind: @model.Global,
      details: "value=i32,mutable=false",
    },
    @model.AbiResource::{
      module_name: Some("env"),
      name: "tag",
      kind: @model.Tag,
      details: "params=()",
    },
  ]
  let current = [
    @model.AbiResource::{
      module_name: None,
      name: "memory",
      kind: @model.Memory,
      details: "min=2",
    },
    @model.AbiResource::{
      module_name: None,
      name: "table",
      kind: @model.Table,
      details: "elem=externref,min=1",
    },
    @model.AbiResource::{
      module_name: Some("env"),
      name: "global2",
      kind: @model.Global,
      details: "value=i64,mutable=true",
    },
    @model.AbiResource::{
      module_name: Some("env"),
      name: "tag",
      kind: @model.Tag,
      details: "params=(i32)",
    },
  ]
  let report = compare_resources(baseline, current)
  inspect(report.classification == @compat.Breaking, content="true")
  inspect(report.changes.length(), content="4")
  inspect(report.changes[0].code, content="MHA_RESOURCE_CHANGED")
  inspect(
    report.changes
    .map(fn(change) { change.code })
    .contains(MHA_RESOURCE_REMOVED),
    content="true",
  )
  inspect(
    report.changes.map(fn(change) { change.code }).contains(MHA_RESOURCE_ADDED),
    content="true",
  )
}

///|
test "unchanged resources are compatible and empty" {
  let resources : Array[@model.AbiResource] = []
  let report = compare_resources(resources, resources)
  inspect(report.classification == @compat.Compatible, content="true")
  inspect(report.changes.length(), content="0")
}
