///|
pub extend ObjectId with Eq::{equal, not_equal}

///|
pub extend ObjectId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Blob with Eq::{equal, not_equal}

///|
pub extend Blob with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TreeEntryKind with Eq::{equal, not_equal}

///|
pub extend TreeEntryKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TreeEntry with Eq::{equal, not_equal}

///|
pub extend TreeEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Tree with Eq::{equal, not_equal}

///|
pub extend Tree with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Commit with Eq::{equal, not_equal}

///|
pub extend Commit with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Ref with Eq::{equal, not_equal}

///|
pub extend Ref with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CandidateFile with Eq::{equal, not_equal}

///|
pub extend CandidateFile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommitCandidate with Eq::{equal, not_equal}

///|
pub extend CommitCandidate with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VcsObject with Eq::{equal, not_equal}

///|
pub extend VcsObject with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VcsError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyDecision with Eq::{equal, not_equal}

///|
pub extend PolicyDecision with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MockPolicyValidator with PolicyValidator::{validate}

///|
pub extend IndexEntry with Eq::{equal, not_equal}

///|
pub extend IndexEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Index with Eq::{equal, not_equal}

///|
pub extend Index with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ObjectState with Eq::{equal, not_equal}

///|
pub extend ObjectState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransferStats with Eq::{equal, not_equal}

///|
pub extend TransferStats with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransferStats with @json.FromJson::{from_json}
