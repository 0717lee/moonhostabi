# Resource contract sources

`@resource.contract_sources_from_analysis` converts a
`@projector.ProjectionAnalysis` resource inventory into deterministic JSON
documents for `memory`, `table`, `global`, and `tag`. Empty kinds are omitted.

The helper uses the JSON AST and includes the projector's stable resource
details, so callers do not need to concatenate JSON strings or duplicate the
Wasm resource classification rules. Each document has this shape:

```json
{
  "schemaVersion": 1,
  "kind": "memory",
  "resources": [
    {
      "direction": "import",
      "module": "env",
      "name": "memory",
      "kind": "memory",
      "details": "min=1,max=4,memory64=false,page_size_log2=16"
    }
  ]
}
```

For an exported resource, `direction` is `export` and `module` is `null`.
The returned record has optional strings (`memory`, `table`, `global`, and
`tag`) and can be adapted to the opaque resource source input of the
TypeScript adapter generator. Runtime packages remain responsible for
validating each kind's contract semantics.
