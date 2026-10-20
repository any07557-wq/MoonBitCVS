test "published native core matches the empty blob vector" {
  let id = @vcs.object_id_for(@vcs.BlobObject({ content: b"", }))
  assert_eq(
    id.to_string(),
    "3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7",
  )
}

test "published native core encodes and decodes binary blob contents" {
  let object = @vcs.BlobObject({ content: b"\x00MoonVCS\xff", })
  assert_eq(@vcs.decode_object(@vcs.encode_object(object)), object)
}
