///|
test "branch names use a bounded traversal-free ASCII subset" {
  for name in ["main", "feature/security", "Release-1.2_3"] {
    assert_eq(branch_ref(name), "refs/heads/" + name)
  }
  for
    name in [
      "",
      "HEAD",
      "-force",
      "/absolute",
      "a//b",
      "../b",
      "a..b",
      "a/..",
      "a/",
      ".hidden",
      "x.lock",
      "x.",
      "a\\b",
      "a\n",
      "月亮",
      "x".repeat(65),
      "a/b/c/d/e/f/g/h/i",
    ] {
    let failed = try branch_ref(name) catch {
      VcsError::CheckoutFailed(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed)
  }
}

///|
async fn with_switch_fixture(body : async (Repository) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-switch")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repo = init_test_repository(root)
    @fs.write_file(root + "/file.txt", "old\n", create_mode=CreateNew)
    @fs.write_file(root + "/deleted.txt", "delete\n", create_mode=CreateNew)
    repo.add(["."]) |> ignore
    repo.commit("Test", 1UL, "old") |> ignore
    repo.create_branch("old") |> ignore
    @fs.write_file(root + "/file.txt", "new\n", create_mode=TruncateExisting)
    @fs.remove(root + "/deleted.txt")
    @fs.write_file(root + "/月亮.bin", b"\x00\xff", create_mode=CreateNew)
    repo.add(["."]) |> ignore
    repo.commit("Test", 2UL, "new") |> ignore
    body(repo)
  }
}

///|
async test "branch lists unborn HEAD and cannot create from it" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-unborn-branch")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repo = init_test_repository(root)
    assert_eq(repo.branches(), ["* main (unborn)"])
    guard expect_failure(() => repo.create_branch("new"))
      is VcsError::CheckoutFailed(_) else {
      fail("unborn source accepted")
    }
    assert_eq(repo.head(), None)
  }
}

///|
async test "branch creation does not overwrite Refs or change HEAD index and working files" {
  with_switch_fixture(repo => {
    let head = repo.head()
    let index = repo.load_index()
    assert_eq(Some(repo.create_branch("feature/check")), head)
    assert_eq(repo.head(), head)
    assert_eq(repo.load_index(), index)
    assert_eq(@fs.read_file(repo.root + "/file.txt").binary(), b"new\n")
    guard expect_failure(() => repo.create_branch("old"))
      is VcsError::CheckoutFailed(_) else {
      fail("existing branch overwritten")
    }
    assert_eq(repo.read_ref("refs/heads/old"), Some(repo.log()[1].0))
    assert_eq(repo.branches().length(), 3)
  })
}

///|
async test "switch plan validates all target content without publishing metadata" {
  with_switch_fixture(repo => {
    let head = repo.head()
    let index = repo.load_index()
    let plan = repo.switch_plan("old")
    assert_eq(plan.additions, ["deleted.txt"])
    assert_eq(plan.replacements, ["file.txt"])
    assert_eq(plan.deletions, ["月亮.bin"])
    assert_eq(repo.head(), head)
    assert_eq(repo.load_index(), index)
    assert_false(@fs.exists(repo.root + "/.moonvcs/switch-transaction"))
    // Synthetic evidence-size vector, not a supported filesystem path.
    let oversized = prepare_switch(repo, "old")
    oversized.changes.push({
      path: "x".repeat(4194304),
      before: None,
      after: Some(b""),
      before_id: None,
      after_id: Some("0".repeat(64)),
    })
    guard expect_failure(() => encode_switch_manifest(oversized, "0".repeat(64)))
      is VcsError::CheckoutFailed(_) else {
      fail("oversized manifest would become unreadable recovery evidence")
    }
  })
}

