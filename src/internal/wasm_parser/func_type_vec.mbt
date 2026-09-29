// SPDX-License-Identifier: Apache-2.0
// Vendored from Milky2018/wasm_core@0.14.0, parser/func_type_vec.mbt.
// Upstream: https://github.com/Milky2018/wasmoon
// Modified for MoonHostABI: provenance header only; implementation unchanged.
// License and provenance: third_party/wasm_core_parser/ (repository root).

// ============================================================
// Function Type Parsing
// ============================================================

///|
/// Read a vector of items using a reader function
fn[T] Parser::read_vec(
  self : Parser,
  reader : () -> T raise ParserError,
) -> Array[T] raise ParserError {
  let count = self.read_u32()
  let acc : Array[T] = []
  for _ in 0..<count {
    acc.push(reader())
  }
  acc
}
