///|
/// Contract JSON sources generated from the projector resource inventory.
///
/// The generator package intentionally keeps these payloads opaque so a host
/// runtime can provide its own guard implementation. This helper provides a
/// stable, structured payload for every resource kind without requiring
/// callers to hand-build JSON strings.
pub(all) struct ResourceContractSources {
  memory : String?
  table : String?
  global : String?
  tag : String?
} derive(Eq, Debug)

///|
fn resource_kind_text(kind : @model.AbiResourceKind) -> String {
  match kind {
    @model.Table => "table"
    @model.Memory => "memory"
    @model.Global => "global"
    @model.Tag => "tag"
  }
}

///|
fn resource_direction(resource : @model.AbiResource) -> String {
  match resource.module_name {
    Some(_) => "import"
    None => "export"
  }
}

///|
fn resource_json(resource : @model.AbiResource) -> Json {
  let module_json = match resource.module_name {
    Some(value) => Json::string(value)
    None => Json::null()
  }
  Json::object({
    "direction": Json::string(resource_direction(resource)),
    "module": module_json,
    "name": Json::string(resource.name),
    "kind": Json::string(resource_kind_text(resource.kind)),
    "details": Json::string(resource.details),
  })
}

///|
fn contract_json(
  kind : String,
  resources : Array[@model.AbiResource],
) -> String? {
  if resources.is_empty() {
    return None
  }
  let entries = resources.map(resource_json)
  Some(
    Json::object({
      "schemaVersion": Json::number(1),
      "kind": Json::string(kind),
      "resources": Json::array(entries),
    }).stringify(),
  )
}

///|
/// Build deterministic JSON contract sources from a projection analysis.
///
/// Each non-empty resource kind is emitted as an independent document. The
/// documents contain direction, module, name, kind, and the projector's
/// stable details text. They are suitable as the opaque inputs accepted by
/// `generate_typescript_adapter_with_resources` after adapting the returned
/// record to that package's source type.
pub fn contract_sources_from_analysis(
  analysis : @projector.ProjectionAnalysis,
) -> ResourceContractSources {
  let memories : Array[@model.AbiResource] = []
  let tables : Array[@model.AbiResource] = []
  let globals : Array[@model.AbiResource] = []
  let tags : Array[@model.AbiResource] = []
  for resource in analysis.resources {
    match resource.kind {
      @model.Memory => memories.push(resource)
      @model.Table => tables.push(resource)
      @model.Global => globals.push(resource)
      @model.Tag => tags.push(resource)
    }
  }
  memories.sort_by(fn(left, right) {
    left.stable_text().compare(right.stable_text())
  })
  tables.sort_by(fn(left, right) {
    left.stable_text().compare(right.stable_text())
  })
  globals.sort_by(fn(left, right) {
    left.stable_text().compare(right.stable_text())
  })
  tags.sort_by(fn(left, right) {
    left.stable_text().compare(right.stable_text())
  })
  ResourceContractSources::{
    memory: contract_json("memory", memories),
    table: contract_json("table", tables),
    global: contract_json("global", globals),
    tag: contract_json("tag", tags),
  }
}
