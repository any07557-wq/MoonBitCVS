///|
// Stable on-disk protocol and conservative rejection rules: BRANCH_SWITCH.md.
pub(all) struct SwitchPlan {
  from_ref : String
  target_ref : String
  from_commit : String?
  target_commit : String
  additions : Array[String]
  replacements : Array[String]
  deletions : Array[String]
} derive(@json.ToJson)

///|
pub extend SwitchPlan with @json.ToJson::{to_json}

///|
priv struct SwitchChange {
  path : String
  before : Bytes?
  after : Bytes?
  before_id : String?
  after_id : String?
}

///|
priv struct SwitchChangeRecord {
  path : String
  before : String?
  after : String?
} derive(@json.ToJson, @json.FromJson)

///|
priv struct SwitchManifest {
  schema : Int32
  transaction : String
  from_ref : String
  target_ref : String
  from_commit : String?
  target_commit : String
  old_index_digest : String
  new_index_digest : String
  old_head_digest : String
  new_head_digest : String
  changes : Array[SwitchChangeRecord]
} derive(@json.ToJson, @json.FromJson)

///|
priv struct PreparedSwitch {
  plan : SwitchPlan
  reader : DiffReader
  old_index : Bytes
  new_index : Bytes
  old_head : Bytes
  new_head : Bytes
  current : Map[String, Bytes]
  target : Map[String, Bytes]
  changes : Array[SwitchChange]
}

///|
fn checkout_reader(root : String) -> DiffReader {
  { root, bytes: 0, entries: 0, metadata: [], }
}

///|
async fn checkout_kind(path : String) -> @fs.FileKind? {
  Some(@fs.kind(path, follow_symlink=false)) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  }
}

///|
async fn assert_no_switch(root : String) -> Unit {
  if @fs.kind(root + "/.moonvcs", follow_symlink=false) != Directory {
    raise VcsError::CheckoutFailed(
      "repository metadata must be a real directory; symbolic links forbidden",
    )
  }
  if checkout_kind(root + "/.moonvcs/switch-transaction") is Some(_) {
    raise VcsError::SwitchIncomplete(
      "pending .moonvcs/switch-transaction; stop writers, run moonvcs recover --check; see BRANCH_SWITCH.md",
    )
  }
}

///|
fn branch_ref(name : String) -> String raise {
  if name.is_empty() || name.length() > 240 || name == "HEAD" {
    raise VcsError::CheckoutFailed("invalid or reserved branch name")
  }
  let parts = name.split("/").map(part => part.to_owned()).collect()
  if parts.length() > 8 {
    raise VcsError::CheckoutFailed("branch name exceeds 8 components")
  }
  for part in parts {
    if part.is_empty() ||
      part.length() > 64 ||
      part.contains("..") ||
      part.has_suffix(".") ||
      part.has_suffix(".lock") {
      raise VcsError::CheckoutFailed("invalid branch name component")
    }
    for i = 0; i < part.length(); i = i + 1 {
      let char = part[i]
      let alnum = (char >= 'a' && char <= 'z') ||
        (char >= 'A' && char <= 'Z') ||
        (char >= '0' && char <= '9')
      if !alnum && (i == 0 || (char != '.' && char != '_' && char != '-')) {
        raise VcsError::CheckoutFailed(
          "branch names use the documented ASCII subset",
        )
      }
    }
  }
  "refs/heads/" + name
}

///|
async fn checkout_directory(root : String, relative : String) -> Unit {
  let mut path = root
  for part in relative.split("/") {
    path = path + "/" + part.to_owned()
    match checkout_kind(path) {
      Some(Directory) => ()
      None => {
        @fs.mkdir(path, permission=0o700)
        sync_published_directory(path)
        sync_published_directory(parent_directory(path))
      }
      _ =>
        raise VcsError::CheckoutFailed(
          "directory path is blocked or a symbolic link",
        )
    }
  }
}

///|
async fn checkout_metadata_recheck(reader : DiffReader) -> Unit {
  let recheck = checkout_reader(reader.root)
  for (path, expected) in reader.metadata {
    if recheck.read(path, 4194304) != expected {
      raise VcsError::CheckoutFailed(
        "HEAD, index or branch Ref changed; retry preflight",
      )
    }
  }
}

