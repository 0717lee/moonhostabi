///|
test "contract sources cover every projector resource kind" {
  let resources = [
    @model.AbiResource::{
      module_name: Some("env"),
      name: "memory",
      kind: @model.Memory,
      details: "min=1,max=4,memory64=false,page_size_log2=16",
    },
    @model.AbiResource::{
      module_name: Some("env"),
      name: "table",
      kind: @model.Table,
      details: "elem=externref,min=1,max=none,table64=false",
    },
    @model.AbiResource::{
      module_name: None,
      name: "counter",
      kind: @model.Global,
      details: "value=i32,mutable=true",
    },
    @model.AbiResource::{
      module_name: None,
      name: "error",
      kind: @model.Tag,
      details: "index=0",
    },
  ]
  let analysis = @projector.ProjectionAnalysis::{
    abi: @model.HostAbi::{
      schema_version: 1,
      imports: [],
      exports: [],
      types: [],
      features: [],
    },
    diagnostics: [],
    resources,
  }
  let sources = contract_sources_from_analysis(analysis)
  for source in [sources.memory, sources.table, sources.global, sources.tag] {
    guard source is Some(text) else { fail("expected resource source") }
    ignore(@json.parse(text)) catch {
      _ => fail("expected valid JSON")
    }
    inspect(text.contains("\"schemaVersion\":1"), content="true")
    inspect(text.contains("\"resources\":["), content="true")
  }
  inspect(
    sources.memory.unwrap().contains("\"name\":\"memory\""),
    content="true",
  )
  inspect(sources.table.unwrap().contains("\"kind\":\"table\""), content="true")
  inspect(
    sources.global.unwrap().contains("\"direction\":\"export\""),
    content="true",
  )
  inspect(
    sources.tag.unwrap().contains("\"details\":\"index=0\""),
    content="true",
  )
}

///|
test "contract sources are deterministic and omit empty kinds" {
  let analysis = @projector.ProjectionAnalysis::{
    abi: @model.HostAbi::{
      schema_version: 1,
      imports: [],
      exports: [],
      types: [],
      features: [],
    },
    diagnostics: [],
    resources: [
      @model.AbiResource::{
        module_name: None,
        name: "z",
        kind: @model.Global,
        details: "value=i32,mutable=false",
      },
      @model.AbiResource::{
        module_name: None,
        name: "a",
        kind: @model.Global,
        details: "value=i64,mutable=false",
      },
    ],
  }
  let first = contract_sources_from_analysis(analysis)
  let second = contract_sources_from_analysis(analysis)
  inspect(first == second, content="true")
  inspect(first.memory is None, content="true")
  inspect(first.table is None, content="true")
  inspect(first.tag is None, content="true")
  inspect(first.global.unwrap().contains("\"name\":\"a\""), content="true")
}
