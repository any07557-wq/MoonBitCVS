;; Initializer loop: budgets must apply before evaluate is reached.
(module
  (memory (export "memory") 2)
  (func $start (loop $forever (br $forever)))
  (start $start)
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    i32.const 1024)
  (func (export "moonvcs:policy/evaluator@0.1.0#evaluate")
    (param i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32)
    (result i32)
    i32.const 0)
  (func (export "cabi_post_moonvcs:policy/evaluator@0.1.0#evaluate") (param i32))
)
