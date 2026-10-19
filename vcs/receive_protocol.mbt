///|
let receive_magic : Bytes = b"MOONRX\x00\x00"

///|
let max_receive_bundle_bytes = 16777216

///|
let max_receive_objects = 4096

///|
pub(all) struct ReceivedObject {
  id : ObjectId
  encoded : Bytes
}

///|
pub(all) struct ReceiveRequest {
  ref_name : String
  expected_old : ObjectId?
  target : ObjectId
  objects : Array[ReceivedObject]
}

///|
pub struct ReceiveReport {
  ref_name : String
  target : ObjectId
  checked_commits : Int32
  promoted_objects : Int32
  policy_revision : String
}

///|
fn validate_receive_request(request : ReceiveRequest) -> Unit raise {
  if @utf8.encode(request.ref_name).length() > 1024 {
    raise VcsError::ReceiveInvalid("Ref name exceeds limit")
  }
  ignore(ref_path("/unused", request.ref_name))
  ignore(ObjectId::parse(request.target.hex))
  if request.expected_old is Some(id) {
    ignore(ObjectId::parse(id.hex))
  }
  if request.objects.length() > max_receive_objects {
    raise VcsError::ReceiveInvalid("too many received objects")
  }
  let seen : Map[String, Bool] = Map([])
  let mut size = 128 + @utf8.encode(request.ref_name).length()
  for item in request.objects {
    ignore(ObjectId::parse(item.id.hex))
    if seen.contains(item.id.hex) {
      raise VcsError::ReceiveInvalid("duplicate received ObjectId")
    }
    seen[item.id.hex] = true
    if item.encoded.length() > max_receive_bundle_bytes {
      raise VcsError::ReceiveInvalid("received object exceeds bundle limit")
    }
    size = size + item.encoded.length() + 68
    if size > max_receive_bundle_bytes {
      raise VcsError::ReceiveInvalid("receive bundle exceeds size limit")
    }
  }
}

///|
pub fn encode_receive_request(request : ReceiveRequest) -> Bytes raise {
  validate_receive_request(request)
  let encoder = Encoder::new()
  encoder.bytes(receive_magic)
  encoder.byte(1)
  encoder.string(request.ref_name)
  match request.expected_old {
    None => encoder.byte(0)
    Some(id) => {
      encoder.byte(1)
      encoder.object_id(id)
    }
  }
  encoder.object_id(request.target)
  encoder.u32(request.objects.length())
  for item in request.objects {
    encoder.object_id(item.id)
    encoder.u32(item.encoded.length())
    encoder.bytes(item.encoded)
  }
  let bytes = encoder.finish()
  if bytes.length() > max_receive_bundle_bytes {
    raise VcsError::ReceiveInvalid("encoded bundle exceeds size limit")
  }
  bytes
}

///|
pub fn decode_receive_request(bytes : Bytes) -> ReceiveRequest raise {
  try {
    if bytes.length() > max_receive_bundle_bytes {
      raise VcsError::ReceiveInvalid("bundle exceeds size limit")
    }
    let decoder = Decoder::new(bytes)
    if decoder.bytes(8) != receive_magic || decoder.byte() != 1 {
      raise VcsError::ReceiveInvalid("unsupported receive protocol")
    }
    let ref_name = decoder.string()
    let expected_old = match decoder.byte() {
      0 => None
      1 => Some(decoder.object_id())
      _ => raise VcsError::ReceiveInvalid("invalid expected-old flag")
    }
    let target = decoder.object_id()
    let count = decoder.u32()
    if count > max_receive_objects {
      raise VcsError::ReceiveInvalid("too many received objects")
    }
    let objects : Array[ReceivedObject] = []
    for _ in 0..<count {
      let id = decoder.object_id()
      let encoded = decoder.bytes(decoder.u32())
      objects.push({ id, encoded, })
    }
    if decoder.remaining() != 0 {
      // No client-supplied policy result/configuration/extra command is accepted.
      raise VcsError::ReceiveInvalid("trailing receive data")
    }
    let request : ReceiveRequest = { ref_name, expected_old, target, objects, }
    validate_receive_request(request)
    request
  } catch {
    _ => raise VcsError::ReceiveInvalid("invalid or oversized receive bundle")
  }
}

///|
pub async fn prepare_receive_request(
  source : Repository,
  ref_name : String,
  expected_old : ObjectId?,
  target : ObjectId,
) -> ReceiveRequest {
  let graph = inspect_receive_graph(source.store, target)
  let objects : Array[ReceivedObject] = []
  for id in graph.ordered {
    objects.push({ id, encoded: encode_object(source.store.get(id)), })
  }
  let request : ReceiveRequest = { ref_name, expected_old, target, objects, }
  validate_receive_request(request)
  request
}

///|
pub async fn receive_bundle_file(
  server : Repository,
  path : String,
) -> ReceiveReport {
  let request = decode_receive_request(
    read_bounded_storage_file(path, max_receive_bundle_bytes),
  ) catch {
    _ => raise VcsError::ReceiveInvalid("unreadable or invalid receive bundle")
  }
  receive_candidate(server, request)
}
