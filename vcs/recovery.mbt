///|
priv struct RecoveryFinding {
  path : String
  kind : String
  state : String
} derive(ToJson)

///|
priv struct RecoveryReport {
  schema : Int32
  read_only : Bool
  point_in_time_only : Bool
  requires_attention : Bool
  truncated : Bool
  visited : Int32
  findings : Array[RecoveryFinding]
  automatic_recovery : Bool
  journal_replay : Bool
  gc : Bool
  power_loss_verified : Bool
} derive(ToJson)

///|
priv struct RecoveryInspection {
  findings : Array[RecoveryFinding]
  mut visited : Int32
  mut requires_attention : Bool
  mut truncated : Bool
}

///|
fn RecoveryInspection::record(
  self : RecoveryInspection,
  path : String,
  kind : String,
  state : String,
  attention : Bool,
) -> Unit {
  if self.findings.length() >= 1024 {
    self.truncated = true
    self.requires_attention = true
    return
  }
  self.findings.push({ path, kind, state, })
  if attention {
    self.requires_attention = true
  }
}

///|
async fn inspect_advisory_lock(path : String) -> Bool {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise VcsError::InvalidPath(
      "recovery lock inspection expected a regular file",
    )
  }
  if file.try_lock(Exclusive) {
    file.unlock()
    false
  } else {
    true
  }
}

///|
async fn inspect_recovery_directory(
  root : String,
  relative : String,
  inspection : RecoveryInspection,
  depth : Int32,
) -> Unit {
  if depth > 64 || inspection.visited >= 20000 {
    inspection.truncated = true
    inspection.requires_attention = true
    return
  }
  for name in @fs.readdir(root + "/" + relative, include_hidden=true) {
    inspection.visited = inspection.visited + 1
    if inspection.visited > 20000 {
      inspection.truncated = true
      inspection.requires_attention = true
      return
    }
    let child = relative + "/" + name
    let path = root + "/" + child
    try {
      let kind = @fs.kind(path, follow_symlink=false)
      if relative == ".moonvcs" && name == "switch-transaction" {
        let state = if kind == Directory {
          switch_recovery_summary(root, child) catch {
            error => {
              if @async.is_cancellation_error(error) {
                raise error
              }
              "unknown_or_incomplete_manifest; preserve all files; see BRANCH_SWITCH.md"
            }
          }
        } else {
          "unsupported_pending_entry_preserved; see BRANCH_SWITCH.md"
        }
        inspection.record(child, "switch_transaction", state, true)
      } else if relative == ".moonvcs/switch-history" {
        let state = if kind == Directory {
          switch_recovery_summary(root, child) catch {
            error => {
              if @async.is_cancellation_error(error) {
                raise error
              }
              "unknown_switch_archive_preserved"
            }
          }
        } else {
          "unsupported_switch_archive_preserved"
        }
        inspection.record(
          child,
          "switch_archive",
          state,
          !state.has_prefix("phase=completed;"),
        )
      } else if relative == ".moonvcs/quarantine" {
        if kind == Directory {
          let lease = path + "/active.lock"
          if @fs.exists(lease) &&
            @fs.kind(lease, follow_symlink=false) == Regular {
            let active = inspect_advisory_lock(lease)
            inspection.record(
              child,
              "quarantine",
              if active {
                "active"
              } else {
                "inactive_lease_requires_inspection"
              },
              !active,
            )
          } else {
            inspection.record(
              child, "quarantine", "unknown_owner_or_activity", true,
            )
          }
        } else {
          inspection.record(
            child, "quarantine_entry", "unsupported_kind_preserved", true,
          )
        }
      } else if kind == Directory {
        inspect_recovery_directory(root, child, inspection, depth + 1)
      } else if kind != Regular {
        // Never follow metadata symlinks or read their targets.
        inspection.record(
          child, "metadata_entry", "unsupported_kind_preserved", true,
        )
      } else if relative == ".moonvcs" &&
        ["staging-transaction.lock", "lazy-fetch.lock", "receive-publish.lock"].contains(
          name,
        ) {
        let active = inspect_advisory_lock(path)
        inspection.record(
          child,
          "advisory_lock",
          if active {
            "active"
          } else {
            "idle_file_not_a_stale_lock"
          },
          false,
        )
      } else if name.has_suffix(".lock") {
        inspection.record(
          child, "exclusive_lock_or_pending_write", "unknown_owner_or_activity",
          true,
        )
      } else if relative.has_prefix(".moonvcs/objects/") &&
        name.contains(".tmp-") {
        inspection.record(
          child, "temporary_object", "requires_inspection", true,
        )
      }
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        inspection.record(
          child, "inspection_error", "concurrent_change_or_io_error", true,
        )
      }
    }
  }
}

///|
async fn recovery_report(root : String) -> String {
  let inspection : RecoveryInspection = {
    findings: [],
    visited: 0,
    requires_attention: false,
    truncated: false,
  }
  if @fs.kind(root + "/.moonvcs", follow_symlink=false) == Directory {
    inspect_recovery_directory(root, ".moonvcs", inspection, 0)
  } else {
    inspection.record(
      ".moonvcs", "metadata_root", "unsupported_kind_preserved", true,
    )
  }
  @json.to_json(RecoveryReport::{
    schema: 1,
    read_only: true,
    point_in_time_only: true,
    requires_attention: inspection.requires_attention,
    truncated: inspection.truncated,
    visited: inspection.visited,
    findings: inspection.findings,
    automatic_recovery: false,
    journal_replay: false,
    gc: false,
    power_loss_verified: false,
  }).stringify()
}
