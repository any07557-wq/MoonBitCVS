///|
async fn init_test_repository(root : String) -> Repository {
  // Explicit trusted configuration for Core-only tests; never a production bypass.
  init_repository(
    root,
    policy_config=(
      #|{"schema":1,"host":"","required":[],"allowed_capabilities":[],
      #|"limits":{"fuel":10000000,"timeout_ms":1000,"max_memory_bytes":33554432,
      #|"max_input_bytes":1048576,"max_output_bytes":65536},"custom_rules":[]}
    ),
  )
}
