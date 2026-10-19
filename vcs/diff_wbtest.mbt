///|
fn diff_for_test(before : Bytes?, after : Bytes?) -> String raise {
  let output = DiffOutput::new()
  output.file("file.txt", before, after)
  output.finish()
}

///|
test "diff renders a contextual line replacement and omits identical files" {
  assert_eq(diff_for_test(Some(b"same\n"), Some(b"same\n")), "")
  assert_eq(
    diff_for_test(Some(b"first\nold\nlast\n"), Some(b"first\nnew\nlast\n")),
    "diff --moonvcs a/file.txt b/file.txt\nchange modified\n--- a/file.txt\n+++ b/file.txt\n@@ -1,3 +1,3 @@\n first\n-old\n+new\n last\n",
  )
}

///|
test "diff distinguishes empty additions deletions and missing terminal newlines" {
  let added = diff_for_test(None, Some(b""))
  assert_true(added.contains("change added\n--- /dev/null\n"))
  assert_false(added.contains("@@"))
  assert_true(diff_for_test(Some(b""), None).contains("change deleted\n"))
  assert_true(
    diff_for_test(None, Some(b"one\n")).contains("@@ -0,0 +1,1 @@\n+one\n"),
  )
  assert_true(
    diff_for_test(Some(b"one\n"), None).contains("@@ -1,1 +0,0 @@\n-one\n"),
  )
  assert_true(
    diff_for_test(Some(b"one"), Some(b"one\n")).contains(
      "-one\n\\ No newline at end of file\n+one\n",
    ),
  )
  assert_true(
    diff_for_test(Some(b"a\r\n"), Some(b"a\n")).contains("-a\\r\n+a\n"),
  )
}

///|
test "diff classifies NUL and invalid UTF-8 as binary without printing payload" {
  for content in [b"private\x00value", b"private\xffvalue"] {
    let output = diff_for_test(None, Some(content))
    assert_true(output.contains("Binary files /dev/null (0 bytes)"))
    assert_false(output.contains("private"))
    assert_false(output.contains("@@"))
  }
}

///|
test "diff hunk positions stay correct across distant insertion and deletion" {
  let old = @utf8.encode(
    Array::makei(30, i => "line-" + i.to_string() + "\n").join(""),
  )
  let new = @utf8.encode(
    Array::makei(30, i => {
      if i == 2 {
        "inserted\nline-2\n"
      } else if i == 24 {
        ""
      } else {
        "line-" + i.to_string() + "\n"
      }
    }).join(""),
  )
  let output = diff_for_test(Some(old), Some(new))
  assert_true(output.contains("@@ -1,5 +1,6 @@\n"))
  assert_true(output.contains("@@ -22,7 +23,6 @@\n"))
  assert_true(output.contains("+inserted\n"))
  assert_true(output.contains("-line-24\n"))
}

///|
test "diff edit scripts reconstruct both sides for repeated and unterminated lines" {
  let samples = [
    "", "a\n", "b\n", "a", "a\na\nb\n", "b\na\nb", "\n\n", "a\nb\na\n",
  ]
  for before in samples {
    for after in samples {
      let old = diff_lines(before)
      let new = diff_lines(after)
      let output = DiffOutput::new()
      let edits = output.edits(old, new)
      let rebuilt_old : Array[DiffLine] = []
      let rebuilt_new : Array[DiffLine] = []
      for edit in edits {
        match edit {
          Keep(line) => {
            rebuilt_old.push(line)
            rebuilt_new.push(line)
          }
          Remove(line) => rebuilt_old.push(line)
          Insert(line) => rebuilt_new.push(line)
        }
      }
      assert_true(rebuilt_old == old)
      assert_true(rebuilt_new == new)
    }
  }
}

///|
test "diff LCS budget falls back to a complete deterministic replacement" {
  let old = diff_lines(Array::make(1100, "old\n").join(""))
  let new = diff_lines(Array::make(1100, "new\n").join(""))
  let output = DiffOutput::new()
  let edits = output.edits(old, new)
  assert_eq(edits.length(), 2200)
  assert_eq(output.cells, 0)
  assert_true(edits[0] is Remove(_))
  assert_true(edits[2199] is Insert(_))
  output.hunks(edits)
  assert_true(output.finish().has_prefix("@@ -1,1100 +1,1100 @@\n"))
  let exhausted = DiffOutput::new()
  exhausted.cells = 8000000
  assert_eq(
    exhausted.edits(diff_lines("a\nx\n"), diff_lines("b\nx\n")).length(),
    3,
  )
  assert_eq(exhausted.cells, 8000000)
}

///|
test "diff bounds lines and output with explicit failure instead of truncation" {
  let output = DiffOutput::new()
  output.bytes = 8388607
  let failed = try output.line("x") catch {
    VcsError::DiffFailed(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  let failed = try diff_lines(Array::make(100001, "\n").join("")) catch {
    VcsError::DiffFailed(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
}

///|
test "diff escapes terminal controls bidi formatting and ambiguous backslashes" {
  assert_eq(
    diff_escape("月亮\t\r\n\u001b[31m\u007f\u009b\u202e\\"),
    "月亮\\t\\r\\u{a}\\u{1b}[31m\\u{7f}\\u{9b}\\u{202e}\\\\",
  )
}
