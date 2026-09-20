(module
  (type $event (func (param i32)))
  (memory (export "memory") 1 3)
  (table (export "table") 2 4 externref)
  (global (export "global") (mut i64) (i64.const 7))
  (tag (export "tag") (type $event))
)
