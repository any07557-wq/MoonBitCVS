///|
pub(all) struct IndexEntry {
  path : String
  blob_id : ObjectId
} derive(Eq, Debug)

///|
pub(all) struct Index {
  entries : Array[IndexEntry]
} derive(Eq, Debug)

///|
pub struct Repository {
  root : String
  store : LazyObjectStore
}

///|
pub fn Repository::at(
  root : String,
  offline~ : Bool = false,
  fetch_events~ : Bool = false,
) -> Repository {
  { root, store: LazyObjectStore::new(root, offline~, fetch_events~), }
}

///|
pub fn Repository::root(self : Repository) -> String {
  self.root
}

///|
fn parent_directory(path : String) -> String {
  if path == "/" {
    return path
  }
  let mut index = path.length() - 1
  while index > 0 && path[index] != '/' {
    index = index - 1
  }
  if index == 0 {
    "/"
  } else {
    path[:index].to_owned()
  }
}

///|
pub async fn find_repository_root(start : String) -> String {
  let mut current = @fs.realpath(start)
  while true {
    if @fs.exists(current + "/.moonvcs") {
      return current
    }
    let parent = parent_directory(current)
    if parent == current {
      raise VcsError::RepositoryNotFound(start)
    }
    current = parent
  }
  raise VcsError::RepositoryNotFound(start)
}

///|
fn encode_index(index : Index) -> Bytes raise {
  let entries = index.entries.copy()
  entries.sort_by((left, right) => compare_utf8(left.path, right.path))
  let encoder = Encoder::new()
  encoder.bytes(b"MOONIDX\x00")
  encoder.byte(1)
  encoder.u32(entries.length())
  let mut previous : String? = None
  for entry in entries {
    let canonical = normalize_repository_path(entry.path)
    if canonical != entry.path || previous == Some(entry.path) {
      raise VcsError::InvalidPath(entry.path)
    }
    previous = Some(entry.path)
    encoder.string(entry.path)
    encoder.object_id(entry.blob_id)
  }
  encoder.finish()
}

///|
fn decode_index(data : Bytes) -> Index raise {
  let decoder = Decoder::new(data)
  if decoder.bytes(8) != b"MOONIDX\x00" || decoder.byte() != 1 {
    raise VcsError::InvalidObject("invalid index format")
  }
  let entries : Array[IndexEntry] = []
  for _ in 0..<decoder.u32() {
    entries.push({ path: decoder.string(), blob_id: decoder.object_id(), })
  }
  if decoder.remaining() != 0 {
    raise VcsError::InvalidObject("trailing bytes in index")
  }
  let index : Index = { entries, }
  if encode_index(index) != data {
    raise VcsError::InvalidObject("noncanonical index encoding")
  }
  index
}

///|
fn index_path(root : String) -> String {
  root + "/.moonvcs/index"
}

///|
async fn sync_storage_directory(path : String) -> Unit {
  let directory = @fs.open(path, mode=ReadOnly)
  defer directory.close()
  if directory.kind() != Directory {
    raise VcsError::InvalidPath("directory sync expected a directory")
  }
  directory.sync()
}

///|
async fn sync_published_directory(path : String) -> Unit {
  @async.protect_from_cancel(() => sync_storage_directory(path)) catch {
    _ =>
      raise VcsError::PublicationUncertain(
        "rename succeeded but directory sync failed; inspect state before retry",
      )
  }
}

///|
async fn write_atomic(path : String, data : Bytes) -> Unit {
  let temporary = path + ".lock"
  let file = @fs.open(
    temporary,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o644,
    sync=Full,
  )
  @async.with_task_group() <| group => {
    let mut published = false
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => {
        if !published && @fs.exists(temporary) {
          @fs.remove(temporary)
        }
      })
    }
    {
      defer file.close()
      file.write_at(data, position=0L)
      file.sync()
    }
    @fs.rename(temporary, path, replace=true)
    published = true
    sync_published_directory(parent_directory(path))
  }
}

