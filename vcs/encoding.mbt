///|
let object_magic : Bytes = b"MOONVCS\x00"

///|
priv struct Encoder {
  data : Array[Byte]
}

///|
fn Encoder::new() -> Encoder {
  { data: [], }
}

///|
fn Encoder::byte(self : Encoder, value : Int32) -> Unit {
  self.data.push(value.to_byte())
}

///|
fn Encoder::u32(self : Encoder, value : Int32) -> Unit raise VcsError {
  if value < 0 {
    raise VcsError::InvalidObject("negative length")
  }
  self.byte((value >> 24) & 0xff)
  self.byte((value >> 16) & 0xff)
  self.byte((value >> 8) & 0xff)
  self.byte(value & 0xff)
}

///|
fn Encoder::u64(self : Encoder, value : UInt64) -> Unit {
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    self.byte(((value >> shift) & 0xff).to_int())
  }
}

///|
fn Encoder::bytes(self : Encoder, value : BytesView) -> Unit {
  for byte in value {
    self.data.push(byte)
  }
}

///|
fn Encoder::string(self : Encoder, value : String) -> Unit raise VcsError {
  let encoded = @utf8.encode(value)
  self.u32(encoded.length())
  self.bytes(encoded)
}

///|
fn Encoder::object_id(self : Encoder, value : ObjectId) -> Unit raise VcsError {
  ignore(ObjectId::parse(value.hex))
  self.bytes(@utf8.encode(value.hex))
}

///|
fn Encoder::finish(self : Encoder) -> Bytes {
  Bytes::from_array(self.data)
}

///|
priv struct Decoder {
  data : Bytes
  mut offset : Int32
}

///|
fn Decoder::new(data : Bytes) -> Decoder {
  { data, offset: 0, }
}

///|
fn Decoder::remaining(self : Decoder) -> Int32 {
  self.data.length() - self.offset
}

///|
fn Decoder::byte(self : Decoder) -> Int32 raise VcsError {
  if self.remaining() < 1 {
    raise VcsError::InvalidObject("unexpected end of object")
  }
  let result = self.data[self.offset].to_int()
  self.offset = self.offset + 1
  result
}

///|
fn Decoder::u32(self : Decoder) -> Int32 raise VcsError {
  let a = self.byte()
  let b = self.byte()
  let c = self.byte()
  let d = self.byte()
  if a >= 128 {
    raise VcsError::InvalidObject("field count or length exceeds 2147483647")
  }
  (a << 24) | (b << 16) | (c << 8) | d
}

///|
fn Decoder::u64(self : Decoder) -> UInt64 raise VcsError {
  let mut value = 0UL
  for _ in 0..<8 {
    value = (value << 8) | self.byte().to_uint64()
  }
  value
}

///|
fn Decoder::bytes(self : Decoder, length : Int32) -> Bytes raise VcsError {
  if length < 0 || self.remaining() < length {
    raise VcsError::InvalidObject("invalid field length")
  }
  let value = self.data[self.offset:self.offset + length].to_owned()
  self.offset = self.offset + length
  value
}

///|
fn Decoder::string(self : Decoder) -> String raise {
  @utf8.decode(self.bytes(self.u32()))
}

///|
fn Decoder::object_id(self : Decoder) -> ObjectId raise {
  ObjectId::parse(@utf8.decode(self.bytes(64)))
}

///|
fn encode_payload(object : VcsObject) -> Bytes raise VcsError {
  let encoder = Encoder::new()
  match object {
    BlobObject(blob) => encoder.bytes(blob.content)
    TreeObject(tree) => {
      let canonical = Tree::new(tree.entries)
      encoder.u32(canonical.entries.length())
      for entry in canonical.entries {
        encoder.byte(
          match entry.kind {
            BlobEntry => 1
            TreeEntry => 2
          },
        )
        encoder.string(entry.name)
        encoder.object_id(entry.object_id)
      }
    }
    CommitObject(commit) => {
      encoder.object_id(commit.tree_id)
      encoder.u32(commit.parents.length())
      for parent in commit.parents {
        encoder.object_id(parent)
      }
      encoder.string(commit.author)
      encoder.u64(commit.timestamp)
      encoder.string(commit.message)
    }
  }
  encoder.finish()
}

///|
pub fn encode_object(object : VcsObject) -> Bytes raise VcsError {
  let payload = encode_payload(object)
  let encoder = Encoder::new()
  encoder.bytes(object_magic)
  encoder.byte(1)
  encoder.byte(
    match object {
      BlobObject(_) => 1
      TreeObject(_) => 2
      CommitObject(_) => 3
    },
  )
  encoder.u64(payload.length().to_uint64())
  encoder.bytes(payload)
  encoder.finish()
}

///|
pub fn object_id_for_bytes(encoded : Bytes) -> ObjectId {
  let digest = @sha256.Digest::new()
  for byte in encoded {
    digest.write(byte)
  }
  { hex: digest.check_sum(), }
}

///|
pub fn object_id_for(object : VcsObject) -> ObjectId raise VcsError {
  object_id_for_bytes(encode_object(object))
}

///|
pub fn decode_object(encoded : Bytes) -> VcsObject raise {
  let decoder = Decoder::new(encoded)
  if decoder.bytes(object_magic.length()) != object_magic {
    raise VcsError::InvalidObject("invalid object magic")
  }
  if decoder.byte() != 1 {
    raise VcsError::InvalidObject("unsupported object format version")
  }
  let kind = decoder.byte()
  let payload_length = decoder.u64()
  if payload_length > 2147483647UL ||
    payload_length.to_int() != decoder.remaining() {
    raise VcsError::InvalidObject("object payload length mismatch")
  }
  let payload = Decoder::new(decoder.bytes(payload_length.to_int()))
  let object = match kind {
    1 => BlobObject({ content: payload.bytes(payload.remaining()), })
    2 => {
      let count = payload.u32()
      let entries : Array[TreeEntry] = []
      for _ in 0..<count {
        let entry_kind = match payload.byte() {
          1 => BlobEntry
          2 => TreeEntry
          _ => raise VcsError::InvalidObject("invalid tree entry kind")
        }
        entries.push({
          name: payload.string(),
          kind: entry_kind,
          object_id: payload.object_id(),
        })
      }
      TreeObject(Tree::new(entries))
    }
    3 => {
      let tree_id = payload.object_id()
      let parent_count = payload.u32()
      let parents : Array[ObjectId] = []
      for _ in 0..<parent_count {
        parents.push(payload.object_id())
      }
      CommitObject({
        tree_id,
        parents,
        author: payload.string(),
        timestamp: payload.u64(),
        message: payload.string(),
      })
    }
    _ => raise VcsError::InvalidObject("unknown object kind")
  }
  if payload.remaining() != 0 {
    raise VcsError::InvalidObject("trailing bytes in object payload")
  }
  if encode_object(object) != encoded {
    raise VcsError::InvalidObject("noncanonical object encoding")
  }
  object
}

///|
fn verify_encoded_object(id : ObjectId, encoded : Bytes) -> Bool {
  if object_id_for_bytes(encoded) != id {
    return false
  }
  try decode_object(encoded) |> ignore catch {
    _ => return false
  }
  true
}
