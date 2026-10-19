///|
pub(all) enum DiffMode {
  WorkingDiff // Index -> working files; untracked files are excluded.
  StagedDiff // HEAD (or empty unborn HEAD) -> index.
  HeadDiff // HEAD -> working files tracked by HEAD or index.
} derive(Eq, Debug)

///|
pub extend DiffMode with Eq::{equal, not_equal}

///|
pub extend DiffMode with @debug.Debug::{to_repr}

///|
priv struct DiffReader {
  root : String
  mut bytes : Int32
  mut entries : Int32
  metadata : Array[(String, Bytes?)]
}

///|
// Unlike exists(), lstat detects dangling links. Only ENOENT means absence;
// permissions, IO errors and special files must never look like a deletion.
async fn diff_path_kind(
  root : String,
  relative : String,
  working~ : Bool = false,
) -> @fs.FileKind? {
  let parts = relative.split("/").map(part => part.to_owned()).collect()
  let mut full = root
  for i = 0; i < parts.length(); i = i + 1 {
    full = full + "/" + parts[i]
    let kind = Some(@fs.kind(full, follow_symlink=false)) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => None
      error => raise error
    }
    match kind {
      None => return None
      Some(SymLink) =>
        raise VcsError::DiffFailed("symbolic link in a compared path")
      Some(value) => {
        if i + 1 == parts.length() {
          return Some(value)
        }
        if value == Regular && working {
          // A tracked directory was replaced with a regular file. Its former
          // descendants are absent; the replacement is shown only if tracked.
          return None
        }
        if value != Directory {
          raise VcsError::DiffFailed("special file in a compared path")
        }
      }
    }
  }
  raise VcsError::DiffFailed("empty comparison path")
}

///|
async fn DiffReader::read(
  self : DiffReader,
  relative : String,
  limit : Int32,
  working~ : Bool = false,
) -> Bytes? {
  match diff_path_kind(self.root, relative, working~) {
    None => return None
    Some(Directory) if working => return None
    Some(Regular) => ()
    _ => raise VcsError::DiffFailed("comparison expected a regular file")
  }
  let path = self.root + "/" + relative
  if !within_root(self.root, @fs.realpath(path)) {
    raise VcsError::DiffFailed("compared path escapes repository")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise VcsError::DiffFailed("compared file changed type; retry diff")
  }
  let size = file.size()
  if size < 0L || size > limit.to_int64() {
    raise VcsError::DiffFailed("comparison file exceeds size limit")
  }
  self.bytes = self.bytes + size.to_int()
  if self.bytes > 67108864 {
    raise VcsError::DiffFailed("comparison exceeds 64 MiB read budget")
  }
  let modified = file.mtime()
  let changed = file.ctime()
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  if file.size() != size || file.mtime() != modified || file.ctime() != changed {
    raise VcsError::DiffFailed(
      "compared file changed while reading; retry diff",
    )
  }
  Some(bytes)
}

///|
async fn DiffReader::metadata_file(
  self : DiffReader,
  relative : String,
  limit : Int32,
) -> Bytes? {
  let bytes = self.read(relative, limit)
  self.metadata.push((relative, bytes))
  bytes
}

///|
async fn DiffReader::object(self : DiffReader, id : ObjectId) -> VcsObject {
  let relative = ".moonvcs/objects/" +
    id.hex[:2].to_owned() +
    "/" +
    id.hex[2:].to_owned()
  guard self.read(relative, max_remote_object_bytes) is Some(bytes) else {
    raise VcsError::DiffFailed(
      "missing local object " +
      id.hex +
      "; fetch with moonvcs show " +
      id.hex +
      ", then retry diff",
    )
  }
  // No promise is created, repaired or trusted and no remote is contacted.
  decode_verified_storage_object(id, bytes)
}

///|
fn diff_validate_path(path : String) -> Unit raise {
  if normalize_repository_path(path) != path ||
    @utf8.encode(path).length() > 4096 ||
    path.split("/").count() > 128 {
    raise VcsError::DiffFailed("comparison path exceeds canonical path limits")
  }
}

