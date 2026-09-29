// SPDX-License-Identifier: Apache-2.0
// Vendored from Milky2018/wasm_core@0.14.0, parser/trait_extensions.mbt.
// Upstream: https://github.com/Milky2018/wasmoon
// Modified for MoonHostABI: provenance header only; implementation unchanged.
// License and provenance: third_party/wasm_core_parser/ (repository root).

///|
pub extend Parser with Debug::{to_repr}

///|
pub extend ParserError with Show::{to_string, output}
