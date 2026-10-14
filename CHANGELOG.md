# Changelog

All notable changes to MacWand are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The overview's "files checked" summary showed zero when a scan finished between progress updates.

### Changed

- Items whose file is already gone show the icon for their kind instead of a blank document.

## [0.1.0] - 2026-10-14

First public release.

### Added

- Parallel Rust scanner that streams findings while it walks the home folder.
- Large files (100 MB+), app caches, logs, Xcode data, package-manager caches, iPhone backups,
  Mail attachments, Downloads and the Trash.
- Build-artifact detection: `node_modules`, Rust `target`, Python virtualenvs, CocoaPods, `.next`
  and `.terraform`, listed by project.
- Applications with last-used dates and their support files in `~/Library`; uninstalling removes
  both. Running apps are skipped.
- Overview with disk usage, a chart of reclaimable space and a card per finding.
- Sortable tables, size charts, Reveal in Finder and keyboard shortcuts.
- Every removal is confirmed and goes to the Trash.
- Universal app for macOS 12 and later, distributed as a DMG and a zip.

[Unreleased]: https://github.com/ypankovych/macwand/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ypankovych/macwand/releases/tag/v0.1.0
