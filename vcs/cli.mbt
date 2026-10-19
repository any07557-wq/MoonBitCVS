///|
fn cli_usage() -> String {
  (
    #|MoonVCS - a minimal content-addressed version control system
    #|
    #|Usage:
    #|  moonvcs init
    #|  moonvcs clone <remote-repository> <new-directory>
    #|  moonvcs receive-init
    #|  moonvcs receive-policy-install <trusted-local-config.json>
    #|  moonvcs bundle <new-file> <ref-name> <expected-old|none> [target|HEAD]
    #|  moonvcs receive <bundle-file|--stdin>
    #|  moonvcs push <filesystem-server> <ref-name> <expected-old|none>
    #|  moonvcs add <path>...
    #|  moonvcs status
    #|  moonvcs diff [--staged|--cached|HEAD] [-- <path>...]
    #|  moonvcs branch [name]
    #|  moonvcs switch [--dry-run] <branch>
    #|  moonvcs commit -m <message>
    #|  moonvcs log [--max-count N] [--offline]
    #|  moonvcs show <object-id|HEAD> [--offline]
    #|  moonvcs storage-stats
    #|  moonvcs storage-state <object-id>
    #|  moonvcs recover --check
    #|  moonvcs --offline <command> ...
    #|
    #|Switch backups: .moonvcs/switch-history/<transaction-id>/before/
    #|Successful switches retain backups; disk usage grows. No automatic cleanup.
    #|Interrupted switch: preserve .moonvcs/switch-transaction/ and run recover --check.
    #|
  )
}

///|
fn current_directory() -> String raise VcsError {
  match @env.current_dir() {
    Some(path) => path
    None => raise VcsError::InvalidCommand("cannot determine current directory")
  }
}

///|
fn parse_commit_message(args : ArrayView[String]) -> String raise VcsError {
  if args.length() == 2 && (args[0] == "-m" || args[0] == "--message") {
    return args[1]
  }
  raise VcsError::InvalidCommand("commit requires -m <message>")
}

///|
async fn cli_path(root : String, cwd : String, input : String) -> String {
  let relative = if input == "." {
    ""
  } else {
    normalize_repository_path(input)
  }
  let canonical_cwd = @fs.realpath(cwd)
  if canonical_cwd == root {
    if relative == "" {
      "."
    } else {
      relative
    }
  } else {
    if !within_root(root, canonical_cwd) {
      raise VcsError::InvalidPath("current directory is outside repository")
    }
    let prefix = canonical_cwd[root.length() + 1:].to_owned()
    if relative == "" {
      prefix
    } else {
      prefix + "/" + relative
    }
  }
}

///|
async fn resolve_revision(repository : Repository, value : String) -> ObjectId {
  if value == "HEAD" {
    match repository.head() {
      Some(id) => id
      None => raise VcsError::InvalidCommand("HEAD does not contain a commit")
    }
  } else {
    ObjectId::parse(value)
  }
}

///|
fn print_object(id : ObjectId, object : VcsObject) -> Unit {
  match object {
    BlobObject(blob) => {
      println("blob \{id.hex}")
      println("size \{blob.content.length()}")
      println(safe_policy_text(@utf8.decode(blob.content))) catch {
        _ => println("<binary content>")
      }
    }
    TreeObject(tree) => {
      println("tree \{id.hex}")
      for entry in tree.entries {
        let kind = match entry.kind {
          BlobEntry => "blob"
          TreeEntry => "tree"
        }
        println(
          "\{kind} \{entry.object_id.hex} " + safe_policy_text(entry.name),
        )
      }
    }
    CommitObject(commit) => {
      println("commit \{id.hex}")
      println("tree \{commit.tree_id.hex}")
      for parent in commit.parents {
        println("parent \{parent.hex}")
      }
      println("author " + safe_policy_text(commit.author))
      println("timestamp \{commit.timestamp}")
      println("")
      println("    " + safe_policy_text(commit.message))
    }
  }
}