///|
async fn read_branch_head(reader : DiffReader) -> (String, ObjectId?) {
  guard reader.metadata_file(".moonvcs/HEAD", 4096) is Some(bytes) else {
    raise VcsError::CheckoutFailed("missing HEAD")
  }
  let text = @utf8.decode(bytes).trim().to_owned()
  guard text.has_prefix("ref: refs/heads/") else {
    raise VcsError::CheckoutFailed("only symbolic branch HEAD is supported")
  }
  let name = text[16:].to_owned()
  let ref_name = branch_ref(name)
  let id = match reader.metadata_file(".moonvcs/" + ref_name, 4096) {
    Some(bytes) => Some(ObjectId::parse(@utf8.decode(bytes).trim().to_owned()))
    None => None
  }
  (ref_name, id)
}

///|
async fn list_branch_directory(
  reader : DiffReader,
  relative : String,
  current : String,
  output : Array[String],
  depth : Int32,
) -> Unit {
  if depth > 8 || output.length() > 10000 {
    raise VcsError::CheckoutFailed("branch listing exceeds limits")
  }
  if diff_path_kind(reader.root, relative) != Some(Directory) {
    raise VcsError::CheckoutFailed("branch storage is not a directory")
  }
  let directory = @fs.opendir(reader.root + "/" + relative)
  defer directory.close()
  while directory.next(include_hidden=true) is Some(entry) {
    reader.entries = reader.entries + 1
    if reader.entries > 20000 {
      raise VcsError::CheckoutFailed("branch listing exceeds entry limit")
    }
    let child = relative + "/" + entry.name
    let kind = diff_path_kind(reader.root, child)
    if kind == Some(Directory) {
      list_branch_directory(reader, child, current, output, depth + 1)
    } else if kind == Some(Regular) && !entry.name.has_suffix(".lock") {
      let name = child[20:].to_owned()
      let ref_name = branch_ref(name)
      guard reader.read(child, 4096) is Some(bytes) else {
        raise VcsError::CheckoutFailed("branch disappeared during listing")
      }
      let id = ObjectId::parse(@utf8.decode(bytes).trim().to_owned())
      if output.length() >= 10000 {
        raise VcsError::CheckoutFailed("branch listing exceeds 10000 branches")
      }
      output.push(
        (if ref_name == current { "* " } else { "  " }) + name + " " + id.hex,
      )
    } else {
      raise VcsError::CheckoutFailed(
        "unsupported entry or lock in branch storage; inspect repository",
      )
    }
  }
}

///|
pub async fn Repository::branches(self : Repository) -> Array[String] {
  assert_no_switch(self.root)
  let reader = checkout_reader(self.root)
  let (current, id) = read_branch_head(reader)
  let output : Array[String] = []
  list_branch_directory(reader, ".moonvcs/refs/heads", current, output, 0)
  if id is None {
    output.push("* " + current[11:].to_owned() + " (unborn)")
  }
  output.sort_by((left, right) => {
    compare_utf8(left[2:].to_owned(), right[2:].to_owned())
  })
  checkout_metadata_recheck(reader)
  output
}

///|
pub async fn Repository::create_branch(
  self : Repository,
  name : String,
) -> ObjectId {
  let ref_name = branch_ref(name)
  let lock = acquire_staging_lock(self.root)
  defer lock.close()
  defer lock.unlock()
  let reader = checkout_reader(self.root)
  let (_, current) = read_branch_head(reader)
  guard current is Some(id) else {
    raise VcsError::CheckoutFailed("cannot create a branch from unborn HEAD")
  }
  guard reader.object(id) is CommitObject(_) else {
    raise VcsError::InvalidObject("branch source must be a Commit")
  }
  if diff_path_kind(self.root, ".moonvcs/" + ref_name) is Some(_) {
    raise VcsError::CheckoutFailed(
      "branch already exists or conflicts with an existing Ref",
    )
  }
  checkout_metadata_recheck(reader)
  checkout_directory(self.root, parent_directory(".moonvcs/" + ref_name))
  self.update_ref(ref_name, None, id)
  id
}