///|
async test "switch round trip preserves bytes and archives replaced or deleted inodes" {
  with_switch_fixture(repo => {
    let main = repo.head()
    repo.switch_branch("old") |> ignore
    assert_eq(repo.head_ref_name(), "refs/heads/old")
    assert_eq(@fs.read_file(repo.root + "/file.txt").binary(), b"old\n")
    assert_eq(@fs.read_file(repo.root + "/deleted.txt").binary(), b"delete\n")
    assert_false(@fs.exists(repo.root + "/月亮.bin"))
    assert_eq(repo.diff(StagedDiff), "")
    assert_eq(repo.diff(WorkingDiff), "")
    assert_eq(@fs.readdir(repo.root + "/.moonvcs/switch-history").length(), 1)
    repo.switch_branch("main") |> ignore
    assert_eq(repo.head(), main)
    assert_eq(@fs.read_file(repo.root + "/月亮.bin").binary(), b"\x00\xff")
    assert_eq(@fs.readdir(repo.root + "/.moonvcs/switch-history").length(), 2)
  })
}

///|
async test "switch refuses dirty index and working files without dropping them" {
  with_switch_fixture(repo => {
    @fs.write_file(
      repo.root + "/file.txt",
      "user changes",
      create_mode=TruncateExisting,
    )
    guard expect_failure(() => repo.switch_branch("old"))
      is VcsError::CheckoutFailed(_) else {
      fail("dirty working file overwritten")
    }
    assert_eq(@fs.read_file(repo.root + "/file.txt").binary(), b"user changes")
    repo.add(["file.txt"]) |> ignore
    guard expect_failure(() => repo.switch_branch("old"))
      is VcsError::CheckoutFailed(_) else {
      fail("staged changes overwritten")
    }
    assert_false(@fs.exists(repo.root + "/.moonvcs/switch-transaction"))
  })
}

///|
async test "pending switch blocks direct Core writers not only CLI commands" {
  with_switch_fixture(repo => {
    @fs.mkdir(repo.root + "/.moonvcs/switch-transaction", permission=0o700)
    let original = repo.head()
    guard expect_failure(() => repo.add(["file.txt"]))
      is VcsError::SwitchIncomplete(_) else {
      fail("add bypassed pending transaction")
    }
    guard expect_failure(() => repo.commit("Test", 3UL, "blocked"))
      is VcsError::SwitchIncomplete(_) else {
      fail("commit bypassed pending transaction")
    }
    guard expect_failure(() => repo.create_branch("blocked"))
      is VcsError::SwitchIncomplete(_) else {
      fail("branch bypassed pending transaction")
    }
    guard expect_failure(() => {
        repo.update_ref("refs/heads/blocked", None, original.unwrap())
      })
      is VcsError::SwitchIncomplete(_) else {
      fail("internal Ref writer bypassed pending transaction")
    }
    guard expect_failure(() => {
        receive_candidate(repo, {
          ref_name: "refs/heads/blocked",
          expected_old: None,
          target: original.unwrap(),
          objects: [],
        })
      })
      is VcsError::SwitchIncomplete(_) else {
      fail("receive bypassed pending transaction")
    }
    assert_eq(repo.head(), original)
  })
}

///|
async test "switch has no force path for untracked collisions or filesystem type changes" {
  with_switch_fixture(repo => {
    @fs.write_file(
      repo.root + "/deleted.txt",
      "untracked content",
      create_mode=CreateNew,
    )
    guard expect_failure(() => repo.switch_branch("old"))
      is VcsError::CheckoutFailed(_) else {
      fail("untracked collision overwritten")
    }
    assert_eq(
      @fs.read_file(repo.root + "/deleted.txt").binary(),
      b"untracked content",
    )
    @fs.remove(repo.root + "/deleted.txt")
    @fs.mkdir(repo.root + "/deleted.txt", permission=0o700)
    guard expect_failure(() => repo.switch_branch("old"))
      is VcsError::CheckoutFailed(_) else {
      fail("directory replaced by file")
    }
    assert_eq(
      @fs.kind(repo.root + "/deleted.txt", follow_symlink=false),
      @fs.Directory,
    )
  })
}
