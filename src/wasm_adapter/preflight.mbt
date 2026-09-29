///|
/// Maximum input size accepted by `parse_artifact_checked` (32 MiB).
pub const MAX_ARTIFACT_BYTES : Int = 32 * 1024 * 1024

///|
// Keep policy internal and immutable. Tests use smaller budgets to exercise
// exact boundaries without constructing resource-exhausting inputs.
// The guarded iterative-expression parser patch removes control-stack recursion.
// Keep a finite 256-frame budget, tested in native debug as well as other targets.
priv struct PreflightLimits {
  bytes : Int
  types : Int
  items : Int
  locals : Int
  function_locals : Int
  instructions : Int
  depth : Int
}

///|
fn preflight_limits(
  bytes? : Int = MAX_ARTIFACT_BYTES,
  types? : Int = 2048,
  items? : Int = 65536,
  locals? : Int = 131072,
  function_locals? : Int = 65536,
  instructions? : Int = 262144,
  depth? : Int = 256,
) -> PreflightLimits {
  { bytes, types, items, locals, function_locals, instructions, depth, }
}

///|
priv struct Preflight {
  bytes : Bytes
  limits : PreflightLimits
  mut pos : Int
  mut end : Int
  mut types : Int
  mut items : Int
  mut locals : Int
  mut instructions : Int
  mut has_data_count : Bool
}

///|
fn Preflight::byte(self : Preflight) -> Int raise ArtifactError {
  if self.pos >= self.end {
    raise InvalidArtifact("unexpected end of section or function body")
  }
  let value = self.bytes[self.pos].to_int()
  self.pos += 1
  value
}

///|
fn Preflight::peek(self : Preflight) -> Int raise ArtifactError {
  if self.pos >= self.end {
    raise InvalidArtifact("unexpected end of section or function body")
  }
  self.bytes[self.pos].to_int()
}

///|
fn Preflight::skip(self : Preflight, size : Int64) -> Unit raise ArtifactError {
  if size < 0L || size > (self.end - self.pos).to_int64() {
    raise InvalidArtifact("length crosses section or function body boundary")
  }
  self.pos += size.to_int()
}

///|
// Unsigned counts stay in Int64 until bounded; no signed Int wraparound and no
// allocation or iteration using an unchecked length from the input.
fn Preflight::u32(self : Preflight) -> Int64 raise ArtifactError {
  let mut result = 0L
  for i in 0..<5 {
    let byte = self.byte()
    if i == 4 && byte > 0x0f {
      raise InvalidArtifact("u32 LEB128 overflow")
    }
    result = result | ((byte & 0x7f).to_int64() << (i * 7))
    if (byte & 0x80) == 0 {
      return result
    }
  }
  raise InvalidArtifact("unterminated u32 LEB128")
}

///|
fn Preflight::leb(
  self : Preflight,
  bits : Int,
  signed : Bool,
) -> Unit raise ArtifactError {
  let count = (bits + 6) / 7
  for i in 0..<count {
    let byte = self.byte()
    if i == count - 1 {
      let remaining = bits - i * 7
      let mask = (1 << remaining) - 1
      let upper = byte & (0x7f ^ mask)
      let negative = signed && (byte & (1 << (remaining - 1))) != 0
      if (byte & 0x80) != 0 ||
        (negative && upper != (0x7f ^ mask)) ||
        (!negative && upper != 0) {
        raise InvalidArtifact("LEB128 overflow")
      }
    }
    if (byte & 0x80) == 0 {
      return
    }
  }
  raise InvalidArtifact("unterminated LEB128")
}

///|
fn bounded_add(
  current : Int,
  amount : Int64,
  limit : Int,
  label : String,
) -> Int raise ArtifactError {
  if amount < 0L || amount > (limit - current).to_int64() {
    raise LimitExceeded(label)
  }
  current + amount.to_int()
}

///|
fn Preflight::items(self : Preflight, count : Int64) -> Int raise ArtifactError {
  self.items = bounded_add(
    self.items,
    count,
    self.limits.items,
    "declared items",
  )
  count.to_int()
}

///|
fn Preflight::vector(self : Preflight) -> Int raise ArtifactError {
  self.items(self.u32())
}

///|
fn Preflight::name(self : Preflight) -> Unit raise ArtifactError {
  self.skip(self.u32())
}

///|
fn Preflight::value_type(self : Preflight) -> Unit raise ArtifactError {
  match self.byte() {
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
    0x63 | 0x64 => self.leb(32, true)
    _ => raise InvalidArtifact("unsupported value type")
  }
}

///|
fn Preflight::mutability(self : Preflight) -> Unit raise ArtifactError {
  if self.byte() > 1 {
    raise InvalidArtifact("malformed mutability")
  }
}

