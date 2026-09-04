(module $moonhostabi-fixtures/externref@0.1.0
  (type (;0;) (func (param externref) (result externref)))
  (import "host" "echo" (func (;0;) (type 0)))
  (memory (;0;) 1)
  (export "roundtrip" (func 1))
  (func (;1;) (type 0) (param externref) (result externref)
    local.get 0
    call 2
  )
  (func (;2;) (type 0) (param externref) (result externref)
    local.get 0
    call 0
  )
  (@producers
    (language "MoonBit" "")
    (processed-by "moonc" "v0.10.9+6e6c44045")
  )
)
