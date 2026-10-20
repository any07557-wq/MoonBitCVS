fn main {
  try {
    let id = @vcs.object_id_for(@vcs.BlobObject({ content: b"", }))
    println(id.to_string())
  } catch {
    _ => println("object encoding failed")
  }
}
