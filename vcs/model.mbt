///|
pub struct ObjectId {
  hex : String
} derive(Eq, Debug)

///|
pub fn ObjectId::to_string(self : ObjectId) -> String {
  self.hex
}

///|
pub fn ObjectId::parse(value : String) -> ObjectId raise VcsError {
  if value.length() != 64 {
    raise VcsError::InvalidObjectId(value)
  }
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    if !((n >= 48 && n <= 57) || (n >= 97 && n <= 102)) {
      raise VcsError::InvalidObjectId(value)
    }
  }
  { hex: value, }
}

///|
pub(all) struct Blob {
  content : Bytes
} derive(Eq, Debug)

///|
pub(all) enum TreeEntryKind {
  BlobEntry
  TreeEntry
} derive(Eq, Debug)

///|
pub(all) struct TreeEntry {
  name : String
  kind : TreeEntryKind
  object_id : ObjectId
} derive(Eq, Debug)

///|
pub(all) struct Tree {
  entries : Array[TreeEntry]
} derive(Eq, Debug)

///|
pub fn Tree::new(entries : Array[TreeEntry]) -> Tree raise VcsError {
  let normalized = entries.copy()
  normalized.sort_by((left, right) => compare_utf8(left.name, right.name))
  let mut previous : String? = None
  for entry in normalized {
    validate_tree_name(entry.name)
    if previous == Some(entry.name) {
      raise VcsError::InvalidTree("duplicate tree entry: \{entry.name}")
    }
    previous = Some(entry.name)
  }
  { entries: normalized, }
}

///|
fn compare_utf8(left : String, right : String) -> Int32 {
  let a = @utf8.encode(left)
  let b = @utf8.encode(right)
  let common_length = if a.length() < b.length() {
    a.length()
  } else {
    b.length()
  }
  for index in 0..<common_length {
    if a[index] != b[index] {
      return compare(a[index].to_int(), b[index].to_int())
    }
  }
  compare(a.length(), b.length())
}

///|
fn validate_tree_name(name : String) -> Unit raise VcsError {
  if name.length() == 0 ||
    name == "." ||
    name == ".." ||
    name.contains("/") ||
    name.contains("\\") ||
    name.contains("\u0000") {
    raise VcsError::InvalidTree("invalid tree entry name: \{name}")
  }
}

///|
pub(all) struct Commit {
  tree_id : ObjectId
  parents : Array[ObjectId]
  author : String
  timestamp : UInt64
  message : String
} derive(Eq, Debug)

///|
pub(all) struct Ref {
  name : String
  target : ObjectId
} derive(Eq, Debug)

///|
pub(all) struct CandidateFile {
  path : String
  blob_id : ObjectId
  content : Bytes
} derive(Eq, Debug)

///|
pub(all) struct CommitCandidate {
  tree_id : ObjectId
  parents : Array[ObjectId]
  author : String
  timestamp : UInt64
  message : String
  staged_files : Array[CandidateFile]
} derive(Eq, Debug)

///|
pub(all) enum VcsObject {
  BlobObject(Blob)
  TreeObject(Tree)
  CommitObject(Commit)
} derive(Eq, Debug)

///|
pub(all) suberror VcsError {
  InvalidObjectId(String)
  InvalidObject(String)
  InvalidTree(String)
  InvalidPath(String)
  ObjectNotFound(String)
  UnknownObject(String)
  ObjectUnavailableOffline(String)
  RemoteUnavailable(String)
  RemoteObjectMissing(String)
  InvalidPromise(String)
  RemoteRefChanged(String)
  RepositoryNotFound(String)
  RepositoryExists(String)
  RefConflict(String)
  StagingBusy(String)
  PublicationUncertain(String)
  ReceiveRejected(String)
  ReceiveInvalid(String)
  ReceivePolicyError(String)
  ReceiveProcessExit(Int32)
  PolicyRejected(String)
  PolicyExecutionFailed(String)
  InvalidCommand(String)
  DiffFailed(String)
  CheckoutFailed(String)
  SwitchIncomplete(String)
} derive(Debug)

///|
pub(all) enum PolicyDecision {
  PolicyPass
  PolicyReject(String)
  PolicyError(String)
} derive(Eq, Debug)

///|
pub(open) trait PolicyValidator {
  async fn validate(Self, CommitCandidate) -> PolicyDecision
}

///|
pub struct MockPolicyValidator {
  allow : Bool
  reason : String
}

///|
pub fn MockPolicyValidator::pass() -> MockPolicyValidator {
  { allow: true, reason: "", }
}

///|
pub fn MockPolicyValidator::reject(reason : String) -> MockPolicyValidator {
  { allow: false, reason, }
}

///|
pub impl PolicyValidator for MockPolicyValidator with fn validate(self, _) {
  if self.allow {
    PolicyPass
  } else {
    PolicyReject(self.reason)
  }
}
