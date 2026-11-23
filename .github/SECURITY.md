# Security policy

## What this project is

Bomb Flower is a save editor and save creator for Longshot's Ocarina of Time
Switch 2 remake saves. It reads a `slot_NN` folder you already have and writes
an export through an atomic path. It never modifies the game, never modifies a
game installation, never downloads code, and ships no ROMs, game assets, or
save data. It is a single-maintainer project with no CI workflow and no
security team.

## Reporting

Use GitHub's private vulnerability reporting for this repository: the
**Security** tab, then **Report a vulnerability**. It is the only disclosure
channel. There is no security email and no GPG key; please do not send one.

Do not open a public issue containing vulnerability details.

If the "Report a vulnerability" button is not visible, private reporting has
not been enabled on the repository yet. In that case open an issue that
contains no vulnerability details, and say only that you have a security report
and need a private channel.

## In scope

- The save engine: parsing, validation, and editing of `progress.sav` and the
  sidecar files (`lib/domain/`, `lib/data/codec/`).
- The atomic export path (`lib/data/io/atomic_file_writer.dart`): staging,
  rename, and the rollback of an already-renamed target on failure.
- The file adapter and folder handling (`lib/data/io/`, `lib/data/system/`),
  including the refusal to write through a symlink or over a directory, and
  path handling when a folder is opened.
- Malformed or hostile save input that causes a crash, a hang, or an
  out-of-bounds read rather than a typed error.

## Out of scope

- The game itself, and any behaviour of the game or console that runs it.
- Longshot, which is a separate project; report issues there.
- Third-party save data you obtained elsewhere, including saves edited by
  another tool.
- Anything that requires modifying a game installation to demonstrate.

## Please do not attach

Do not attach a personal save file, a ROM, a memory-card dump, or any game
asset to a report. None of them are needed to describe a defect.

If a save is what reproduces the issue, redact it first: strip or zero the
fields you consider personal, keep only the bytes around the affected offset,
and say which offset the report is about. A synthetic file built to the same
shape is usually enough, and is preferred.

## Response

There is no response-time commitment. Reports are handled by the maintainer
when available, and a fix ships when it ships. If a report needs disclosure
before a fix exists, coordinate that through the advisory itself.

## Supported versions

The repository's `main` branch is the only version. There are no release
branches or backports.