///|
pub async fn init_repository(
  root : String,
  policy_config? : String,
) -> Repository {
  let configuration = match policy_config {
    Some(text) => text
    None => default_policy_configuration()
  }
  ignore(parse_policy_context(configuration))
  let canonical_root = @fs.realpath(root)
  let metadata = canonical_root + "/.moonvcs"
  if @fs.exists(metadata) {
    raise VcsError::RepositoryExists(canonical_root)
  }
  @fs.mkdir(metadata + "/objects", recursive=true, permission=0o755)
  @fs.mkdir(metadata + "/refs/heads", recursive=true, permission=0o755)
  @fs.write_file(
    metadata + "/HEAD",
    "ref: refs/heads/main\n",
    create_mode=CreateNew,
    permission=0o644,
    sync=Full,
  )
  write_atomic(index_path(canonical_root), encode_index({ entries: [], }))
  write_atomic(metadata + "/policies.json", @utf8.encode(configuration))
  sync_storage_directory(metadata + "/refs/heads")
  sync_storage_directory(metadata + "/refs")
  sync_storage_directory(metadata)
  sync_storage_directory(canonical_root)
  Repository::at(canonical_root)
}

///|
async fn default_policy_configuration() -> String {
  let program = @env.args()[0]
  let mut executable : String? = None
  if program.contains("/") {
    executable = Some(@fs.realpath(program))
  } else if @env.get_env_var("PATH") is Some(paths) {
    for directory in paths.split(":") {
      let path = directory.to_owned() + "/" + program
      if @fs.exists(path) {
        executable = Some(@fs.realpath(path))
        break
      }
    }
  }
  guard executable is Some(path) else {
    raise VcsError::PolicyExecutionFailed(
      "cannot locate installed policy runtime",
    )
  }
  let defaults = parent_directory(path) + "/moonvcs-default-policy.json"
  @fs.read_file(defaults).text() catch {
    _ =>
      raise VcsError::PolicyExecutionFailed(
        "policy runtime is missing; run scripts/build-vcs.sh",
      )
  }
}

///|
async fn Repository::policy_configuration(self : Repository) -> String {
  @fs.read_file(self.root + "/.moonvcs/policies.json").text() catch {
    _ =>
      raise VcsError::PolicyExecutionFailed(
        "required-policy configuration is missing or unreadable",
      )
  }
}

///|
pub async fn Repository::load_index(self : Repository) -> Index {
  decode_index(@fs.read_file(index_path(self.root)).binary())
}

///|
async fn Repository::write_index(self : Repository, index : Index) -> Unit {
  write_atomic(index_path(self.root), encode_index(index))
}

///|
pub fn normalize_repository_path(path : String) -> String raise {
  if path.length() == 0 ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains("\u0000") {
    raise VcsError::InvalidPath(path)
  }
  let parts : Array[String] = []
  for raw in path.split("/") {
    let part = raw.to_owned()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      raise VcsError::InvalidPath(path)
    }
    parts.push(part)
  }
  if parts.is_empty() || parts[0] == ".moonvcs" {
    raise VcsError::InvalidPath(path)
  }
  parts.join("/")
}

///|
fn within_root(root : String, real : String) -> Bool {
  real == root || real.has_prefix(root + "/")
}

///|
async fn reject_symlink_components(root : String, canonical : String) -> Unit {
  let mut current = root
  for part in canonical.split("/") {
    current = current + "/" + part.to_owned()
    if @fs.exists(current) && @fs.kind(current, follow_symlink=false) == SymLink {
      raise VcsError::InvalidPath(
        "symbolic links are not supported: \{canonical}",
      )
    }
  }
}

///|
async fn collect_files(
  root : String,
  relative : String,
  output : Array[String],
) -> Unit {
  let canonical = if relative == "." {
    ""
  } else {
    normalize_repository_path(relative)
  }
  let full = if canonical == "" { root } else { root + "/" + canonical }
  if !@fs.exists(full) {
    raise VcsError::InvalidPath("path does not exist: \{relative}")
  }
  reject_symlink_components(root, canonical)
  let real = @fs.realpath(full)
  if !within_root(root, real) {
    raise VcsError::InvalidPath("path escapes repository: \{relative}")
  }
  let kind = @fs.kind(full, follow_symlink=false)
  match kind {
    SymLink =>
      raise VcsError::InvalidPath(
        "symbolic links are not supported: \{relative}",
      )
    Regular => output.push(canonical)
    Directory => {
      let names = @fs.readdir(
        full,
        include_hidden=true,
        include_special=false,
        sort=true,
      )
      for name in names {
        if canonical == "" && name == ".moonvcs" {
          continue
        }
        let child = if canonical == "" { name } else { canonical + "/" + name }
        collect_files(root, child, output)
      }
    }
    _ => raise VcsError::InvalidPath("unsupported file type: \{relative}")
  }
}

