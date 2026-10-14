# MacWand

A native macOS app that finds what's taking up space and helps you clear it:
large files, app caches, logs, Xcode data, package-manager caches, build folders
(`node_modules`, Rust `target`, virtualenvs…), Downloads, the Trash, and apps you
haven't used in months together with the support files they leave in `~/Library`.

Nothing is deleted without confirmation. Removed items go to the Trash; only items
already in the Trash are deleted permanently.

## Download

Get the latest `MacWand-<version>.dmg` from
[Releases](https://github.com/ypankovych/macwand/releases/latest), open it and drag
MacWand to Applications.

Runs on **macOS 12 Monterey and later**, on both Apple silicon and Intel Macs.
Some extras only appear on newer systems: the rolling numbers and clicking a
donut slice need macOS 13, the pulsing icon needs macOS 14.

### First launch

The app is not notarized by Apple, so macOS blocks it the first time:

- **macOS 15 and later:** open MacWand, click **Done** on the warning, then go to
  System Settings → Privacy & Security, scroll down and click **Open Anyway**.
- **macOS 12–14:** right-click MacWand in Applications, choose **Open**, then **Open**
  again in the dialog.

Or clear the quarantine flag from Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/MacWand.app
```

## Layout

```
engine/   Rust scanner (rayon). Walks the home folder in parallel and streams JSON lines.
app/      SwiftUI app (macOS 12+). Runs the engine as a helper and renders results.
scripts/  build.sh (builds the app), package.sh (DMG + zip), make-icon.swift (regenerates the icon).
```

The engine never deletes anything. It reports:

- `large_file`: files of 100 MB or more (`--min-large BYTES` to change)
- `category` / `category_item`: the direct children of known cleanup folders, plus
  detected build-artifact folders
- `app`: every `.app` in `/Applications` and `~/Applications` with its size
- `size`: sizes of per-app folders in `~/Library`, used to size uninstall leftovers
- `progress` and `done`

Sizes are allocated blocks (`st_blocks`), so sparse files and evicted iCloud files
count for what they really use, and hard links are counted once.

## Build

Needs the Xcode Command Line Tools and a Rust toolchain (rustup) with both Mac
targets. Full Xcode isn't required: SwiftPM doesn't work with the Command Line Tools
alone, so the build script calls `swiftc` directly.

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
./scripts/build.sh          # -> build/MacWand.app (universal, macOS 12+, ad-hoc signed)
./scripts/package.sh        # -> build/MacWand-<version>.dmg and .zip
open build/MacWand.app
cd engine && cargo test     # engine tests
```

The deployment target is macOS 12. Newer SwiftUI APIs are used only behind
`#available` checks (see `Views/Theme.swift`), so the compiler flags any unguarded use.

Run the engine on its own:

```sh
cargo run --release --manifest-path engine/Cargo.toml -- scan | head
cargo run --release --manifest-path engine/Cargo.toml -- sizes ~/Library/Caches
```

## Notes

- **Full Disk Access** gives a complete scan (Mail, Safari, other apps' containers).
  Without it macOS hides those folders and asks once each about Desktop, Documents
  and Downloads. The app links to the setting.
- **App containers are slow to read.** macOS checks access for every folder inside
  `~/Library/Containers`, one at a time across the whole system, at about 10 ms per
  folder. No API avoids this. Everything else finishes in seconds, and results
  stream in while the container walk completes.
- **Photos libraries are skipped.** Reading inside a `.photoslibrary` triggers a
  Photos privacy prompt, and Photos manages that storage itself.
- **"Last used"** is the later of Spotlight's last-used date and the last time the
  app's executable was read. Spotlight data is often missing.
