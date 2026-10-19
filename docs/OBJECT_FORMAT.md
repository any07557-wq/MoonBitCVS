# MoonVCS object format v1

Status: implemented and tested on 2026-10-17. This format is independent of the
policy WIT ABI. It is not Git's loose-object format.

## Object identity and envelope

`ObjectId = lowercase_hex(SHA256(encoded_object))`. Every stored file contains
exactly the bytes that are hashed, without compression or a second wrapper.

| Offset | Size | Meaning |
|---|---:|---|
| 0 | 8 | Magic `MOONVCS\0` (`4d4f4f4e56435300`) |
| 8 | 1 | Format version: `01` |
| 9 | 1 | Type: Blob `01`, Tree `02`, Commit `03` |
| 10 | 8 | Unsigned big-endian payload byte length |
| 18 | declared length | Type-specific payload |

The type byte and payload length are part of the hash. Identical raw payloads
under different types have different identities, subject to SHA-256's collision
resistance. Object IDs are exactly 64 lowercase ASCII hex characters. API callers
construct IDs through `ObjectId::parse`, not arbitrary strings.

### Collision and authenticity assumptions

SHA-256 is the 256-bit digest algorithm specified by
[NIST FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final). MoonVCS uses
the complete digest, without truncation, for an established portable algorithm
and simple independent verification. This is not a certification of this
implementation or a proof that collisions are impossible. Under an ideal
256-bit hash model, the birthday collision probability for n distinct encodings
is approximately n(n-1)/2^257 when that probability is small. That estimate is a
cryptographic assumption, not a property proven by the test suite.

Type/version/length framing removes serialization ambiguity; it does not remove
the hash collision assumption. A successful chosen collision/preimage attack
could undermine object identity. No collision-recovery format or algorithm
negotiation is implemented; a future algorithm change requires a versioned
migration, not silently interpreting a different digest as SHA-256.

Hashes establish byte integrity, not who authored a Commit, whether a Ref is
authorized, whether a Blob is safe, or whether the entire graph is available.
Partial clones deliberately allow absent promised historical objects. Receive
separately validates complete graphs and required policies before Ref publication.
Cycle traversal defense is tested with an explicitly synthetic ObjectStore;
the suite does not pretend to create a valid cyclic SHA-256 fixed-point graph.

## Primitive encodings

- `u32`: four unsigned big-endian bytes. Version 1 currently accepts only values
  `0..2147483647`, matching MoonBit's in-memory lengths.
- `u64`: eight unsigned big-endian bytes.
- `string`: `u32(UTF-8 byte length)` followed by exactly those UTF-8 bytes. No
  terminator, BOM removal, newline conversion, or Unicode normalization is used.
- `id`: exactly 64 ASCII bytes; no length prefix.
- Arrays: `u32(element count)` followed by the encoded elements in order.

Malformed UTF-8, oversized lengths/counts, truncation, unknown types/versions,
trailing bytes, invalid IDs, and noncanonical object encodings are rejected.
Decoders re-encode and require byte equality. Canonical Tree sorting is therefore
enforced on incoming objects as well as on locally created objects.

## Payloads

Blob: the raw file bytes, including zero bytes, binary data, and empty content.

Tree:

```text
u32(entry_count)
repeat entry_count:
    u8(kind)           # Blob entry = 1, Tree entry = 2
    string(name)       # one directory component
    id(object_id)
```

Entries sort lexicographically by unsigned UTF-8 bytes of the name; when one
name is a prefix of another, the shorter name sorts first. Duplicate names and
empty names, `.`, `..`, `/`, `\`, or NUL in names are rejected. Directories refer
to other Trees; files refer to Blobs. Empty directories are not staged by the
filesystem adapter. No executable bit, ownership, or symlink mode is stored.

Commit:

```text
id(tree_id)
u32(parent_count)
repeat parent_count:
    id(parent_id)
string(author)
u64(timestamp)          # Unix epoch milliseconds
string(message)
```

Parent order is significant. The model accepts multiple parents; the MVP CLI
creates zero-parent roots and one-parent successors. `log` follows the first
parent. Referenced objects are not embedded. `put`/`verify` check the current
object, not the transitive graph; the implemented promised-object store can therefore
represent commits whose historical objects are not local yet.

## Known hash vectors

These values were independently computed with Python `hashlib`; the CLI test
also compares every actual object filename with `sha256sum` of the file.

| Object | Complete encoded bytes (hex) | Object ID |
|---|---|---|
| Empty Blob | `4d4f4f4e5643530001010000000000000000` | `3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7` |
| Blob `hello\n` | `4d4f4f4e564353000101000000000000000668656c6c6f0a` | `a255789328a6ba5556b5f55d01dc72a70dc3970dd4c5d92cd82f9925df130dbf` |
| Blob: four zero bytes | `4d4f4f4e564353000101000000000000000400000000` | `9739581cae3d71824298d6b68d0978b9d7a69d7150530af684a66cde7d0596fd` |
| Empty Tree: payload is four zero bytes | `4d4f4f4e564353000102000000000000000400000000` | `854955a81ec425451f4d78c00589900a817a2846c0fdf9e628ddd3fa0759f3a7` |

Reproduce the empty Blob vector independently:

```bash
printf '4d4f4f4e5643530001010000000000000000' | xxd -r -p | sha256sum
```

## Local repository metadata

The filesystem adapter maps ID `abcdef...` to
`.moonvcs/objects/ab/cdef...`. This layout is not part of `ObjectStore`'s interface.
Objects are written through a unique same-directory temporary file, synced, and
renamed without replacement. Existing corrupt objects are rejected, never
silently replaced. Concurrent writers of identical valid content may share the
already installed object.

Phase 5 uses exactly this encoding and ID rule on local caches and filesystem
remotes. No hash, object tag or envelope change was made. Partial-clone origin,
typed promises and accounting are separate versioned adapter metadata described
in [LAZY_STORAGE.md](LAZY_STORAGE.md); they are not part of object identity.

The local index is an independent binary file:

```text
"MOONIDX\0" || u8(1) || u32(entry_count)
repeat entry_count, in lexicographic UTF-8 path order:
    string(repository_relative_path)
    id(blob_id)
```

The index is the complete staged snapshot, not only a list of changes. Missing
tracked paths supplied to `add`, or missing paths within an added directory,
are removed from it. Empty/duplicate/noncanonical index paths are rejected.

`HEAD` contains `ref: refs/heads/main\n`. A branch ref contains one 64-character
Commit ID followed by `\n`; refs and index are mutable metadata, not hashed
objects. Ref publication uses exclusive `<ref>.lock` creation, an expected-old
ID check, file sync, and atomic rename. See [policy boundary](POLICY_ENGINE.md)
for failure behavior and [limits](KNOWN_LIMITATIONS.md) for crash durability.
