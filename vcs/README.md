# MoonVCS Core

Native MoonBit source module for the MoonVCS research prototype: typed Blob,
Tree and Commit objects, canonical SHA-256 encoding, object stores, lazy history,
and repository operations with policy validation boundaries.

Candidate module: `any07557-wq/moonvcs@0.1.0`, prepared for the maintainer's
confirmed Mooncakes username `any07557-wq`. **Not published yet**; authenticated
publication permissions and version availability remain unverified. A local
package archive is not a published release; do not assume
`moon add any07557-wq/moonvcs` is available.

## Scope

The module contains the MoonBit core and native CLI source. It does not ship
the Rust/Wasmtime Host, compiled Wasm policies, WIT, runtime configuration,
toolchain archives, or a prebuilt `moonvcs` executable. Installing this module
alone does not provision the complete policy-enforced VCS.

Use the [full source repository](https://github.com/any07557-wq/MoonBitCVS) and its
[installation instructions](https://github.com/any07557-wq/MoonBitCVS/blob/main/INSTALL.md)
for the end-to-end CLI and policies. The repository-only bypass test client is
excluded from this module archive; it remains available in the repository tests.

## Minimal library example

After making the module available as a local dependency (or after its actual
publication under a confirmed namespace), import it in your `moon.pkg`:

```moonbit
import {
  "any07557-wq/moonvcs" @vcs,
}

pkgtype(kind: "executable")
```

```moonbit
fn main {
  try {
    let id = @vcs.object_id_for(@vcs.BlobObject({ content: b"", }))
    println(id.to_string())
  } catch {
    _ => println("object encoding failed")
  }
}
```

The empty Blob ID is
`3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7`.
It hashes MoonVCS's typed encoding, not just the empty payload and not Git's
object encoding.

## Compatibility and limitations

- Native backend; verified in Linux x86-64 environments. This is not a claim of
  browser, JS, Wasm-GC or cross-platform support for the entire module.
- Candidate 0.1.0 API is experimental, not a stable production API commitment.
- Real repository commits/receives need a valid policy context and external
  Host/plugins. Do not replace required policy validation with a mock validator.
- Included white-box tests also contain repository integration tests requiring
  the full repository and built runtime. A standalone module check/build is not
  a standalone pass of the complete test suite.
- File-system/stdio remotes have no authentication, ACL, TLS or server OS
  privilege separation. This is not a production Git replacement.

For test evidence and security boundaries see the repository's
[CI validation](https://github.com/any07557-wq/MoonBitCVS/blob/main/docs/CI_VALIDATION.md)
and [SECURITY.md](https://github.com/any07557-wq/MoonBitCVS/blob/main/SECURITY.md).
The CI result applies to its recorded commit, not automatically to this later
packaging preparation.

## License

Apache-2.0; the module includes the same LICENSE notice as the repository.
