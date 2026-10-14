# Security policy

MacWand removes files, so bugs that could remove the wrong thing are treated as security issues.

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through
[GitHub private vulnerability reporting](https://github.com/ypankovych/macwand/security/advisories/new).

Please include:

- what could happen, and under what conditions;
- steps or a proof of concept to reproduce it;
- your macOS version and the MacWand version.

You will get a reply within a week. Once a fix is released, you'll be credited in the release
notes unless you'd rather stay anonymous.

## Safety model

What MacWand guarantees:

- **No removal without confirmation.** Every removal goes through a confirmation that names what
  will be removed and how much space it takes.
- **The Trash first.** Items are moved to the Trash, where they can be restored. Only items already
  in the Trash are deleted permanently.
- **A read-only scanner.** The `macwand-engine` helper has no code that writes, moves or deletes
  files.
- **No network access** and no data collection.

What it does not protect against:

- Removing something you still need after confirming. Sections marked *review before removing*
  (Large Files, Downloads, backups, archives) can hold important data.
- Apps that store data somewhere unexpected: uninstalling only removes the support files MacWand
  can match to the app's bundle identifier or name.