///|
async fn prepare_switch(
  repository : Repository,
  name : String,
) -> PreparedSwitch {
  assert_no_switch(repository.root)
  let target_ref = branch_ref(name)
  let reader = checkout_reader(repository.root)
  guard reader.metadata_file(".moonvcs/index", 4194304) is Some(old_index) else {
    raise VcsError::CheckoutFailed("missing index")
  }
  let (from_ref, old_id) = read_branch_head(reader)
  let old_head = reader.metadata[1].1.unwrap()
  let current_ids : Map[String, ObjectId] = Map([])
  if old_id is Some(id) {
    guard reader.object(id) is CommitObject(commit) else {
      raise VcsError::InvalidObject("current HEAD must identify a Commit")
    }
    reader.tree(commit.tree_id, "", current_ids, 0, reject_empty=true)
  }
  let index = decode_index(old_index)
  if index.entries.length() != current_ids.length() ||
    !index.entries.all(entry => {
      current_ids.get(entry.path) == Some(entry.blob_id)
    }) {
    raise VcsError::CheckoutFailed(
      "staged changes; commit or preserve them before switching",
    )
  }
  guard reader.metadata_file(".moonvcs/" + target_ref, 4096)
    is Some(target_bytes) else {
    raise VcsError::CheckoutFailed("target branch does not exist")
  }
  let target_id = ObjectId::parse(@utf8.decode(target_bytes).trim().to_owned())
  guard reader.object(target_id) is CommitObject(commit) else {
    raise VcsError::InvalidObject("target branch must identify a Commit")
  }
  let target_ids : Map[String, ObjectId] = Map([])
  reader.tree(commit.tree_id, "", target_ids, 0, reject_empty=true)
  if current_ids.length() > 10000 || target_ids.length() > 10000 {
    raise VcsError::CheckoutFailed("switch exceeds 10000 files per snapshot")
  }
  let current : Map[String, Bytes] = Map([])
  for (path, id) in current_ids {
    let content = reader.blob(Some(id)).unwrap()
    if reader.read(path, 8388608, working=true) != Some(content) {
      raise VcsError::CheckoutFailed(
        "tracked working files are dirty or deleted; preserve changes before switching",
      )
    }
    current[path] = content
  }
  let target : Map[String, Bytes] = Map([])
  let entries : Array[IndexEntry] = []
  for (path, id) in target_ids {
    let content = if current_ids.get(path) == Some(id) {
      current[path]
    } else {
      reader.blob(Some(id)).unwrap()
    }
    target[path] = content
    entries.push({ path, blob_id: id, })
    if !current.contains(path) &&
      diff_path_kind(repository.root, path) is Some(_) {
      raise VcsError::CheckoutFailed(
        "untracked path or directory would be overwritten; preserve it first",
      )
    }
  }
  let all : Map[String, Bool] = Map([])
  for (path, _) in current {
    all[path] = true
  }
  for (path, _) in target {
    all[path] = true
  }
  if all.length() > 10000 {
    raise VcsError::CheckoutFailed("switch exceeds 10000 combined paths")
  }
  let ordered = all.keys().collect()
  ordered.sort_by(compare_utf8)
  let changes : Array[SwitchChange] = []
  let additions : Array[String] = []
  let replacements : Array[String] = []
  let deletions : Array[String] = []
  for path in ordered {
    let before = current.get(path)
    let after = target.get(path)
    if before == after {
      continue
    }
    if before is None {
      additions.push(path)
    } else if after is None {
      deletions.push(path)
    } else {
      replacements.push(path)
    }
    changes.push({
      path,
      before,
      after,
      before_id: current_ids.get(path).map(id => id.hex),
      after_id: target_ids.get(path).map(id => id.hex),
    })
  }
  for
    relative in [
      ".moonvcs/index.lock",
      ".moonvcs/HEAD.lock",
      ".moonvcs/" + from_ref + ".lock",
      ".moonvcs/" + target_ref + ".lock",
    ] {
    if diff_path_kind(repository.root, relative) is Some(_) {
      raise VcsError::CheckoutFailed(
        "existing exclusive metadata lock; inspect before switching",
      )
    }
  }
  match diff_path_kind(repository.root, ".moonvcs/switch-history") {
    None | Some(Directory) => ()
    _ =>
      raise VcsError::CheckoutFailed(
        "switch history is blocked; inspect repository",
      )
  }
  checkout_metadata_recheck(reader)
  let new_index = encode_index({ entries, })
  if new_index.length() > 4194304 {
    raise VcsError::CheckoutFailed("target index exceeds 4 MiB limit")
  }
  let prepared : PreparedSwitch = {
    plan: {
      from_ref,
      target_ref,
      from_commit: old_id.map(id => id.hex),
      target_commit: target_id.hex,
      additions,
      replacements,
      deletions,
    },
    reader,
    old_index,
    new_index,
    old_head,
    new_head: @utf8.encode("ref: " + target_ref + "\n"),
    current,
    target,
    changes,
  }
  // Check persisted evidence size during dry-run too, not after touching files.
  encode_switch_manifest(prepared, "0".repeat(64)) |> ignore
  prepared
}

