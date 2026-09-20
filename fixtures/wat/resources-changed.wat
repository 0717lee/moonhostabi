(module
  (type $event (func (param i64 i32)))
  (memory (export "memory") 2 4)
  (table (export "table") 3 5 funcref)
  (global (export "global") i64 (i64.const 7))
  (tag (export "tag") (type $event))
)
