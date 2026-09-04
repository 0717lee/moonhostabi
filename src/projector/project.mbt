///|
fn typed_ref(
  raw_type_index : Int,
  nullable : Bool,
  canonical_type_indices : Array[Int],
) -> @model.AbiValueType {
  if raw_type_index < 0 || raw_type_index >= canonical_type_indices.length() {
    return @model.Unknown("types[\{raw_type_index}]")
  }
  let canonical_index = canonical_type_indices[raw_type_index]
  if canonical_index < 0 {
    @model.Unknown("types[\{raw_type_index}]")
  } else {
    @model.TypedRef("type[\{canonical_index}]", nullable)
  }
}

///|
fn map_value_type(
  value_type : @wasm_types.ValueType,
  canonical_type_indices : Array[Int],
) -> @model.AbiValueType {
  match value_type {
    I32 => @model.I32
    I64 => @model.I64
    F32 => @model.F32
    F64 => @model.F64
    V128 => @model.V128
    ExternRef | RefExtern => @model.ExternRef
    FuncRef | RefFunc => @model.FuncRef
    RefFuncTyped(type_index) | RefStruct(type_index) | RefArray(type_index) =>
      typed_ref(type_index, false, canonical_type_indices)
    RefNullFuncTyped(type_index)
    | RefNullStruct(type_index)
    | RefNullArray(type_index) =>
      typed_ref(type_index, true, canonical_type_indices)
    AnyRef => @model.Unknown("value_type.anyref")
    ExnRef => @model.Unknown("value_type.exnref")
    StructRef => @model.Unknown("value_type.structref")
    ArrayRef => @model.Unknown("value_type.arrayref")
    RefAny => @model.Unknown("value_type.ref_any")
    RefEq => @model.Unknown("value_type.ref_eq")
    RefNullEq => @model.Unknown("value_type.ref_null_eq")
    RefI31 => @model.Unknown("value_type.ref_i31")
    RefNullI31 => @model.Unknown("value_type.ref_null_i31")
    RefStructAbs => @model.Unknown("value_type.ref_struct")
    RefArrayAbs => @model.Unknown("value_type.ref_array")
    RefNone => @model.Unknown("value_type.ref_none")
    NullRef => @model.Unknown("value_type.nullref")
    NullFuncRef => @model.Unknown("value_type.nullfuncref")
    NullExnRef => @model.Unknown("value_type.nullexnref")
    NullExternRef => @model.Unknown("value_type.nullexternref")
  }
}

///|
fn project_function(
  module_name : String?,
  name : String,
  function_type : @wasm_types.FuncType,
  canonical_type_indices : Array[Int],
) -> @model.AbiFunction {
  @model.AbiFunction::{
    module_name,
    name,
    params: function_type.params.map(fn(value_type) {
      map_value_type(value_type, canonical_type_indices)
    }),
    results: function_type.results.map(fn(value_type) {
      map_value_type(value_type, canonical_type_indices)
    }),
  }
}

///|
fn unresolved_function(
  module_name : String?,
  name : String,
  path : String,
) -> @model.AbiFunction {
  @model.AbiFunction::{
    module_name,
    name,
    params: [@model.Unknown(path)],
    results: [],
  }
}

///|
fn function_type_at_index(
  wasm_module : @wasm_types.Module,
  function_index : Int,
) -> @wasm_types.FuncType? {
  if function_index < 0 {
    return None
  }
  let mut imported_function_count = 0
  for imported in wasm_module.imports {
    match imported.desc {
      Func(type_index) => {
        if imported_function_count == function_index {
          return wasm_module.func_type_at(type_index)
        }
        imported_function_count += 1
      }
      _ => ()
    }
  }
  let defined_index = function_index - imported_function_count
  if defined_index < 0 || defined_index >= wasm_module.funcs.length() {
    return None
  }
  wasm_module.func_type_at(wasm_module.funcs[defined_index])
}

///|
pub fn project_host_abi(wasm_module : @wasm_types.Module) -> @model.HostAbi {
  let canonical_type_indices = @wasm_types.compute_canonical_type_indices(
    wasm_module.types,
    type_rec_groups=wasm_module.type_rec_groups,
  )
  let imports : Array[@model.AbiFunction] = []
  for imported in wasm_module.imports {
    match imported.desc {
      Func(type_index) =>
        match wasm_module.func_type_at(type_index) {
          Some(function_type) =>
            imports.push(
              project_function(
                Some(imported.mod_name),
                imported.name,
                function_type,
                canonical_type_indices,
              ),
            )
          None =>
            imports.push(
              unresolved_function(
                Some(imported.mod_name),
                imported.name,
                "imports[\{imported.mod_name}.\{imported.name}].type[\{type_index}]",
              ),
            )
        }
      _ => ()
    }
  }
  let exports : Array[@model.AbiFunction] = []
  for exported in wasm_module.exports {
    match exported.desc {
      Func(function_index) =>
        match function_type_at_index(wasm_module, function_index) {
          Some(function_type) =>
            exports.push(
              project_function(
                None,
                exported.name,
                function_type,
                canonical_type_indices,
              ),
            )
          None =>
            exports.push(
              unresolved_function(
                None,
                exported.name,
                "exports[\{exported.name}].functions[\{function_index}]",
              ),
            )
        }
      _ => ()
    }
  }
  @model.HostAbi::{
    schema_version: 1,
    imports: @model.sort_abi_functions(imports),
    exports: @model.sort_abi_functions(exports),
    types: [],
    features: [],
  }
}