///|
pub async fn Repository::switch_plan(
  self : Repository,
  name : String,
) -> SwitchPlan {
  prepare_switch(self, name).plan catch {
    VcsError::DiffFailed(reason) => raise VcsError::CheckoutFailed(reason)
    error => raise error
  }
}

///|
async fn recheck_switch_working(prepared : PreparedSwitch) -> Unit {
  let reader = checkout_reader(prepared.reader.root)
  checkout_metadata_recheck(prepared.reader)
  for (path, bytes) in prepared.current {
    if reader.read(path, 8388608, working=true) != Some(bytes) {
      raise VcsError::CheckoutFailed(
        "working file changed after preflight; no forced overwrite",
      )
    }
  }
  for path in prepared.plan.additions {
    if diff_path_kind(reader.root, path) is Some(_) {
      raise VcsError::CheckoutFailed("new untracked collision after preflight")
    }
  }
}

///|
async fn write_switch_file(path : String, bytes : Bytes) -> Unit {
  @fs.write_file(
    path,
    bytes,
    create_mode=CreateNew,
    permission=0o600,
    sync=Full,
  )
}

///|
async fn switch_phase(pending : String, phase : String) -> Unit {
  write_atomic(pending + "/phase", @utf8.encode(phase + "\n"))
}

///|
fn encode_switch_manifest(
  prepared : PreparedSwitch,
  transaction : String,
) -> Bytes raise {
  let manifest : SwitchManifest = {
    schema: 1,
    transaction,
    from_ref: prepared.plan.from_ref,
    target_ref: prepared.plan.target_ref,
    from_commit: prepared.plan.from_commit,
    target_commit: prepared.plan.target_commit,
    old_index_digest: object_id_for_bytes(prepared.old_index).hex,
    new_index_digest: object_id_for_bytes(prepared.new_index).hex,
    old_head_digest: object_id_for_bytes(prepared.old_head).hex,
    new_head_digest: object_id_for_bytes(prepared.new_head).hex,
    changes: prepared.changes.map(change => SwitchChangeRecord::{
      path: change.path,
      before: change.before_id,
      after: change.after_id,
    }),
  }
  let bytes = @utf8.encode(@json.to_json(manifest).stringify())
  if bytes.length() > 4194304 {
    raise VcsError::CheckoutFailed("switch manifest exceeds 4 MiB limit")
  }
  bytes
}

