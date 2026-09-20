///|
// The wasm_core 0.14 Module omits shared-memory flags and tag attributes. Keep
// this reader limited to restoring and checking that resource metadata.
priv struct ResourceMemoryReader {
  bytes : Bytes
  mut position : Int
  end : Int
}

///|
fn ResourceMemoryReader::read_byte(
  self : ResourceMemoryReader,
) -> Int raise ResourceError {
  if self.position >= self.end {
    invalid_resource("artifact: truncated memory metadata")
  }
  let value = self.bytes[self.position].to_int()
  self.position += 1
  value
}

///|
fn ResourceMemoryReader::read_size(
  self : ResourceMemoryReader,
) -> Int raise ResourceError {
  let mut value = 0L
  for index in 0..<5 {
    let byte = self.read_byte()
    value = value | ((byte & 0x7f).to_int64() << (index * 7))
    if (byte & 0x80) == 0 {
      if value > 2147483647L {
        invalid_resource("artifact: memory metadata size is out of range")
      }
      return value.to_int()
    }
  }
  invalid_resource("artifact: invalid memory metadata size")
}

///|
fn ResourceMemoryReader::skip_bytes(
  self : ResourceMemoryReader,
  count : Int,
) -> Unit raise ResourceError {
  if count < 0 || count > self.end - self.position {
    invalid_resource("artifact: truncated memory metadata")
  }
  self.position += count
}

///|
fn ResourceMemoryReader::skip_leb(
  self : ResourceMemoryReader,
  maximum_bytes : Int,
) -> Unit raise ResourceError {
  for _ in 0..<maximum_bytes {
    if (self.read_byte() & 0x80) == 0 {
      return
    }
  }
  invalid_resource("artifact: invalid memory metadata integer")
}

///|
fn ResourceMemoryReader::skip_value_type(
  self : ResourceMemoryReader,
) -> Unit raise ResourceError {
  match self.read_byte() {
    0x63 | 0x64 => self.skip_leb(5)
    0x7f
    | 0x7e
    | 0x7d
    | 0x7c
    | 0x7b
    | 0x70
    | 0x6f
    | 0x6e
    | 0x6d
    | 0x6c
    | 0x6b
    | 0x6a
    | 0x69
    | 0x71
    | 0x72
    | 0x73
    | 0x74 => ()
    _ => invalid_resource("artifact: invalid imported value type")
  }
}

///|
fn ResourceMemoryReader::skip_limits(
  self : ResourceMemoryReader,
  flags : Int,
) -> Unit raise ResourceError {
  let width = if (flags & 0x04) != 0 { 10 } else { 5 }
  self.skip_leb(width)
  if (flags & 0x01) != 0 {
    self.skip_leb(width)
  }
}

///|
fn ResourceMemoryReader::read_memory_shared(
  self : ResourceMemoryReader,
) -> Bool raise ResourceError {
  let flags = self.read_byte()
  if (flags & 0xf0) != 0 || ((flags & 0x02) != 0 && (flags & 0x01) == 0) {
    invalid_resource("artifact: invalid memory flags")
  }
  self.skip_limits(flags)
  if (flags & 0x08) != 0 {
    self.skip_leb(5)
  }
  (flags & 0x02) != 0
}

