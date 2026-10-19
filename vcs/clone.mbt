///|
async fn read_remote_metadata(root : String, relative : String) -> Bytes {
  try {
    reject_symlink_components(root, relative)
    read_bounded_storage_file(root + "/" + relative, 4096)
  } catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      raise VcsError::RemoteUnavailable("cannot read remote Ref metadata")
    }
  }
}

///|
async fn validate_remote_snapshot(
  root : String,
  head_ref : String,
  head_bytes : Bytes,
  ref_bytes : Bytes,
) -> Unit {
  if read_remote_metadata(root, ".moonvcs/HEAD") != head_bytes ||
    read_remote_metadata(root, ".moonvcs/" + head_ref) != ref_bytes {
    raise VcsError::RemoteRefChanged(head_ref)
  }
}

///|
priv struct CheckoutBudget {
  mut files : Int32
  mut entries : Int32
  mut bytes : UInt64
}

///|
async fn checkout_lazy_tree(
  repository : Repository,
  id : ObjectId,
  prefix : String,
  entries : Array[IndexEntry],
  budget : CheckoutBudget,
  depth : Int32,
) -> Unit {
  if depth > 128 {
    raise VcsError::InvalidObject("checkout exceeds directory depth limit")
  }
  guard repository.store.get(id) is TreeObject(tree) else {
    raise VcsError::InvalidObject("checkout expected a Tree")
  }
  for entry in tree.entries {
    budget.entries = budget.entries + 1
    if budget.entries > 100000 {
      raise VcsError::InvalidObject("checkout exceeds total entry limit")
    }
    let path = if prefix == "" { entry.name } else { prefix + "/" + entry.name }
    if normalize_repository_path(path) != path ||
      @utf8.encode(path).length() > 4096 {
      raise VcsError::InvalidPath("remote tree path is not canonical")
    }
    let full = repository.root + "/" + path
    match entry.kind {
      TreeEntry => {
        @fs.mkdir(full, permission=0o755)
        checkout_lazy_tree(
          repository,
          entry.object_id,
          path,
          entries,
          budget,
          depth + 1,
        )
      }
      BlobEntry => {
        guard repository.store.get(entry.object_id) is BlobObject(blob) else {
          raise VcsError::InvalidObject("checkout expected a Blob")
        }
        budget.files = budget.files + 1
        budget.bytes = budget.bytes + blob.content.length().to_uint64()
        if budget.files > 100000 || budget.bytes > 268435456UL {
          raise VcsError::InvalidObject("checkout exceeds file/byte limit")
        }
        @fs.write_file(
          full,
          blob.content,
          create_mode=CreateNew,
          permission=0o644,
          sync=Full,
        )
        entries.push({ path, blob_id: entry.object_id, })
      }
    }
  }
}

///|
pub async fn clone_repository(
  remote : String,
  destination : String,
  policy_config? : String,
  fetch_events~ : Bool = false,
) -> Repository {
  let destination = if destination.has_prefix("/") {
    destination
  } else {
    current_directory() + "/" + destination
  }
  // The local invoker chooses the remote, which roots the trust relationship.
  // No policy executable/configuration is ever imported from the remote.
  let remote_root = @fs.realpath(remote) catch {
    _ => raise VcsError::RemoteUnavailable("remote repository is unavailable")
  }
  if remote_root == "/" {
    raise VcsError::InvalidPath("invalid remote root")
  }
  let head_bytes = read_remote_metadata(remote_root, ".moonvcs/HEAD")
  let head_text = @utf8.decode(head_bytes).trim().to_owned()
  if !head_text.has_prefix("ref: ") {
    raise VcsError::InvalidObject("remote detached HEAD is not supported")
  }
  let head_ref = head_text[5:].to_owned()
  ignore(ref_path(remote_root, head_ref))
  let ref_bytes = read_remote_metadata(remote_root, ".moonvcs/" + head_ref)
  let head_id = ObjectId::parse(@utf8.decode(ref_bytes).trim().to_owned())
  // Only a nonexistent destination is supported. Existing user data is untouched.
  if @fs.exists(destination) {
    raise VcsError::RepositoryExists(destination)
  }
  let parent = @fs.realpath(parent_directory(destination))
  let name = destination.split("/").last().unwrap().to_owned()
  validate_tree_name(name)
  let final_root = if parent == "/" { "/" + name } else { parent + "/" + name }
  let nonce = match @env.rand(16) {
    Some(bytes) => object_id_for_bytes(bytes).hex
    None =>
      raise VcsError::InvalidObject("cannot create unique clone directory")
  }
  let temporary = parent + "/.moonvcs-clone-" + nonce
  @fs.mkdir(temporary, permission=0o700)
  @async.with_task_group() <| group => {
    let mut published = false
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        if !published && @fs.exists(temporary) {
          @fs.rmdir(temporary, recursive=true)
        }
      })
    })
    let repository = init_repository(temporary, policy_config?)
    @fs.mkdir(temporary + "/.moonvcs/promises", permission=0o700)
    let config : PromisorConfig = {
      schema: 1,
      remote_root,
      head_ref,
      head_id: head_id.hex,
    }
    write_atomic(
      temporary + "/.moonvcs/promisor.json",
      @utf8.encode(@json.to_json(config).stringify()),
    )
    let root_promise : ObjectPromise = {
      schema: 1,
      id: head_id.hex,
      kind: "commit",
      source: "ref",
      anchor: head_id.hex,
    }
    write_atomic(
      repository.store.promise_path(head_id),
      @utf8.encode(@json.to_json(root_promise).stringify()),
    )
    let fetching = Repository::at(temporary, fetch_events~)
    guard fetching.store.get(head_id) is CommitObject(commit) else {
      raise VcsError::InvalidObject("remote HEAD is not a Commit")
    }
    let entries : Array[IndexEntry] = []
    checkout_lazy_tree(
      fetching,
      commit.tree_id,
      "",
      entries,
      { files: 0, entries: 0, bytes: 0UL, },
      0,
    )
    fetching.write_index({ entries, })
    // Clone is one consistent pinned Ref snapshot, not an implicit future pull.
    validate_remote_snapshot(remote_root, head_ref, head_bytes, ref_bytes)
    write_atomic(
      temporary + "/.moonvcs/HEAD",
      @utf8.encode("ref: " + head_ref + "\n"),
    )
    let branch_path = ref_path(temporary, head_ref)
    ensure_storage_directory(parent_directory(branch_path))
    write_atomic(branch_path, @utf8.encode(head_id.hex + "\n"))
    let tracking = temporary +
      "/.moonvcs/refs/remotes/origin/" +
      head_ref[11:].to_owned()
    ensure_storage_directory(parent_directory(tracking))
    write_atomic(tracking, @utf8.encode(head_id.hex + "\n"))
    // Publish the entire checked-out repo only after validation succeeds.
    @fs.rename(temporary, final_root, replace=false)
    published = true
    Repository::at(final_root, fetch_events~)
  }
}