///|
async fn apply_switch(
  prepared : PreparedSwitch,
  transaction : String,
  manifest : Bytes,
) -> Unit {
  let root = prepared.reader.root
  let pending = root + "/.moonvcs/switch-transaction"
  @fs.mkdir(pending + "/before", permission=0o700)
  @fs.mkdir(pending + "/after", permission=0o700)
  write_switch_file(pending + "/manifest.json", manifest)
  write_switch_file(pending + "/old-index", prepared.old_index)
  write_switch_file(pending + "/new-index", prepared.new_index)
  write_switch_file(pending + "/old-HEAD", prepared.old_head)
  write_switch_file(pending + "/new-HEAD", prepared.new_head)
  for i = 0; i < prepared.changes.length(); i = i + 1 {
    if prepared.changes[i].after is Some(bytes) {
      write_switch_file(pending + "/after/" + i.to_string(), bytes)
    }
  }
  sync_published_directory(pending + "/before")
  sync_published_directory(pending + "/after")
  sync_published_directory(pending)
  sync_published_directory(root + "/.moonvcs")
  switch_phase(pending, "prepared")
  recheck_switch_working(prepared)
  switch_phase(pending, "applying")
  for i = 0; i < prepared.changes.length(); i = i + 1 {
    let change = prepared.changes[i]
    let work_path = root + "/" + change.path
    if change.before is Some(bytes) {
      let reader = checkout_reader(root)
      if reader.read(change.path, 8388608, working=true) != Some(bytes) {
        raise VcsError::CheckoutFailed(
          "working bytes changed before backup; preserved without overwrite",
        )
      }
      @fs.rename(work_path, pending + "/before/" + i.to_string(), replace=false)
      sync_published_directory(parent_directory(work_path))
      sync_published_directory(pending + "/before")
      if read_bounded_storage_file(
          pending + "/before/" + i.to_string(),
          8388608,
        ) !=
        bytes {
        raise VcsError::CheckoutFailed(
          "backup differs from preflight; actual bytes retained in before/",
        )
      }
    }
    if change.after is Some(_) {
      if parent_directory(change.path) != "/" && change.path.contains("/") {
        checkout_directory(root, parent_directory(change.path))
      }
      if diff_path_kind(root, change.path) is Some(_) {
        raise VcsError::CheckoutFailed(
          "path appeared during switch; will not overwrite it",
        )
      }
      @fs.rename(pending + "/after/" + i.to_string(), work_path, replace=false)
      sync_published_directory(parent_directory(work_path))
      sync_published_directory(pending + "/after")
    }
  }
  let verify = checkout_reader(root)
  for (path, bytes) in prepared.target {
    if verify.read(path, 8388608, working=true) != Some(bytes) {
      raise VcsError::CheckoutFailed(
        "target working bytes changed; no metadata publication",
      )
    }
  }
  for i = 0; i < prepared.changes.length(); i = i + 1 {
    let change = prepared.changes[i]
    if change.before is Some(bytes) &&
      read_bounded_storage_file(pending + "/before/" + i.to_string(), 8388608) !=
      bytes {
      raise VcsError::CheckoutFailed(
        "old inode changed after backup; data retained, inspect before/",
      )
    }
    if change.after is None && diff_path_kind(root, change.path) is Some(_) {
      raise VcsError::CheckoutFailed(
        "deleted path reappeared; preserve it before recovery",
      )
    }
  }
  checkout_metadata_recheck(prepared.reader)
  write_atomic(root + "/.moonvcs/index", prepared.new_index)
  switch_phase(pending, "index_published")
  write_atomic(root + "/.moonvcs/HEAD", prepared.new_head)
  switch_phase(pending, "head_published")
  let published = checkout_reader(root)
  if published.read(".moonvcs/index", 4194304) != Some(prepared.new_index) ||
    published.read(".moonvcs/HEAD", 4096) != Some(prepared.new_head) {
    raise VcsError::CheckoutFailed(
      "published metadata changed; preserve transaction",
    )
  }
  for (path, expected) in prepared.reader.metadata {
    if path != ".moonvcs/index" &&
      path != ".moonvcs/HEAD" &&
      published.read(path, 4096) != expected {
      raise VcsError::CheckoutFailed("branch Ref changed during publication")
    }
  }
  switch_phase(pending, "completed")
  checkout_directory(root, ".moonvcs/switch-history")
  @fs.rename(
    pending,
    root + "/.moonvcs/switch-history/" + transaction,
    replace=false,
  )
  sync_published_directory(root + "/.moonvcs/switch-history")
  sync_published_directory(root + "/.moonvcs")
}