///|
async fn DiffReader::tree(
  self : DiffReader,
  id : ObjectId,
  prefix : String,
  output : Map[String, ObjectId],
  depth : Int32,
  reject_empty~ : Bool = false,
) -> Unit {
  if depth > 128 {
    raise VcsError::DiffFailed("comparison exceeds directory depth limit")
  }
  guard self.object(id) is TreeObject(tree) else {
    raise VcsError::InvalidObject("diff expected a Tree")
  }
  if reject_empty && depth > 0 && tree.entries.is_empty() {
    raise VcsError::CheckoutFailed(
      "non-root empty Trees are unsupported by switch; preserve directory semantics",
    )
  }
  for entry in tree.entries {
    self.entries = self.entries + 1
    if self.entries > 20000 {
      raise VcsError::DiffFailed("comparison exceeds 20000 Tree entries")
    }
    let path = if prefix == "" { entry.name } else { prefix + "/" + entry.name }
    diff_validate_path(path)
    match entry.kind {
      BlobEntry => output[path] = entry.object_id
      TreeEntry =>
        self.tree(entry.object_id, path, output, depth + 1, reject_empty~)
    }
  }
}

///|
async fn DiffReader::head_entries(self : DiffReader) -> Map[String, ObjectId] {
  guard self.metadata_file(".moonvcs/HEAD", 4096) is Some(bytes) else {
    raise VcsError::DiffFailed("missing HEAD metadata")
  }
  let text = @utf8.decode(bytes).trim().to_owned()
  guard text.has_prefix("ref: ") else {
    raise VcsError::DiffFailed("detached HEAD is not supported")
  }
  let name = text[5:].to_owned()
  ignore(ref_path(self.root, name))
  let entries : Map[String, ObjectId] = Map([])
  if self.metadata_file(".moonvcs/" + name, 4096) is Some(ref_bytes) {
    let id = ObjectId::parse(@utf8.decode(ref_bytes).trim().to_owned())
    guard self.object(id) is CommitObject(commit) else {
      raise VcsError::InvalidObject("diff expected HEAD to identify a Commit")
    }
    self.tree(commit.tree_id, "", entries, 0)
  }
  entries
}

///|
async fn DiffReader::blob(self : DiffReader, id : ObjectId?) -> Bytes? {
  match id {
    None => None
    Some(id) => {
      guard self.object(id) is BlobObject(blob) else {
        raise VcsError::InvalidObject("diff expected a Blob")
      }
      if blob.content.length() > 8388608 {
        raise VcsError::DiffFailed("comparison Blob exceeds 8 MiB limit")
      }
      Some(blob.content)
    }
  }
}

///|
fn diff_selected(path : String, filters : Array[String]) -> Bool {
  filters.is_empty() ||
  filters.any(filter => {
    filter == "." || path == filter || path.has_prefix(filter + "/")
  })
}

///|
pub async fn Repository::diff(
  self : Repository,
  mode : DiffMode,
  paths~ : Array[String] = [],
) -> String {
  assert_no_switch(self.root)
  for path in paths {
    if path != "." {
      diff_validate_path(path)
    }
  }
  let reader : DiffReader = {
    root: self.root,
    bytes: 0,
    entries: 0,
    metadata: [],
  }
  guard reader.metadata_file(".moonvcs/index", 4194304) is Some(index_bytes) else {
    raise VcsError::DiffFailed("missing index metadata")
  }
  let index = decode_index(index_bytes)
  let staged : Map[String, ObjectId] = Map([])
  // Validate file/directory conflicts without building or writing any objects.
  let directory = DirectoryNode::new()
  for entry in index.entries {
    diff_validate_path(entry.path)
    directory.insert(
      entry.path.split("/").map(part => part.to_owned()).collect(),
      entry.blob_id,
    )
    staged[entry.path] = entry.blob_id
  }
  let before = match mode {
    WorkingDiff => staged
    StagedDiff | HeadDiff => reader.head_entries()
  }
  let tracked : Map[String, Bool] = Map([])
  for (path, _) in before {
    tracked[path] = true
  }
  for (path, _) in staged {
    tracked[path] = true
  }
  if tracked.length() > 10000 {
    raise VcsError::DiffFailed("comparison exceeds 10000 tracked files")
  }
  let ordered = tracked.keys().collect()
  ordered.sort_by(compare_utf8)
  let output = DiffOutput::new()
  for path in ordered {
    if !diff_selected(path, paths) {
      continue
    }
    let old_id = before.get(path)
    let old_content = reader.blob(old_id)
    let new_content = match mode {
      StagedDiff => {
        let new_id = staged.get(path)
        if new_id == old_id {
          old_content
        } else {
          reader.blob(new_id)
        }
      }
      WorkingDiff | HeadDiff => reader.read(path, 8388608, working=true)
    }
    output.file(path, old_content, new_content)
  }
  // Catch observed index / HEAD / Ref changes before printing a partial result.
  // This is a point-in-time inspection, not a globally atomic filesystem view.
  for (path, expected) in reader.metadata {
    if reader.read(path, 4194304) != expected {
      raise VcsError::DiffFailed(
        "index or HEAD changed during comparison; retry diff",
      )
    }
  }
  output.finish()
}

