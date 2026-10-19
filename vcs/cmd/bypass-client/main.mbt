// TEST FIXTURE ONLY. Writes unchecked objects into the specified CLIENT repo,
// never its Ref and never server policy/objects. No local validator is called.

///|
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
async fn run() -> Unit {
  let args = @env.args()
  if args.length() != 5 {
    println(
      "usage: moonvcs-bypass-client CLIENT_ROOT NEW_BUNDLE EXPECTED_OLD MODE",
    )
    exit_process(1)
    return
  }
  let root = @fs.realpath(args[1])
  let parent = if args[3] == "none" {
    None
  } else {
    Some(@core.ObjectId::parse(args[3]))
  }
  let mode = args[4]
  let content = match mode {
    "secret" => "MOONVCS_API_KEY=harmless-bypass-only-do-not-log\n"
    "safe-a" => "APP_MODE=unchecked-client-a\n"
    "safe-b" => "APP_MODE=unchecked-client-b\n"
    _ => {
      println("unsupported fixture mode")
      exit_process(1)
      return
    }
  }
  let store = @core.LocalObjectStore::new(root)
  let blob = @core.VcsObject::BlobObject({ content: @utf8.encode(content), })
  let blob_id = store.put(blob)
  let tree = @core.VcsObject::TreeObject(
    @core.Tree::new([
      {
        name: "config.env",
        kind: @core.TreeEntryKind::BlobEntry,
        object_id: blob_id,
      },
    ]),
  )
  let tree_id = store.put(tree)
  let commit = @core.VcsObject::CommitObject({
    tree_id,
    parents: match parent {
      Some(id) => [id]
      None => []
    },
    author: "Untrusted bypass fixture",
    timestamp: 1792000000000UL,
    message: "unchecked " + mode,
  })
  let target = store.put(commit)
  let request : @core.ReceiveRequest = {
    ref_name: "refs/heads/main",
    expected_old: parent,
    target,
    objects: [
      { id: blob_id, encoded: @core.encode_object(blob), },
      { id: tree_id, encoded: @core.encode_object(tree), },
      { id: target, encoded: @core.encode_object(commit), },
    ],
  }
  @fs.write_file(
    args[2],
    @core.encode_receive_request(request),
    create_mode=CreateNew,
    sync=Full,
  )
  println("Unscanned candidate " + target.hex)
}

///|
async fn main {
  run() catch {
    _ => {
      println("Bypass fixture failed")
      exit_process(1)
    }
  }
}