///|
pub async fn Repository::switch_branch(
  self : Repository,
  name : String,
) -> SwitchPlan {
  let lock = acquire_staging_lock(self.root)
  defer lock.close()
  defer lock.unlock()
  let prepared = prepare_switch(self, name) catch {
    VcsError::DiffFailed(reason) => raise VcsError::CheckoutFailed(reason)
    error => raise error
  }
  recheck_switch_working(prepared)
  if prepared.plan.from_ref == prepared.plan.target_ref {
    return prepared.plan
  }
  let transaction = match @env.rand(16) {
    Some(bytes) => object_id_for_bytes(bytes).hex
    None =>
      raise VcsError::CheckoutFailed("cannot allocate switch transaction ID")
  }
  let manifest = encode_switch_manifest(prepared, transaction)
  // From this mkdir onwards, NEVER remove evidence or automatically roll back.
  @fs.mkdir(self.root + "/.moonvcs/switch-transaction", permission=0o700)
  apply_switch(prepared, transaction, manifest) catch {
    VcsError::PublicationUncertain(_) as error => raise error
    _ =>
      raise VcsError::SwitchIncomplete(
        "transaction " +
        transaction +
        " target " +
        prepared.plan.target_ref +
        " commit " +
        prepared.plan.target_commit +
        "; preserve .moonvcs/switch-transaction and worktree; run moonvcs recover --check; see BRANCH_SWITCH.md",
      )
  }
  prepared.plan
}

///|
async fn switch_recovery_summary(root : String, relative : String) -> String {
  let reader = checkout_reader(root)
  guard reader.read(relative + "/manifest.json", 4194304) is Some(bytes) else {
    raise VcsError::CheckoutFailed("incomplete switch manifest")
  }
  let manifest : SwitchManifest = @json.from_json(
    @json.parse(@utf8.decode(bytes)),
  )
  ignore(ObjectId::parse(manifest.transaction))
  ignore(ObjectId::parse(manifest.target_commit))
  for
    digest in [
      manifest.old_index_digest,
      manifest.new_index_digest,
      manifest.old_head_digest,
      manifest.new_head_digest,
    ] {
    ignore(ObjectId::parse(digest))
  }
  if manifest.from_commit is Some(id) {
    ignore(ObjectId::parse(id))
  }
  if manifest.schema != 1 ||
    !manifest.from_ref.has_prefix("refs/heads/") ||
    !manifest.target_ref.has_prefix("refs/heads/") {
    raise VcsError::CheckoutFailed("unknown switch manifest")
  }
  ignore(branch_ref(manifest.from_ref[11:].to_owned()))
  ignore(branch_ref(manifest.target_ref[11:].to_owned()))
  let phase = match reader.read(relative + "/phase", 64) {
    Some(bytes) => @utf8.decode(bytes).trim().to_owned()
    None => "preparing"
  }
  if ![
      "preparing", "prepared", "applying", "index_published", "head_published", "completed",
    ].contains(phase) {
    raise VcsError::CheckoutFailed("unknown switch phase")
  }
  let observed = if relative == ".moonvcs/switch-transaction" {
    let head = reader.read(".moonvcs/HEAD", 4096)
    let index = reader.read(".moonvcs/index", 4194304)
    "; HEAD=" +
    switch_observed_version(
      head,
      manifest.old_head_digest,
      manifest.new_head_digest,
    ) +
    "; index=" +
    switch_observed_version(
      index,
      manifest.old_index_digest,
      manifest.new_index_digest,
    )
  } else {
    ""
  }
  "phase=" +
  phase +
  "; from=" +
  manifest.from_ref +
  "; from_commit=" +
  manifest.from_commit.unwrap_or("unborn") +
  "; target=" +
  manifest.target_ref +
  "; commit=" +
  manifest.target_commit +
  "; transaction=" +
  manifest.transaction +
  observed
}

///|
fn switch_observed_version(
  bytes : Bytes?,
  before : String,
  after : String,
) -> String {
  guard bytes is Some(bytes) else { return "missing" }
  let actual = object_id_for_bytes(bytes).hex
  if actual == before && actual == after {
    "old_or_target"
  } else if actual == before {
    "old"
  } else if actual == after {
    "target"
  } else {
    "other"
  }
}