///|
fn Preflight::field(self : Preflight) -> Unit raise ArtifactError {
  match self.peek() {
    0x77 | 0x78 => self.skip(1L)
    _ => self.value_type()
  }
  self.mutability()
}

///|
fn Preflight::subtype(self : Preflight) -> Unit raise ArtifactError {
  let tag = self.peek()
  if tag == 0x50 || tag == 0x4f {
    self.skip(1L)
    let flags = self.byte()
    if flags > (if tag == 0x50 { 3 } else { 1 }) {
      raise InvalidArtifact("malformed subtype flags")
    }
    if (flags & 1) != 0 {
      self.items(1L) |> ignore
      self.u32() |> ignore
    }
  }
  match self.byte() {
    0x60 => {
      let params = self.vector()
      for _ in 0..<params {
        self.value_type()
      }
      let results = self.vector()
      for _ in 0..<results {
        self.value_type()
      }
    }
    0x5f => {
      let fields = self.vector()
      for _ in 0..<fields {
        self.field()
      }
    }
    0x5e => {
      self.items(1L) |> ignore
      self.field()
    }
    _ => raise InvalidArtifact("unsupported composite type")
  }
}

///|
fn Preflight::limits(
  self : Preflight,
  memory : Bool,
) -> Unit raise ArtifactError {
  let flags = self.byte()
  if memory {
    if flags > 15 || (flags & 3) == 2 {
      raise InvalidArtifact("malformed memory limits flags")
    }
  } else if flags != 0 && flags != 1 && flags != 4 && flags != 5 {
    raise InvalidArtifact("malformed table limits flags")
  }
  let bits = if (flags & 4) != 0 { 64 } else { 32 }
  self.leb(bits, false)
  if (flags & 1) != 0 {
    self.leb(bits, false)
  }
  if memory && (flags & 8) != 0 && self.u32() > 30L {
    raise InvalidArtifact("invalid memory page size")
  }
}

///|
fn Preflight::block_type(self : Preflight) -> Unit raise ArtifactError {
  match self.peek() {
    0x40 => self.skip(1L)
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
    | 0x74
    | 0x63
    | 0x64
    | 0x62
    | 0x65 => self.value_type()
    _ => self.leb(32, true)
  }
}

///|
fn Preflight::memarg(self : Preflight) -> Unit raise ArtifactError {
  let flags = self.byte()
  if flags >= 0x80 || (flags & 0x3f) >= 32 {
    raise InvalidArtifact("malformed memory instruction flags")
  }
  if (flags & 0x40) != 0 {
    self.u32() |> ignore
  }
  self.leb(64, false)
}

///|
// Immediate layouts intentionally match wasm_core 0.14.0. In particular its
// br_on_cast layout is label + two value types, not the newer binary layout.
fn Preflight::gc(self : Preflight) -> Unit raise ArtifactError {
  match self.u32() {
    0L | 1L | 6L | 7L | 11L | 12L | 13L | 14L | 16L => self.u32() |> ignore
    2L | 3L | 4L | 5L | 8L | 9L | 10L | 17L | 18L | 19L => {
      self.u32() |> ignore
      self.u32() |> ignore
    }
    20L | 21L | 22L | 23L => self.leb(32, true)
    24L | 25L => {
      self.u32() |> ignore
      self.value_type()
      self.value_type()
    }
    15L | 26L | 27L | 28L | 29L | 30L => ()
    _ => raise InvalidArtifact("unsupported GC opcode")
  }
}

///|
fn Preflight::bulk(self : Preflight) -> Unit raise ArtifactError {
  let opcode = self.u32()
  if (opcode == 8L || opcode == 9L) && !self.has_data_count {
    raise InvalidArtifact("data count section required")
  }
  match opcode {
    0L | 1L | 2L | 3L | 4L | 5L | 6L | 7L | 21L | 22L => ()
    8L | 10L | 12L | 14L => {
      self.u32() |> ignore
      self.u32() |> ignore
    }
    9L | 11L | 13L | 15L | 16L | 17L => self.u32() |> ignore
    _ => raise InvalidArtifact("unsupported bulk-memory opcode")
  }
}

///|
fn Preflight::simd(self : Preflight) -> Unit raise ArtifactError {
  let opcode = self.u32()
  if opcode <= 11L || opcode == 92L || opcode == 93L {
    self.memarg()
  } else if opcode == 12L || opcode == 13L {
    self.skip(16L)
  } else if opcode >= 21L && opcode <= 34L {
    self.skip(1L)
  } else if opcode >= 84L && opcode <= 91L {
    self.memarg()
    self.skip(1L)
  } else {
    match opcode {
      154L
      | 162L
      | 165L
      | 166L
      | 175L
      | 176L
      | 178L
      | 179L
      | 180L
      | 187L
      | 194L
      | 197L
      | 198L
      | 207L
      | 208L
      | 210L
      | 211L
      | 212L
      | 226L
      | 238L => raise InvalidArtifact("reserved SIMD opcode")
      _ => if opcode > 275L { raise InvalidArtifact("unsupported SIMD opcode") }
    }
  }
}

