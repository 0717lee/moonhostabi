(module
  (type $unused (func (param f64) (result f64)))
  (type $event (func (param i32)))
  (memory (export "memory") 1 3)
  (table (export "table") 2 4 externref)
  (global (export "global") (mut i32) (i32.const 7))
  (tag (export "tag") (type $event))
)