///|
priv struct DiffLine {
  text : String
  newline : Bool
} derive(Eq)

///|
priv enum DiffEdit {
  Keep(DiffLine)
  Remove(DiffLine)
  Insert(DiffLine)
}

///|
priv struct DiffOutput {
  lines : Array[String]
  mut bytes : Int32
  mut cells : Int32
}

///|
fn DiffOutput::new() -> DiffOutput {
  { lines: [], bytes: 0, cells: 0, }
}

///|
fn DiffOutput::line(self : DiffOutput, text : String) -> Unit raise {
  self.bytes = self.bytes + @utf8.encode(text).length() + 1
  if self.bytes > 8388608 {
    raise VcsError::DiffFailed("comparison exceeds 8 MiB output limit")
  }
  self.lines.push(text)
}

///|
fn DiffOutput::finish(self : DiffOutput) -> String {
  if self.lines.is_empty() {
    ""
  } else {
    self.lines.join("\n") + "\n"
  }
}

///|
// Display format, not a patch-application protocol. Escape controls, backslashes
// and bidi formatting so repository content cannot issue terminal commands.
fn diff_escape(text : String) -> String {
  let output = StringBuilder()
  for char in text {
    let code = char.to_int()
    if char == '\\' {
      output.write_string("\\\\")
    } else if char == '\t' {
      output.write_string("\\t")
    } else if char == '\r' {
      output.write_string("\\r")
    } else if code < 32 ||
      (code >= 127 && code <= 159) ||
      (code >= 0x2028 && code <= 0x202e) ||
      (code >= 0x2066 && code <= 0x2069) ||
      code == 0x061c ||
      code == 0x200e ||
      code == 0x200f {
      output.write_string("\\u{" + code.to_string(radix=16) + "}")
    } else {
      output.write_char(char)
    }
  }
  output.to_string()
}

///|
fn diff_text(bytes : Bytes?) -> String? {
  match bytes {
    None => Some("")
    Some(bytes) => {
      if bytes.iter().any(byte => byte == b'\x00') {
        return None
      }
      Some(@utf8.decode(bytes)) catch {
        _ => None
      }
    }
  }
}

///|
fn diff_lines(text : String) -> Array[DiffLine] raise {
  // Bound line allocation before split, including very small repeated lines.
  let mut count = 0
  for char in text {
    if char == '\n' {
      count = count + 1
    }
  }
  if count > 100000 {
    raise VcsError::DiffFailed("comparison exceeds 100000 lines per file")
  }
  let parts = text.split("\n").map(part => part.to_owned()).collect()
  let result : Array[DiffLine] = []
  for i = 0; i < parts.length(); i = i + 1 {
    if i + 1 == parts.length() && parts[i] == "" {
      break
    }
    result.push({ text: parts[i], newline: i + 1 < parts.length(), })
  }
  result
}

