# Contributing to MacWand

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and suggesting features

Use the [issue templates](https://github.com/ypankovych/macwand/issues/new/choose). For bugs,
please include your macOS version, your Mac's chip (Apple silicon or Intel), the MacWand version,
and the steps that reproduce the problem.

Please **don't** report security issues in public issues; see [SECURITY.md](SECURITY.md).

## Development setup

You need the Xcode Command Line Tools (`xcode-select --install`) and Rust
([rustup](https://rustup.rs)) with both Mac targets. Xcode is optional.

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
cargo test --manifest-path engine/Cargo.toml   # scanner tests
scripts/build.sh                               # build build/MacWand.app
open build/MacWand.app
```

## Guidelines

- **The scanner never deletes.** `engine` only reads sizes and reports them. All removal happens
  in the app, through the Trash, after a confirmation.
- **Keep it native and small.** SwiftUI and AppKit only in the app, a short dependency list in the
  engine, no networking.
- **Keep compatibility.** The app targets macOS 12. Guard newer APIs with `#available` and provide
  a fallback (see `Views/Theme.swift`). Both architectures are compiled for macOS 12, so unguarded
  APIs fail the build.
- **Keep the main thread free.** Anything that touches the disk runs in the engine or off the main
  actor; results are applied in batches.
- **Structure.** Scanning logic goes in `engine` with tests. In the app, `Model` holds state,
  `Services` talk to the system and `Views` only render.
- **Style.** Match the surrounding code: small focused types, dependencies passed in, doc comments
  on non-private API.
- **UI changes.** Regenerate the screenshots with `scripts/screenshots.sh` and include them in the
  pull request.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests where it makes sense.
3. Run `cargo test --manifest-path engine/Cargo.toml` and `scripts/build.sh`.
4. Add an entry under "Unreleased" in `CHANGELOG.md`.
5. Open the pull request and describe what changed and why.

## Releasing (maintainers)

1. Move the "Unreleased" changelog entries under the new version.
2. Tag the version and push the tag: `git tag v1.2.3 && git push origin v1.2.3`.
3. The *Release* workflow builds the app, DMG and zip and publishes a GitHub release with their
   SHA-256 checksums.