///|
async fn acquire_staging_lock(root : String) -> @fs.File {
  // Shared writer domain: add/commit/branch/switch and receive publication.
  assert_no_switch(root)
  if checkout_kind(root + "/.moonvcs/staging-transaction.lock") is Some(kind) &&
    kind != Regular {
    raise VcsError::CheckoutFailed("transaction lock must be a regular file")
  }
  let file = @fs.open(
    root + "/.moonvcs/staging-transaction.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  errdefer file.close()
  @async.with_timeout(30000, () => {
    while !file.try_lock(Exclusive) {
      @async.sleep(5)
    }
  }) catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      raise VcsError::StagingBusy("staging transaction lock timed out")
    }
  }
  assert_no_switch(root)
  file
}

///|
pub async fn Repository::add(
  self : Repository,
  paths : Array[String],
) -> Array[IndexEntry] {
  if paths.is_empty() {
    raise VcsError::InvalidCommand("add requires at least one path")
  }
  let transaction = acquire_staging_lock(self.root)
  defer transaction.close()
  defer transaction.unlock()
  let index = self.load_index()
  let staged : Map[String, ObjectId] = Map([])
  for entry in index.entries {
    staged[entry.path] = entry.blob_id
  }
  let added : Array[IndexEntry] = []
  for input in paths {
    let canonical = if input == "." {
      ""
    } else {
      normalize_repository_path(input)
    }
    let stale : Array[String] = []
    staged.each((path, _) => {
      if canonical == "" ||
        path == canonical ||
        path.has_prefix(canonical + "/") {
        stale.push(path)
      }
    })
    for path in stale {
      staged.remove(path)
    }
    let full = if canonical == "" {
      self.root
    } else {
      self.root + "/" + canonical
    }
    if !@fs.exists(full) {
      if stale.is_empty() {
        raise VcsError::InvalidPath("path does not exist: \{input}")
      }
      continue
    }
    let files : Array[String] = []
    collect_files(self.root, input, files)
    for path in files {
      let content = @fs.read_file(self.root + "/" + path).binary()
      let id = self.store.put(BlobObject({ content, }))
      staged[path] = id
      added.push({ path, blob_id: id, })
    }
  }
  let entries : Array[IndexEntry] = []
  staged.each((path, blob_id) => entries.push({ path, blob_id, }))
  self.write_index({ entries, })
  added.sort_by((left, right) => compare(left.path, right.path))
  added
}

///|
priv struct DirectoryNode {
  files : Map[String, ObjectId]
  directories : Map[String, DirectoryNode]
}

///|
fn DirectoryNode::new() -> DirectoryNode {
  { files: {}, directories: {}, }
}

///|
fn DirectoryNode::insert(
  self : DirectoryNode,
  parts : ArrayView[String],
  id : ObjectId,
) -> Unit raise {
  if parts.length() == 1 {
    let name = parts[0]
    if self.directories.contains(name) {
      raise VcsError::InvalidTree("path is both file and directory: \{name}")
    }
    self.files[name] = id
    return
  }
  let name = parts[0]
  if self.files.contains(name) {
    raise VcsError::InvalidTree("path is both file and directory: \{name}")
  }
  let child = self.directories.get_or_init(name, DirectoryNode::new)
  child.insert(parts[1:], id)
}

///|
async fn[S : ObjectStore] write_directory(
  store : S,
  node : DirectoryNode,
) -> ObjectId {
  let entries : Array[TreeEntry] = []
  node.files.each((name, object_id) => {
    entries.push({ name, kind: BlobEntry, object_id, })
  })
  for (name, child) in node.directories {
    let object_id = write_directory(store, child)
    entries.push({ name, kind: TreeEntry, object_id, })
  }
  store.put(TreeObject(Tree::new(entries)))
}

///|
async fn[S : ObjectStore] build_tree(store : S, index : Index) -> ObjectId {
  let root = DirectoryNode::new()
  for entry in index.entries {
    let parts = entry.path.split("/").map(part => part.to_owned()).collect()
    root.insert(parts, entry.blob_id)
  }
  write_directory(store, root)
}

