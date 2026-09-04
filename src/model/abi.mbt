///|
pub(all) enum AbiValueType {
  I32
  I64
  F32
  F64
  V128
  ExternRef
  FuncRef
  TypedRef(String, Bool)
  Unknown(String)
} derive(Eq, Debug)

///|
pub fn AbiValueType::stable_text(self : AbiValueType) -> String {
  match self {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    ExternRef => "externref"
    FuncRef => "funcref"
    TypedRef(type_id, nullable) =>
      if nullable {
        "ref null \{type_id}"
      } else {
        "ref \{type_id}"
      }
    Unknown(source) => "unknown(\{source})"
  }
}

///|
pub(all) struct AbiFunction {
  module_name : String?
  name : String
  params : Array[AbiValueType]
  results : Array[AbiValueType]
} derive(Eq, Debug)

///|
pub fn AbiFunction::stable_text(self : AbiFunction) -> String {
  let function_name = match self.module_name {
    Some(module_name) => "func import \{module_name}.\{self.name}"
    None => "func export \{self.name}"
  }
  let params = self.params.map(fn(value) { value.stable_text() }).join(",")
  let results = self.results.map(fn(value) { value.stable_text() }).join(",")
  "\{function_name}(\{params})->(\{results})"
}

///|
pub fn sort_abi_functions(functions : Array[AbiFunction]) -> Array[AbiFunction] {
  let sorted = functions.copy()
  sorted.sort_by(fn(left, right) {
    let module_order = left.module_name
      .unwrap_or("")
      .compare(right.module_name.unwrap_or(""))
    if module_order != 0 {
      module_order
    } else {
      left.name.compare(right.name)
    }
  })
  sorted
}

///|
pub(all) enum AbiStorageType {
  PackedI8
  PackedI16
  Value(AbiValueType)
} derive(Eq, Debug)

///|
pub(all) struct AbiField {
  storage : AbiStorageType
  mutable : Bool
} derive(Eq, Debug)

///|
pub(all) enum AbiTypeDef {
  Struct(String, Array[AbiField])
  Array(String, AbiField)
} derive(Eq, Debug)

///|
pub(all) struct HostAbi {
  schema_version : Int
  imports : Array[AbiFunction]
  exports : Array[AbiFunction]
  types : Array[AbiTypeDef]
  features : Array[String]
} derive(Eq, Debug)
