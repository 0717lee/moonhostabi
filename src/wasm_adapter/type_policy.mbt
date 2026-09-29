///|
fn value_type_needs_canonicalization(
  value_type : @wasm_types.ValueType,
) -> Bool {
  match value_type {
    RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_) => true
    _ => false
  }
}

///|
fn function_type_needs_canonicalization(
  wasm_module : @wasm_types.Module,
  type_index : Int,
) -> Bool {
  if type_index < 0 || type_index >= wasm_module.types.length() {
    return true
  }
  let subtype = wasm_module.types[type_index]
  if !subtype.supertypes.is_empty() {
    return true
  }
  match subtype.composite {
    Func(signature) => {
      for value_type in signature.params {
        if value_type_needs_canonicalization(value_type) {
          return true
        }
      }
      for value_type in signature.results {
        if value_type_needs_canonicalization(value_type) {
          return true
        }
      }
      false
    }
    // A malformed function index pointing at a GC definition must retain the
    // established projection and diagnostic behavior instead of dropping it.
    Struct(_) | Array(_) => true
  }
}

///|
/// Whether function host-ABI projection needs the complete canonical type map.
///
/// `false` proves every imported/exported function root is a function without
/// supertypes or indexed reference values. Such roots reach no GC definitions
/// and their value projections never use a canonical type ID. Private types and
/// non-function resources are deliberately outside this function-ABI predicate.
/// Invalid public indices and GC roots conservatively return `true`.
pub fn host_abi_needs_type_canonicalization(
  wasm_module : @wasm_types.Module,
) -> Bool {
  let function_types : Array[Int] = []
  for imported in wasm_module.imports {
    if imported.desc is Func(type_index) {
      if function_type_needs_canonicalization(wasm_module, type_index) {
        return true
      }
      function_types.push(type_index)
    }
  }
  for type_index in wasm_module.funcs {
    function_types.push(type_index)
  }
  for exported in wasm_module.exports {
    if exported.desc is Func(function_index) {
      if function_index < 0 || function_index >= function_types.length() {
        return true
      }
      if function_type_needs_canonicalization(
          wasm_module,
          function_types[function_index],
        ) {
        return true
      }
    }
  }
  false
}
