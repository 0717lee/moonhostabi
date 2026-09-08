/// Parse compiled Wasm bytes into the reusable Wasm module model.
///
/// The parser does not instantiate or execute the module. Malformed bytes are
/// returned as `ParserError` so callers can fail closed before host setup.

///|
pub fn parse_artifact(
  bytes : Bytes,
) -> @wasm_types.Module raise @wasm_parser.ParserError {
  @wasm_parser.parse_module(bytes)
}
