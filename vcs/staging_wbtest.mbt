///|
async test "cancelling a staging lock waiter preserves index and allows later add" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-stage-cancel")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    @fs.write_file(root + "/safe.txt", "safe", create_mode=CreateNew)
    let before = repository.load_index()
    let held = acquire_staging_lock(root)
    @async.with_task_group() <| waiting => {
      let writer = waiting.spawn(
        () => repository.add(["safe.txt"]),
        allow_failure=true,
      )
      @async.sleep(30)
      writer.cancel()
      try writer.wait() |> ignore catch {
        _ => ()
      }
    }
    assert_eq(repository.load_index(), before)
    held.unlock()
    held.close()
    repository.add(["safe.txt"]) |> ignore
    assert_eq(repository.load_index().entries.length(), 1)
  }
}