///|
fn ref_path(root : String, name : String) -> String raise {
  if !name.has_prefix("refs/heads/") ||
    name.contains("..") ||
    name.contains("\\") ||
    name.contains("\u0000") {
    raise VcsError::InvalidPath("invalid ref: \{name}")
  }
  for part in name.split("/") {
    if part.is_empty() || part.has_prefix(".") || part.has_suffix(".lock") {
      raise VcsError::InvalidPath("invalid ref: \{name}")
    }
    for char in part {
      if char <= ' ' || char == '\u007f' {
        raise VcsError::InvalidPath("invalid ref: \{name}")
      }
    }
  }
  root + "/.moonvcs/" + name
}

///|
pub async fn Repository::head_ref_name(self : Repository) -> String {
  let content = @fs.read_file(self.root + "/.moonvcs/HEAD")
    .text()
    .trim()
    .to_owned()
  guard content.has_prefix("ref: ") else {
    raise VcsError::InvalidObject("detached HEAD is not supported")
  }
  content[5:].to_owned()
}

///|
pub async fn Repository::read_ref(
  self : Repository,
  name : String,
) -> ObjectId? {
  let path = ref_path(self.root, name)
  if !@fs.exists(path) {
    return None
  }
  Some(ObjectId::parse(@fs.read_file(path).text().trim().to_owned()))
}

///|
pub async fn Repository::head(self : Repository) -> ObjectId? {
  self.read_ref(self.head_ref_name())
}

///|
async fn Repository::update_ref(
  self : Repository,
  name : String,
  expected : ObjectId?,
  target : ObjectId,
) -> Unit {
  assert_no_switch(self.root)
  guard self.store.get(target) is CommitObject(_) else {
    raise VcsError::InvalidObject("ref target must be a stored commit")
  }
  let path = ref_path(self.root, name)
  let lock = path + ".lock"
  let file = @fs.open(
    lock,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o644,
    sync=Full,
  )
  @async.with_task_group() <| group => {
    let mut published = false
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => {
        if !published && @fs.exists(lock) {
          @fs.remove(lock)
        }
      })
    }
    {
      defer file.close()
      file.write_at(@utf8.encode(target.hex + "\n"), position=0L)
      file.sync()
    }
    let actual = self.read_ref(name)
    if actual != expected {
      raise VcsError::RefConflict(name)
    }
    @fs.rename(lock, path, replace=true)
    published = true
    sync_published_directory(parent_directory(path))
  }
}

///|
pub async fn Repository::make_candidate(
  self : Repository,
  author : String,
  timestamp : UInt64,
  message : String,
) -> CommitCandidate {
  assert_no_switch(self.root)
  if message.trim().length() == 0 {
    raise VcsError::InvalidCommand("commit message must not be empty")
  }
  let index = self.load_index()
  let tree_id = build_tree(self.store, index)
  let parents = match self.head() {
    Some(id) =>
      match self.store.get(id) {
        CommitObject(parent) => {
          if parent.tree_id == tree_id {
            raise VcsError::InvalidCommand("nothing is staged")
          }
          [id]
        }
        _ => raise VcsError::InvalidObject("HEAD does not identify a commit")
      }
    None => {
      if index.entries.is_empty() {
        raise VcsError::InvalidCommand("nothing is staged")
      }
      []
    }
  }
  let staged_files : Array[CandidateFile] = []
  for entry in index.entries {
    match self.store.get(entry.blob_id) {
      BlobObject(blob) =>
        staged_files.push({
          path: entry.path,
          blob_id: entry.blob_id,
          content: blob.content,
        })
      _ =>
        raise VcsError::InvalidObject(
          "index entry is not a blob: \{entry.path}",
        )
    }
  }
  { tree_id, parents, author, timestamp, message, staged_files, }
}

///|
pub async fn[V : PolicyValidator] Repository::commit_with_validator(
  self : Repository,
  author : String,
  timestamp : UInt64,
  message : String,
  validator : V,
) -> ObjectId {
  let transaction = acquire_staging_lock(self.root)
  defer transaction.close()
  defer transaction.unlock()
  let ref_name = self.head_ref_name()
  let candidate = self.make_candidate(author, timestamp, message)
  let configuration = self.policy_configuration()
  let context = parse_policy_context(configuration)
  // Freeze the persisted object before any caller-supplied validator runs.
  let commit : Commit = {
    tree_id: candidate.tree_id,
    parents: candidate.parents.copy(),
    author: candidate.author,
    timestamp: candidate.timestamp,
    message: candidate.message,
  }
  match validate_policies(candidate, context) {
    Accept => ()
    Warning(diagnostics) => println(format_policy_diagnostics(diagnostics))
    Reject(diagnostics) =>
      raise VcsError::PolicyRejected(format_policy_diagnostics(diagnostics))
    EngineError(reason) => raise VcsError::PolicyExecutionFailed(reason)
  }
  match validator.validate(candidate) {
    PolicyPass => ()
    PolicyReject(reason) => raise VcsError::PolicyRejected(reason)
    PolicyError(reason) =>
      raise VcsError::PolicyRejected("policy error: \{reason}")
  }
  if self.policy_configuration() != configuration {
    raise VcsError::PolicyExecutionFailed(
      "required-policy configuration changed during validation",
    )
  }
  let commit_id = self.store.put(CommitObject(commit))
  let expected = match commit.parents {
    [parent] => Some(parent)
    _ => None
  }
  if self.head_ref_name() != ref_name {
    raise VcsError::RefConflict("HEAD changed during policy validation")
  }
  self.update_ref(ref_name, expected, commit_id)
  commit_id
}