///|
// Iterative traversal allocates only one small frame per bounded nesting level.
// Count every opcode including end/else across every expression in the module.
fn Preflight::expr(self : Preflight) -> Unit raise ArtifactError {
  let frames : Array[Int] = []
  while true {
    let opcode = self.byte()
    self.instructions = bounded_add(
      self.instructions,
      1L,
      self.limits.instructions,
      "instructions",
    )
    match opcode {
      0x0b => {
        if frames.is_empty() {
          return
        }
        frames.pop() |> ignore
      }
      0x05 => {
        if frames.is_empty() || frames[frames.length() - 1] != 0x04 {
          raise InvalidArtifact("else outside if or repeated else")
        }
        frames[frames.length() - 1] = 0x05
      }
      0x02 | 0x03 | 0x04 | 0x1f => {
        if frames.length() >= self.limits.depth {
          raise LimitExceeded("expression depth")
        }
        self.block_type()
        if opcode == 0x1f {
          let handlers = self.vector()
          for _ in 0..<handlers {
            match self.byte() {
              0 | 1 => {
                self.u32() |> ignore
                self.u32() |> ignore
              }
              2 | 3 => self.u32() |> ignore
              _ => raise InvalidArtifact("invalid catch handler kind")
            }
          }
        }
        frames.push(opcode)
      }
      0x08
      | 0x0c
      | 0x0d
      | 0x10
      | 0x12
      | 0x14
      | 0x15
      | 0x20
      | 0x21
      | 0x22
      | 0x23
      | 0x24
      | 0x25
      | 0x26
      | 0x3f
      | 0x40
      | 0xd2
      | 0xd5
      | 0xd6 => self.u32() |> ignore
      0x11 | 0x13 => {
        self.u32() |> ignore
        self.u32() |> ignore
      }
      0x0e => {
        let labels = self.vector()
        for _ in 0..<labels {
          self.u32() |> ignore
        }
        self.u32() |> ignore
      }
      0x41 | 0xd0 => self.leb(32, true)
      0x42 => self.leb(64, true)
      0x43 => self.skip(4L)
      0x44 => self.skip(8L)
      0xfb => self.gc()
      0xfc => self.bulk()
      0xfd => self.simd()
      0xfe => {
        let subopcode = self.u32()
        if subopcode == 3L {
          if self.byte() != 0 {
            raise InvalidArtifact("malformed atomic.fence")
          }
        } else if subopcode <= 2L || (subopcode >= 0x10L && subopcode <= 0x4eL) {
          self.memarg()
        } else {
          raise InvalidArtifact("unsupported atomic opcode")
        }
      }
      0x00 | 0x01 | 0x0a | 0x0f | 0x1a | 0x1b | 0xd1 | 0xd3 | 0xd4 => ()
      _ =>
        if opcode >= 0x28 && opcode <= 0x3e {
          self.memarg()
        } else if opcode < 0x45 || opcode > 0xc4 {
          raise InvalidArtifact("unsupported opcode")
        }
    }
  }
}

///|
fn section_order(id : Int) -> Int {
  match id {
    1 | 2 | 3 | 4 | 5 => id
    13 => 6
    6 | 7 | 8 | 9 => id + 1
    12 => 11
    10 | 11 => id + 2
    _ => 0
  }
}

