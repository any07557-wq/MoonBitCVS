;; Correct canonical ABI signature, deliberately invalid decision discriminant.
;; No filesystem access, no imports, no actual secret data.
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 1024))
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $old i32)
    global.get $heap
    local.tee $old
    local.get 3
    i32.add
    i32.const 15
    i32.add
    i32.const -16
    i32.and
    global.set $heap
    local.get $old)
  (func (export "moonvcs:policy/evaluator@0.1.0#evaluate")
    (param i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32)
    (result i32)
    i32.const 0
    i32.const 255
    i32.store
    i32.const 0)
  (func (export "cabi_post_moonvcs:policy/evaluator@0.1.0#evaluate") (param i32))
)