///|
fn cli_expected_old(text : String) -> ObjectId? raise {
  if text == "none" {
    None
  } else {
    Some(ObjectId::parse(text))
  }
}

///|
fn print_receive_report(report : ReceiveReport) -> Unit {
  println("Push accepted")
  let value : Json = {
    "status": "accepted",
    "ref": report.ref_name,
    "target": report.target.hex,
    "checked_commits": report.checked_commits,
    "promoted_objects": report.promoted_objects,
    "policy_revision": report.policy_revision,
  }
  println(value.stringify())
}

///|
async fn receive_cli_executable() -> String {
  let program = @env.args()[0]
  if program.contains("/") {
    return @fs.realpath(program)
  }
  if @env.get_env_var("PATH") is Some(paths) {
    for directory in paths.split(":") {
      let path = directory.to_owned() + "/" + program
      if @fs.exists(path) {
        return @fs.realpath(path)
      }
    }
  }
  raise VcsError::ReceivePolicyError(
    "cannot locate installed receiver executable",
  )
}

///|
async fn invoke_receive_process(server_root : String, wire : Bytes) -> Unit {
  let executable = receive_cli_executable()
  let code = @async.with_task_group() <| group => {
    let (stdin, writer) = @process.write_to_process()
    group.spawn_bg(() => {
      defer writer.close()
      writer.write(wire)
    })
    @process.run(
      executable,
      ["receive", "--stdin"],
      cwd=server_root,
      stdin~,
      inherit_env=false,
      cancel_handler=@process.hard_cancel(),
    )
  }
  if code != 0 {
    raise VcsError::ReceiveProcessExit(code)
  }
}

