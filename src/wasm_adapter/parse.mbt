/// Parse compiled Wasm bytes into the reusable Wasm module model.
///
/// The parser does not instantiate or execute the module. Malformed bytes are
/// returned as `ArtifactError::InvalidArtifact` so callers can fail closed.
/// This unbounded entrypoint requires trusted, caller-budgeted input;
/// use `parse_artifact_checked` for the structural resource policy.

///|
pub fn parse_artifact(bytes : Bytes) -> @wasm_types.Module raise ArtifactError {
  @wasm_parser.parse_module(bytes) catch {
    error => raise InvalidArtifact(error.to_string())
  }
}

///|
/// A checked artifact either exceeds this adapter's resource policy or is invalid.
pub(all) suberror ArtifactError {
  LimitExceeded(String)
  InvalidArtifact(String)
} derive(Debug)

///|
pub extend ArtifactError with @debug.Debug::{to_repr}

///|
pub extend ArtifactError with Show::{to_string, output}

///|
pub impl Show for ArtifactError with fn output(self, logger) {
  match self {
    LimitExceeded(reason) =>
      logger.write_string("artifact limit exceeded: \{reason}")
    InvalidArtifact(reason) =>
      logger.write_string("invalid artifact: \{reason}")
  }
}

///|
/// Parse an artifact with a bounded structural preflight before allocating its AST.
///
/// Fixed limits cover input bytes, declared items and types, expanded locals,
/// instruction count, control nesting, and expanded public function/tag signatures.
/// The signature budget is checked after bounded AST parsing, before projection.
/// `LimitExceeded` denotes this policy; `InvalidArtifact` wraps structural or
/// upstream parse errors. This is a parsing boundary, not Wasm semantic validation.
pub fn parse_artifact_checked(
  bytes : Bytes,
) -> @wasm_types.Module raise ArtifactError {
  preflight_artifact(bytes, preflight_limits())
  let parsed = parse_artifact(bytes)
  check_public_signature_budget(parsed, 131072)
  // Keep the lower bound on the expensive whole-module canonicalizer. Modules
  // whose public functions need no canonical IDs may have more private types.
  if parsed.types.length() > 1024 &&
    host_abi_needs_type_canonicalization(parsed) {
    raise LimitExceeded("canonicalization types")
  }
  parsed
}

///|
fn check_public_signature_budget(
  parsed : @wasm_types.Module,
  limit : Int,
) -> Unit raise ArtifactError {
  // Many exports may reference one wide signature. Bound the expanded public
  // surface before the projector copies its slots for every import/export.
  let function_types : Array[Int] = []
  let tag_types : Array[Int] = []
  let mut slots = 0
  for import_ in parsed.imports {
    let type_idx = match import_.desc {
      Func(type_idx) => {
        function_types.push(type_idx)
        type_idx
      }
      Tag(type_idx) => {
        tag_types.push(type_idx)
        type_idx
      }
      _ => continue
    }
    slots = bounded_add(
      slots,
      signature_slots(parsed, type_idx).to_int64(),
      limit,
      "public signature slots",
    )
  }
  for type_idx in parsed.funcs {
    function_types.push(type_idx)
  }
  for tag in parsed.tags {
    tag_types.push(tag.type_idx)
  }
  for export_ in parsed.exports {
    let (indices, index) = match export_.desc {
      Func(index) => (function_types, index)
      Tag(index) => (tag_types, index)
      _ => continue
    }
    if index >= 0 && index < indices.length() {
      slots = bounded_add(
        slots,
        signature_slots(parsed, indices[index]).to_int64(),
        limit,
        "public signature slots",
      )
    }
  }
}

///|
fn signature_slots(parsed : @wasm_types.Module, type_idx : Int) -> Int {
  // Invalid indices remain the projector's existing validation responsibility.
  // The structural preflight already bounds the sum of params and results.
  match parsed.func_type_at(type_idx) {
    Some(signature) => signature.params.length() + signature.results.length()
    None => 0
  }
}