///|
pub async fn Repository::commit(
  self : Repository,
  author : String,
  timestamp : UInt64,
  message : String,
) -> ObjectId {
  self.commit_with_validator(
    author,
    timestamp,
    message,
    MockPolicyValidator::pass(),
  )
}

///|
pub async fn Repository::log(
  self : Repository,
  max_count~ : Int32 = 2147483647,
) -> Array[(ObjectId, Commit)] {
  assert_no_switch(self.root)
  if max_count < 0 {
    raise VcsError::InvalidCommand("negative log max-count")
  }
  let commits : Array[(ObjectId, Commit)] = []
  let mut next = self.head()
  while next is Some(id) && commits.length() < max_count {
    match self.store.get(id) {
      CommitObject(commit) => {
        commits.push((id, commit))
        next = match commit.parents {
          [parent, ..] => Some(parent)
          [] => None
        }
      }
      _ =>
        raise VcsError::InvalidObject(
          "ref does not point to a commit: \{id.hex}",
        )
    }
  }
  commits
}

///|
async fn[S : ObjectStore] flatten_tree(
  store : S,
  tree_id : ObjectId,
  prefix : String,
  output : Map[String, ObjectId],
) -> Unit {
  match store.get(tree_id) {
    TreeObject(tree) =>
      for entry in tree.entries {
        let path = if prefix == "" {
          entry.name
        } else {
          prefix + "/" + entry.name
        }
        match entry.kind {
          BlobEntry => output[path] = entry.object_id
          TreeEntry => flatten_tree(store, entry.object_id, path, output)
        }
      }
    _ => raise VcsError::InvalidObject("tree id does not identify a tree")
  }
}

///|
pub async fn Repository::status(self : Repository) -> Array[String] {
  assert_no_switch(self.root)
  let index = self.load_index()
  let head_entries : Map[String, ObjectId] = Map([])
  if self.head() is Some(head_id) {
    match self.store.get(head_id) {
      CommitObject(commit) =>
        flatten_tree(self.store, commit.tree_id, "", head_entries)
      _ => raise VcsError::InvalidObject("HEAD does not identify a commit")
    }
  }
  let lines : Array[String] = []
  // Validate every working path before reading tracked bytes, including ancestors.
  let working_files : Array[String] = []
  collect_files(self.root, ".", working_files)
  let staged_entries : Map[String, ObjectId] = Map([])
  for entry in index.entries {
    staged_entries[entry.path] = entry.blob_id
    if head_entries.get(entry.path) != Some(entry.blob_id) {
      lines.push("staged  " + entry.path)
    }
    let full = self.root + "/" + entry.path
    if !@fs.exists(full) {
      lines.push("deleted " + entry.path)
    } else if @fs.kind(full, follow_symlink=false) == Regular {
      let working = object_id_for(
        BlobObject({ content: @fs.read_file(full).binary(), }),
      )
      if working != entry.blob_id {
        lines.push("modified " + entry.path)
      }
    } else {
      lines.push("typechanged " + entry.path)
    }
  }
  head_entries.each((path, _) => {
    if !staged_entries.contains(path) {
      lines.push("staged  delete " + path)
    }
  })
  for path in working_files {
    if !staged_entries.contains(path) {
      lines.push("untracked " + path)
    }
  }
  lines.sort()
  lines
}

///|
pub async fn Repository::get_object(
  self : Repository,
  id : ObjectId,
) -> VcsObject {
  assert_no_switch(self.root)
  self.store.get(id)
}