///|
pub async fn run_cli(argv : ArrayView[String]) -> Unit {
  let mut offline = @env.get_env_var("MOONVCS_OFFLINE") == Some("1")
  let argv = if !argv.is_empty() && argv[0] == "--offline" {
    offline = true
    argv[1:]
  } else {
    argv
  }
  if argv.is_empty() || argv[0] == "help" || argv[0] == "--help" {
    println(cli_usage())
    return
  }
  let cwd = current_directory()
  if [
      "receive-init", "receive-policy-install", "bundle", "receive", "push", "add",
      "status", "diff", "commit", "log", "show", "branch", "switch",
    ].contains(argv[0]) {
    assert_no_switch(find_repository_root(cwd))
  }
  match argv[0] {
    "recover" => {
      if argv.length() != 2 || argv[1] != "--check" {
        raise VcsError::InvalidCommand(
          "only read-only recover --check is supported",
        )
      }
      println(recovery_report(find_repository_root(cwd)))
    }
    "receive-init" => {
      if argv.length() != 1 {
        raise VcsError::InvalidCommand("receive-init takes no arguments")
      }
      let server = Repository::at(find_repository_root(cwd))
      install_receive_policy(
        server,
        default_policy_configuration(),
        initialize=true,
      )
      println("Initialized trusted server on-receive policy")
    }
    "receive-policy-install" => {
      if argv.length() != 2 {
        raise VcsError::InvalidCommand(
          "receive-policy-install requires a trusted local configuration",
        )
      }
      let text = @utf8.decode(read_bounded_storage_file(argv[1], 65536))
      install_receive_policy(Repository::at(find_repository_root(cwd)), text)
      println("Installed trusted server on-receive policy")
    }
    "bundle" => {
      if argv.length() != 4 && argv.length() != 5 {
        raise VcsError::InvalidCommand(
          "bundle requires output, ref, expected-old and optional target",
        )
      }
      let source = Repository::at(
        find_repository_root(cwd),
        offline~,
        fetch_events=true,
      )
      let target = resolve_revision(
        source,
        if argv.length() == 5 {
          argv[4]
        } else {
          "HEAD"
        },
      )
      let request = prepare_receive_request(
        source,
        argv[2],
        cli_expected_old(argv[3]),
        target,
      )
      @fs.write_file(
        argv[1],
        encode_receive_request(request),
        create_mode=CreateNew,
        sync=Full,
      )
      println("Bundle created " + request.target.hex)
    }
    "receive" => {
      if argv.length() != 2 {
        raise VcsError::InvalidCommand("receive requires one bundle file")
      }
      let server = Repository::at(find_repository_root(cwd), offline=true)
      if argv[1] == "--stdin" {
        let bytes = @async.with_timeout(10000, () => {
          read_policy_pipe(@stdio.stdin, max_receive_bundle_bytes)
        }) catch {
          _ =>
            raise VcsError::ReceiveInvalid(
              "invalid oversized or timed-out receive input",
            )
        }
        print_receive_report(
          receive_candidate(server, decode_receive_request(bytes)),
        )
      } else {
        print_receive_report(receive_bundle_file(server, argv[1]))
      }
    }
    "push" => {
      if argv.length() != 4 || offline {
        raise VcsError::InvalidCommand(
          "push requires server, ref and expected-old (or none)",
        )
      }
      let source = Repository::at(find_repository_root(cwd), fetch_events=true)
      let target = resolve_revision(source, "HEAD")
      let request = prepare_receive_request(
        source,
        argv[2],
        cli_expected_old(argv[3]),
        target,
      )
      // Independent receiver process: only bounded wire bytes cross the entry.
      // Production still requires an authenticated endpoint and OS separation.
      let wire = encode_receive_request(request)
      invoke_receive_process(@fs.realpath(argv[1]), wire)
    }
    "clone" => {
      if argv.length() != 3 || offline {
        raise VcsError::InvalidCommand(
          "clone requires a remote and new directory; not available offline",
        )
      }
      let repository = clone_repository(argv[1], argv[2], fetch_events=true)
      let stats = repository.store.transfer_stats()
      println("Cloned " + safe_policy_text(repository.root))
      println(
        "Clone downloaded objects=" +
        stats.received_objects.to_string() +
        " object_bytes=" +
        stats.received_bytes.to_string(),
      )
    }
    "init" => {
      if argv.length() != 1 {
        raise VcsError::InvalidCommand("init does not accept arguments")
      }
      let repository = init_repository(cwd)
      println(
        "Initialized empty MoonVCS repository in " +
        safe_policy_text(repository.root()) +
        "/.moonvcs",
      )
    }
    "add" => {
      let root = find_repository_root(cwd)
      let repository = Repository::at(root, offline~, fetch_events=true)
      let paths : Array[String] = []
      for input in argv[1:] {
        paths.push(cli_path(root, cwd, input))
      }
      let added = repository.add(paths)
      for entry in added {
        println(
          "staged " + safe_policy_text(entry.path) + " \{entry.blob_id.hex}",
        )
      }
    }
    "status" => {
      if argv.length() != 1 {
        raise VcsError::InvalidCommand("status does not accept arguments")
      }
      let repository = Repository::at(
        find_repository_root(cwd),
        offline~,
        fetch_events=true,
      )
      let lines = repository.status()
      if lines.is_empty() {
        println("clean")
      } else {
        for line in lines {
          println(safe_policy_text(line))
        }
      }
    }
    "diff" => {
      let root = find_repository_root(cwd)
      let mut mode = WorkingDiff
      let mut selected = false
      let mut paths_only = false
      let paths : Array[String] = []
      for arg in argv[1:] {
        if paths_only {
          paths.push(cli_path(root, cwd, arg))
        } else if arg == "--" {
          paths_only = true
        } else if !selected && (arg == "--staged" || arg == "--cached") {
          mode = StagedDiff
          selected = true
        } else if !selected && arg == "HEAD" {
          mode = HeadDiff
          selected = true
        } else {
          raise VcsError::DiffFailed(
            "usage: moonvcs diff [--staged|--cached|HEAD] [-- <path>...]",
          )
        }
      }
      // No LazyObjectStore.get: even offline lazy reads can repair metadata.
      @stdio.stdout.write(Repository::at(root, offline~).diff(mode, paths~))
    }
    "branch" => {
      let repository = Repository::at(find_repository_root(cwd), offline~)
      if argv.length() == 1 {
        for line in repository.branches() {
          println(line)
        }
      } else if argv.length() == 2 {
        let id = repository.create_branch(argv[1])
        println("Created branch " + argv[1] + " at " + id.hex)
      } else {
        raise VcsError::CheckoutFailed("usage: moonvcs branch [name]")
      }
    }
    "switch" => {
      let repository = Repository::at(find_repository_root(cwd), offline~)
      let plan = if argv.length() == 3 && argv[1] == "--dry-run" {
        repository.switch_plan(argv[2])
      } else if argv.length() == 2 {
        repository.switch_branch(argv[1])
      } else {
        raise VcsError::CheckoutFailed(
          "usage: moonvcs switch [--dry-run] <branch>",
        )
      }
      println(@json.to_json(plan).stringify())
      if argv.length() == 2 {
        println("Switched to " + argv[1])
      }
    }
    "commit" => {
      let message = parse_commit_message(argv[1:])
      let author = match @env.get_env_var("MOONVCS_AUTHOR") {
        Some(value) => value
        None => "MoonVCS User"
      }
      let repository = Repository::at(
        find_repository_root(cwd),
        offline~,
        fetch_events=true,
      )
      let id = repository.commit(author, @env.now(), message)
      println("Policy passed")
      println("Commit created")
      println("Committed \{id.hex}")
    }
    "log" => {
      let mut max_count = 2147483647
      let mut index = 1
      while index < argv.length() {
        if argv[index] == "--offline" {
          offline = true
          index = index + 1
        } else if argv[index] == "--max-count" && index + 1 < argv.length() {
          let mut count = 0
          let text = argv[index + 1]
          if text.is_empty() || text.length() > 6 {
            raise VcsError::InvalidCommand("invalid log max-count")
          }
          for char in text {
            if char < '0' || char > '9' {
              raise VcsError::InvalidCommand("invalid log max-count")
            }
            count = count * 10 + (char.to_int() - 48)
          }
          max_count = count
          index = index + 2
        } else {
          raise VcsError::InvalidCommand(
            "log accepts --max-count N and --offline",
          )
        }
      }
      let repository = Repository::at(
        find_repository_root(cwd),
        offline~,
        fetch_events=true,
      )
      let commits = repository.log(max_count~)
      if commits.is_empty() {
        println("No commits")
      } else {
        for (id, commit) in commits {
          println("commit \{id.hex}")
          println("Author: " + safe_policy_text(commit.author))
          println("Date:   \{commit.timestamp}")
          println("")
          println("    " + safe_policy_text(commit.message))
          println("")
        }
      }
    }
    "show" => {
      if argv.length() == 3 && argv[2] == "--offline" {
        offline = true
      } else if argv.length() != 2 {
        raise VcsError::InvalidCommand("show requires one object id or HEAD")
      }
      let repository = Repository::at(
        find_repository_root(cwd),
        offline~,
        fetch_events=true,
      )
      let id = resolve_revision(repository, argv[1])
      print_object(id, repository.get_object(id))
    }
    "storage-stats" => {
      if argv.length() != 1 {
        raise VcsError::InvalidCommand("storage-stats takes no arguments")
      }
      let store = LazyObjectStore::new(find_repository_root(cwd), offline~)
      println(@json.to_json(store.transfer_stats()).stringify())
    }
    "storage-state" => {
      if argv.length() != 2 {
        raise VcsError::InvalidCommand("storage-state requires one ObjectId")
      }
      let store = LazyObjectStore::new(find_repository_root(cwd), offline~)
      let state = store.state(ObjectId::parse(argv[1]))
      println(
        match state {
          Local => "Local"
          PromisedRemote => "PromisedRemote"
          Unknown => "Unknown"
        },
      )
    }
    command =>
      raise VcsError::InvalidCommand(
        "unknown command: \{command}\n\n\{cli_usage()}",
      )
  }
}