///|
fn artifact_memory_shared_flags(
  bytes : Bytes,
  wasm : @wasm_types.Module,
) -> Array[Bool] raise ResourceError {
  let reader : ResourceMemoryReader = {
    bytes,
    position: 8,
    end: bytes.length(),
  }
  let imported : Array[Bool] = []
  let defined : Array[Bool] = []
  while reader.position < reader.end {
    let section_id = reader.read_byte()
    let section_size = reader.read_size()
    if section_size > reader.end - reader.position {
      invalid_resource("artifact: truncated memory metadata section")
    }
    let section : ResourceMemoryReader = {
      bytes,
      position: reader.position,
      end: reader.position + section_size,
    }
    match section_id {
      2 => {
        let count = section.read_size()
        if count != wasm.imports.length() {
          invalid_resource("artifact: import metadata count mismatch")
        }
        for _ in 0..<count {
          section.skip_bytes(section.read_size())
          section.skip_bytes(section.read_size())
          match section.read_byte() {
            0 => section.skip_leb(5)
            1 => {
              section.skip_value_type()
              let flags = section.read_byte()
              if flags != 0 && flags != 1 && flags != 4 && flags != 5 {
                invalid_resource("artifact: invalid imported table flags")
              }
              section.skip_limits(flags)
            }
            2 => imported.push(section.read_memory_shared())
            3 => {
              section.skip_value_type()
              ignore(section.read_byte())
            }
            4 => {
              if section.read_byte() != 0 {
                invalid_resource("artifact: tag attribute must be zero")
              }
              section.skip_leb(5)
            }
            _ => invalid_resource("artifact: invalid import kind")
          }
        }
      }
      5 => {
        let count = section.read_size()
        if count != wasm.memories.length() {
          invalid_resource("artifact: memory metadata count mismatch")
        }
        for _ in 0..<count {
          defined.push(section.read_memory_shared())
        }
      }
      13 => {
        let count = section.read_size()
        if count != wasm.tags.length() {
          invalid_resource("artifact: tag metadata count mismatch")
        }
        for _ in 0..<count {
          if section.read_byte() != 0 {
            invalid_resource("artifact: tag attribute must be zero")
          }
          section.skip_leb(5)
        }
      }
      _ => section.position = section.end
    }
    if section.position != section.end {
      invalid_resource("artifact: memory metadata section size mismatch")
    }
    reader.position = section.end
  }
  let mut imported_count = 0
  for item in wasm.imports {
    if item.desc is Memory(_) {
      imported_count += 1
    }
  }
  if imported.length() != imported_count ||
    defined.length() != wasm.memories.length() {
    invalid_resource("artifact: memory shared metadata is missing")
  }
  for shared in defined {
    imported.push(shared)
  }
  imported
}

///|
fn artifact_memory_resource(
  value : @wasm_types.MemoryType,
  shared : Bool,
  module_name : String?,
  name : String,
) -> MemoryResource {
  {
    path: resource_path(module_name, name),
    module_name,
    name,
    minimum_pages: value.limits.min,
    maximum_pages: value.limits.max,
    shared,
    memory64: value.is_memory64,
    page_size_log2: value.page_size_log2,
  }
}

///|
/// Project host resources from an artifact, including its actual shared-memory
/// flags, which are not represented by the wasm_core 0.14 Module model.
pub fn project_resource_artifact(
  bytes : Bytes,
) -> ResourceSurfaceV4 raise ResourceError {
  let wasm = @wasm_adapter.parse_artifact(bytes) catch {
    error => invalid_resource("artifact: \{error}")
  }
  let surface = project_resource_surface(wasm)
  let shared_flags = artifact_memory_shared_flags(bytes, wasm)
  let memory_types : Array[@wasm_types.MemoryType] = []
  let memories : Array[MemoryResource] = []
  let resolved : Array[String] = []
  for imported in wasm.imports {
    if imported.desc is Memory(value) {
      let path = resource_path(Some(imported.mod_name), imported.name)
      let shared = indexed_resource(shared_flags, memory_types.length(), path)
      memory_types.push(value)
      memories.push(
        artifact_memory_resource(
          value,
          shared,
          Some(imported.mod_name),
          imported.name,
        ),
      )
      resolved.push("\{path}: shared memory metadata unavailable")
    }
  }
  for value in wasm.memories {
    memory_types.push(value)
  }
  for exported in wasm.exports {
    if exported.desc is Memory(index) {
      let path = resource_path(None, exported.name)
      let value = indexed_resource(memory_types, index, path)
      let shared = indexed_resource(shared_flags, index, path)
      memories.push(
        artifact_memory_resource(value, shared, None, exported.name),
      )
      resolved.push("\{path}: shared memory metadata unavailable")
    }
  }
  let result : ResourceSurfaceV4 = {
    ..surface,
    memories,
    unsupported: surface.unsupported.filter(fn(item) {
      !resolved.contains(item)
    }),
  }
  validate_surface_v4(result)
  result
}
