# VCS demo input

Copy this directory to a scratch location, build the native CLI with
`scripts/build-vcs.sh`, then run:

```bash
moonvcs init
moonvcs add .
moonvcs status
moonvcs commit -m "initial"
moonvcs log
moonvcs show HEAD
```

The example intentionally contains a nested directory. Empty, binary, and
Unicode-named files are covered by the automated MoonBit integration tests.
