// Security-test-only policy fixture. Never configure this as a real policy.

///|
fn infinite_loop() -> PolicyResult {
  let mut counter = 0
  while true {
    counter = counter + 1
  }
  {
    decision: Error("infinite-loop fixture unexpectedly terminated: \{counter}"),
    diagnostics: [],
  }
}

///|
fn exhaust_memory() -> PolicyResult {
  let retained : Array[FixedArray[Byte]] = []
  while retained.length() < 1024 {
    retained.push(FixedArray::make(1024 * 1024, b'\x00'))
  }
  {
    decision: Error(
      "memory-growth fixture unexpectedly stayed within its limit",
    ),
    diagnostics: [],
  }
}

///|
fn explicit_trap() -> PolicyResult {
  panic()
}

///|
fn oversized_output() -> PolicyResult {
  {
    decision: Reject,
    diagnostics: [
      {
        code: "fixture.oversized-output",
        severity: ERROR,
        message: "x".repeat(4096),
        path: None,
      },
    ],
  }
}

///|
pub fn evaluate(request : PolicyRequest) -> PolicyResult {
  match request.commit_message {
    "fixture:infinite-loop" => infinite_loop()
    "fixture:memory-growth" => exhaust_memory()
    "fixture:trap" => explicit_trap()
    "fixture:oversized-output" => oversized_output()
    mode =>
      {
        decision: Error("unknown adversarial fixture mode: \{mode}"),
        diagnostics: [],
      }
  }
}