///|
fn DiffOutput::edits(
  self : DiffOutput,
  old : Array[DiffLine],
  new : Array[DiffLine],
) -> Array[DiffEdit] {
  let edits : Array[DiffEdit] = []
  let mut prefix = 0
  while prefix < old.length() &&
        prefix < new.length() &&
        old[prefix] == new[prefix] {
    edits.push(Keep(old[prefix]))
    prefix = prefix + 1
  }
  let mut suffix = 0
  while suffix + prefix < old.length() &&
        suffix + prefix < new.length() &&
        old[old.length() - suffix - 1] == new[new.length() - suffix - 1] {
    suffix = suffix + 1
  }
  let n = old.length() - prefix - suffix
  let m = new.length() - prefix - suffix
  let cells = (n.to_int64() + 1L) * (m.to_int64() + 1L)
  if n > 0 &&
    m > 0 &&
    cells <= 1000000L &&
    cells + self.cells.to_int64() <= 8000000L {
    self.cells = self.cells + cells.to_int()
    let width = m + 1
    let lcs = Array::make(cells.to_int(), 0)
    for i = n - 1; i >= 0; i = i - 1 {
      for j = m - 1; j >= 0; j = j - 1 {
        lcs[i * width + j] = if old[prefix + i] == new[prefix + j] {
          lcs[(i + 1) * width + j + 1] + 1
        } else {
          Int32::max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
        }
      }
    }
    let mut i = 0
    let mut j = 0
    while i < n || j < m {
      if i < n && j < m && old[prefix + i] == new[prefix + j] {
        edits.push(Keep(old[prefix + i]))
        i = i + 1
        j = j + 1
      } else if i < n &&
        (j == m || lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]) {
        edits.push(Remove(old[prefix + i]))
        i = i + 1
      } else {
        edits.push(Insert(new[prefix + j]))
        j = j + 1
      }
    }
  } else {
    // Complete, deterministic replacement of the changed middle when an LCS
    // would exceed its budget. No lines are silently omitted or truncated.
    for i = prefix; i < old.length() - suffix; i = i + 1 {
      edits.push(Remove(old[i]))
    }
    for i = prefix; i < new.length() - suffix; i = i + 1 {
      edits.push(Insert(new[i]))
    }
  }
  for i = old.length() - suffix; i < old.length(); i = i + 1 {
    edits.push(Keep(old[i]))
  }
  edits
}

///|
fn DiffOutput::hunks(self : DiffOutput, edits : Array[DiffEdit]) -> Unit raise {
  let mut i = 0
  let mut old_line = 1
  let mut new_line = 1
  while i < edits.length() {
    if edits[i] is Keep(_) {
      i = i + 1
      old_line = old_line + 1
      new_line = new_line + 1
      continue
    }
    let start = Int32::max(0, i - 3)
    let old_start = old_line - (i - start)
    let new_start = new_line - (i - start)
    let mut last_change = i
    let mut end = i + 1
    while end < edits.length() {
      if edits[end] is Keep(_) {
        if end - last_change > 6 {
          break
        }
      } else {
        last_change = end
      }
      end = end + 1
    }
    end = Int32::min(edits.length(), last_change + 4)
    let mut old_count = 0
    let mut new_count = 0
    for j = start; j < end; j = j + 1 {
      match edits[j] {
        Keep(_) => {
          old_count = old_count + 1
          new_count = new_count + 1
        }
        Remove(_) => old_count = old_count + 1
        Insert(_) => new_count = new_count + 1
      }
    }
    let old_position = if old_count == 0 { old_start - 1 } else { old_start }
    let new_position = if new_count == 0 { new_start - 1 } else { new_start }
    self.line(
      "@@ -\{old_position},\{old_count} +\{new_position},\{new_count} @@",
    )
    for j = start; j < end; j = j + 1 {
      let (prefix, line) = match edits[j] {
        Keep(line) => (" ", line)
        Remove(line) => ("-", line)
        Insert(line) => ("+", line)
      }
      self.line(prefix + diff_escape(line.text))
      if !line.newline {
        self.line("\\ No newline at end of file")
      }
      if j >= i {
        match edits[j] {
          Keep(_) => {
            old_line = old_line + 1
            new_line = new_line + 1
          }
          Remove(_) => old_line = old_line + 1
          Insert(_) => new_line = new_line + 1
        }
      }
    }
    i = end
  }
}

///|
fn DiffOutput::file(
  self : DiffOutput,
  path : String,
  before : Bytes?,
  after : Bytes?,
) -> Unit raise {
  if before == after {
    return
  }
  let escaped = diff_escape(path)
  self.line("diff --moonvcs a/" + escaped + " b/" + escaped)
  let change = if before is None {
    "added"
  } else if after is None {
    "deleted"
  } else {
    "modified"
  }
  self.line("change " + change)
  let old_name = if before is None { "/dev/null" } else { "a/" + escaped }
  let new_name = if after is None { "/dev/null" } else { "b/" + escaped }
  self.line("--- " + old_name)
  self.line("+++ " + new_name)
  match (diff_text(before), diff_text(after)) {
    (Some(old), Some(new)) =>
      self.hunks(self.edits(diff_lines(old), diff_lines(new)))
    _ => {
      let old_size = match before {
        None => 0
        Some(bytes) => bytes.length()
      }
      let new_size = match after {
        None => 0
        Some(bytes) => bytes.length()
      }
      self.line(
        "Binary files " +
        old_name +
        " (\{old_size} bytes) and " +
        new_name +
        " (\{new_size} bytes) differ",
      )
    }
  }
}