///|
fn preflight_artifact(
  bytes : Bytes,
  limits : PreflightLimits,
) -> Unit raise ArtifactError {
  if bytes.length() > limits.bytes {
    raise LimitExceeded("artifact bytes")
  }
  if bytes.length() < 8 {
    raise InvalidArtifact("unexpected end of input")
  }
  let scan : Preflight = {
    bytes,
    limits,
    pos: 0,
    end: bytes.length(),
    types: 0,
    items: 0,
    locals: 0,
    instructions: 0,
    has_data_count: false,
  }
  let header = b"\x00asm\x01\x00\x00\x00"
  for expected in header {
    if scan.byte() != expected.to_int() {
      raise InvalidArtifact("invalid Wasm header")
    }
  }
  let mut last_order = 0
  let mut functions = 0
  let mut codes = 0
  let mut datas = 0
  let mut data_count = 0L
  while scan.pos < bytes.length() {
    scan.end = bytes.length()
    scan.items(1L) |> ignore
    let id = scan.byte()
    let size = scan.u32()
    if size > (scan.end - scan.pos).to_int64() {
      raise InvalidArtifact("section length exceeds input")
    }
    scan.end = scan.pos + size.to_int()
    if id != 0 {
      let order = section_order(id)
      if order <= last_order {
        raise InvalidArtifact("unknown, duplicate, or out-of-order section")
      }
      last_order = order
    }
    match id {
      0 => {
        scan.name()
        scan.pos = scan.end
      }
      1 => {
        let groups = scan.vector()
        for _ in 0..<groups {
          let count = if scan.peek() == 0x4e {
            scan.skip(1L)
            scan.u32()
          } else {
            1L
          }
          scan.types = bounded_add(scan.types, count, limits.types, "types")
          scan.items(count) |> ignore
          for _ in 0..<count.to_int() {
            scan.subtype()
          }
        }
      }
      2 => {
        let count = scan.vector()
        for _ in 0..<count {
          scan.name()
          scan.name()
          match scan.byte() {
            0 => scan.u32() |> ignore
            1 => {
              scan.value_type()
              scan.limits(false)
            }
            2 => scan.limits(true)
            3 => {
              scan.value_type()
              scan.mutability()
            }
            4 => {
              if scan.byte() != 0 {
                raise InvalidArtifact("invalid tag attribute")
              }
              scan.u32() |> ignore
            }
            _ => raise InvalidArtifact("invalid import kind")
          }
        }
      }
      3 => {
        functions = scan.vector()
        for _ in 0..<functions {
          scan.u32() |> ignore
        }
      }
      4 => {
        let count = scan.vector()
        for _ in 0..<count {
          let has_init = scan.peek() == 0x40
          if has_init {
            scan.skip(1L)
            if scan.byte() != 0 {
              raise InvalidArtifact("invalid table initializer")
            }
          }
          scan.value_type()
          scan.limits(false)
          if has_init {
            scan.expr()
          }
        }
      }
      5 => {
        let count = scan.vector()
        for _ in 0..<count {
          scan.limits(true)
        }
      }
      6 => {
        let count = scan.vector()
        for _ in 0..<count {
          scan.value_type()
          scan.mutability()
          scan.expr()
        }
      }
      7 => {
        let count = scan.vector()
        for _ in 0..<count {
          scan.name()
          if scan.byte() > 4 {
            raise InvalidArtifact("invalid export kind")
          }
          scan.u32() |> ignore
        }
      }
      8 => scan.u32() |> ignore
      9 => {
        let count = scan.vector()
        for _ in 0..<count {
          let flags = scan.u32()
          if flags > 7L {
            raise InvalidArtifact("invalid element flags")
          }
          if (flags & 1L) == 0L {
            if (flags & 2L) != 0L {
              scan.u32() |> ignore
            }
            scan.expr()
          }
          if flags >= 1L && flags <= 3L {
            if scan.byte() != 0 {
              raise InvalidArtifact("unsupported element kind")
            }
          } else if flags >= 5L {
            scan.value_type()
          }
          let elements = scan.vector()
          for _ in 0..<elements {
            if (flags & 4L) != 0L {
              scan.expr()
            } else {
              scan.u32() |> ignore
            }
          }
        }
      }
      10 => {
        codes = scan.vector()
        for _ in 0..<codes {
          let body_size = scan.u32()
          let section_end = scan.end
          if body_size > (scan.end - scan.pos).to_int64() {
            raise InvalidArtifact("function body length exceeds section")
          }
          scan.end = scan.pos + body_size.to_int()
          let groups = scan.vector()
          let mut function_locals = 0
          for _ in 0..<groups {
            let count = scan.u32()
            function_locals = bounded_add(
              function_locals,
              count,
              limits.function_locals,
              "function locals",
            )
            scan.locals = bounded_add(
              scan.locals,
              count,
              limits.locals,
              "module locals",
            )
            scan.value_type()
          }
          scan.expr()
          if scan.pos != scan.end {
            raise InvalidArtifact("function body size mismatch")
          }
          scan.end = section_end
        }
      }
      11 => {
        datas = scan.vector()
        for _ in 0..<datas {
          match scan.u32() {
            0L => scan.expr()
            1L => ()
            2L => {
              scan.u32() |> ignore
              scan.expr()
            }
            _ => raise InvalidArtifact("invalid data segment flags")
          }
          scan.skip(scan.u32())
        }
      }
      12 => {
        data_count = scan.u32()
        scan.has_data_count = true
      }
      13 => {
        let count = scan.vector()
        for _ in 0..<count {
          if scan.byte() != 0 {
            raise InvalidArtifact("invalid tag attribute")
          }
          scan.u32() |> ignore
        }
      }
      _ => raise InvalidArtifact("unknown section")
    }
    if scan.pos != scan.end {
      raise InvalidArtifact("section size mismatch")
    }
  }
  if functions != codes {
    raise InvalidArtifact("function and code count mismatch")
  }
  if scan.has_data_count && data_count != datas.to_int64() {
    raise InvalidArtifact("data count mismatch")
  }
}
