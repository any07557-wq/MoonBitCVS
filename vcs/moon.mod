name = "any07557-wq/moonvcs"

version = "0.1.0"

license = "Apache-2.0"

readme = "README.md"

repository = "https://github.com/any07557-wq/MoonBitCVS"

description = "Native MoonBit VCS core with typed SHA-256 objects, lazy storage and policy boundaries."

keywords = [ "version-control", "content-addressed-storage", "wasm", "moonbit" ]

preferred_target = "native"

supported_targets = "native"

import {
  "gmlewis/sha256@0.18.0",
  "moonbitlang/async@0.20.2",
}
