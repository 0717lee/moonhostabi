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
  let cases = [
    (@model.Memory, "memory", "min=1,max=4,memory64=false,page_size_log2=16"),
    (@model.Table, "table", "elem=externref,min=1,max=none,table64=false"),
    (@model.Global, "global", "value=i32,mutable=false"),
    (@model.Tag, "tag", "index=0"),
  ]
  for case in cases {
    let (kind, label, details) = case
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
        @model.AbiResource::{ module_name: None, name: "z", kind, details, },
        @model.AbiResource::{ module_name: None, name: "a", kind, details, },
      ],
    }
    let first = contract_sources_from_analysis(analysis)
    let reversed_analysis = @projector.ProjectionAnalysis::{
      abi: analysis.abi,
      diagnostics: analysis.diagnostics,
      resources: [analysis.resources[1], analysis.resources[0]],
    }
    let reversed = contract_sources_from_analysis(reversed_analysis)
    inspect(
      (first.memory is Some(_)) == (kind == @model.Memory),
      content="true",
    )
    inspect((first.table is Some(_)) == (kind == @model.Table), content="true")
    inspect(
      (first.global is Some(_)) == (kind == @model.Global),
      content="true",
    )
    inspect((first.tag is Some(_)) == (kind == @model.Tag), content="true")
    let source = match kind {
      @model.Memory => first.memory.unwrap()
      @model.Table => first.table.unwrap()
      @model.Global => first.global.unwrap()
      @model.Tag => first.tag.unwrap()
    }
    let expected = "{\"schemaVersion\":1,\"kind\":\"\{label}\",\"resources\":[{\"direction\":\"export\",\"module\":null,\"name\":\"a\",\"kind\":\"\{label}\",\"details\":\"\{details}\"},{\"direction\":\"export\",\"module\":null,\"name\":\"z\",\"kind\":\"\{label}\",\"details\":\"\{details}\"}]}"
    inspect(source, content=expected)
    inspect(first == reversed, content="true")
  }
}
