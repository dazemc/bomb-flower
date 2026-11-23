# Contributing to Bomb Flower

Bomb Flower is a save editor and save creator for the Ocarina of Time Switch 2
remake saves that Longshot reads. It is a Flutter desktop application around a
pure-Dart save engine: the engine parses, validates, edits, and exports save
bytes through a testable API, and the Flutter shell is wired to it. The target
is **Linux desktop only**. There is no `windows/` or `macos/` runner, Windows
and macOS are untested, and a change that happens to work on another platform
does not make that platform supported. See [`docs/BUILD.md`](docs/BUILD.md).

This is a single-maintainer project with no CI workflow. Expect review to be
irregular. What follows is what a change has to satisfy, not a promise about
how quickly it will be looked at.

## Evidence first: the save format is not the N64 format

`progress.sav` is not the N64 Ocarina of Time format, and the N64 offsets,
defaults, checksum scheme, and field meanings do not transfer to it. What is
actually on disk:

- a 40-byte header at `0x00`: magic `0x01020304`, schema revision `2982123` at
  byte 4, a tail offset at byte 8, and 28 reserved bytes;
- 11,958 eight-byte `{u32 Murmur3_x86_32(name, seed 0), u32 value}` records
  starting at `0x28`: 11,925 fields, 32 sentinels, one footer;
- no checksum or integrity field has been found. The probes and their results
  are in section 7 of [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md);
- 3,608 of the 11,925 on-disk fields have a verified name. The other 8,317
  exist as hashes only, with `"name": null`.

Rules for format work:

- **Verify against the game and the samples.** An offset is a claim about
  bytes. Check it against the samples, and against the game where the game is
  the only witness, before it becomes a descriptor.
- **Never assume an N64 offset or an N64 default.** Do not import a value or a
  layout because "OoT does it this way". If the only evidence is another
  project or another version, it is not evidence here.
- **Preserve unknown bytes.** Write back every byte you did not intend to
  change, including the footer, the reserved header bytes, and unknown tail
  spans.
- **Keep unverified fields read-only.** A hash-only field stays read-only until
  something proves its meaning. Do not add a write path "to see what happens".
- **Cite the source next to every new offset.** The descriptor is the
  documentation: record where the number came from, and what was observed.

Read [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md) for the container, sections,
value encodings, and provenance, [`lib/domain/save/progress_layout.dart`](lib/domain/save/progress_layout.dart)
for the verified byte layout the adapter builds its descriptors from, and the
enforced layering and file placement rules in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### A round-trip test is not game acceptance

A codec test proves that bytes survive a decode and encode unchanged. It does
not prove that the game loads the result. The only game-acceptance evidence is
a one-off external run against a local game build: a two-byte edit, one byte
each to `Life` and `MaxLife`. It cannot run here, because neither the game
binary nor its assets are committed. The procedure, its limits, and what it
does not cover are in the "Compatibility gate" section of
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); the open gaps are in
[`docs/LIMITATIONS.md`](docs/LIMITATIONS.md). In particular, **no created save
has ever been loaded by the game**. Do not describe a round-trip test, a byte
comparison, or a successful build as acceptance.

## Tests are mandatory

A change without tests is incomplete, whatever the change is: a new field, a
new parse path, a new widget, a bug fix. The test has to fail before the fix
and pass after it.

- **Do not add new `skip:` stubs.** Two exist, both in
  [`test/domain/engine/roundtrip_invariants_test.dart`](test/domain/engine/roundtrip_invariants_test.dart),
  for the zero-edit round-trip and exact edit-span invariants. They are
  declared known gaps. They are not passing tests and must never be reported as
  passing; the real-format behaviour they describe is covered by
  `test/data/adapter/` and `test/integration/` instead.
- **This repository has no CI workflow.** Nothing runs on push. The gate is run
  locally and its output pasted into the pull request or the commit message.
  That pasted output is the evidence.
- **`.local-fixtures/` is absent by default.** It is gitignored and filled by
  `dart run tool/make_fixtures.dart` from scrubbed samples. Codec and
  integration tests that need the samples skip when it is missing, so a run
  without fixtures reports more skips and a lower pass count. That is not a
  failure.
- **A skip added to dodge a failure is not the same thing.** A missing fixture
  is an environment fact; a `skip:` on a test that would otherwise fail is
  hiding a defect. If a fixture-dependent job is ever added to CI, a job that
  skips every time it runs is not coverage.

If you cannot get a test to pass, report the failure and its output. That is a
useful contribution; a suite that passes because the assertion was weakened is
not.

## Never weaken an assertion to make a suite pass

Do not loosen a matcher, widen a tolerance, delete a case, mark a test skipped,
or change a fixture to match the new behaviour. If an existing test fails, one
of the two is wrong, and finding out which is the work. Report the failure with
its output rather than adjusting the test around it.

## Layering

The layers are enforced by a source-level test,
[`test/architecture/layering_test.dart`](test/architecture/layering_test.dart),
which scans every `import` and `export` and fails with file and line:

- `lib/domain/` may not import `package:flutter/`, `package:flutter_bloc/`,
  `package:bloc/`, `package:material_ui/`, `package:bitsdojo_window/`,
  `package:equatable/`, `dart:io`, or `dart:ui`.
- `lib/data/` may not import `package:flutter/`, `package:flutter_bloc/`,
  `package:bloc/`, `package:material_ui/`, or `package:bitsdojo_window/`. The
  test does **not** restrict `dart:io`, `dart:ui`, or `package:equatable/` in
  this layer.
- `lib/presentation/` may not import `dart:io`.

The asymmetry follows from the design. `lib/data` is where `dart:io` belongs:
it implements the `SlotSource` and `OriginalStore` ports declared in
[`lib/domain/engine/ports.dart`](lib/domain/engine/ports.dart), so file access
lives there rather than in the engine. Files under `lib/data/io/`,
`lib/data/system/`, `lib/data/newsave/`, and
`lib/data/adapter/progress_layout_resolver.dart` import `dart:io`; `lib/domain`
stays pure Dart so the engine can be tested without a filesystem.

Presentation reaches the engine through cubits in `lib/presentation/bloc/`; it
does not open files itself. Matching is a substring test on each `import` or
`export` URI, and deleting a layer directory also fails the test.

For "where does this file go?", use the table in the "Where does new code go?"
section of [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). It is the maintained
answer, including the evidence each location requires; it is not repeated here
so that it cannot drift.

## The gate

Run from the repository root, in this order:

```sh
flutter pub get
dart format .
flutter analyze
flutter test
```

`flutter analyze` is expected to report `No issues found!`. If it reports
anything else, fix it; do not adjust `analysis_options.yaml` to silence it.

A change that touches `linux/` or the window runner also needs:

```sh
flutter build linux --debug
```

The prerequisites, the headless smoke test, and the release build are in
[`docs/BUILD.md`](docs/BUILD.md). Do not quote a pass count from an older gate
as if it were current: the figures in the docs were recorded at specific
commits and are stale relative to `HEAD`.

## Commits

- Conventional Commits with a scope, e.g. `feat(engine):`, `fix(ui):`,
  `test(integration):`, `docs(fields):` (all four appear in the history). A new
  scope such as `docs(build):` or `test(adapter):` is fine.
- Stage only your own paths. Do not `git add -A`; a path-scoped stage keeps
  someone else's in-progress work out of your commit.
- One concern per commit. A format fix and a theme tweak are two commits.
- No drive-by reformatting of files you did not need to change, even if
  `dart format .` touched them. Check `git status` before you stage.
- Fast-forward pushes only. Never force-push and never rebase published
  history.
- Do not amend a commit that has already been pushed.

## Never commit game data

Save files, ROMs, memory-card dumps, and anything copied out of the game are
local inputs, not repository content. `.gitignore` already blocks `*.sav`,
`*.sra`, `*.srm`, `*.st0`, `*.eep`, `*.fla`, `*.mpk`, `*.z64`, `*.n64`,
`*.v64`, `*.rom`, and the whole `.local-fixtures/` directory. Do not add an
exception for a real file.

Test fixtures must be synthetic or scrubbed, and belong under
`test/fixtures/`, which `.gitignore` re-includes for exactly this purpose. A
fixture that contains copyrighted game assets, artwork, audio, or a personal
save is not acceptable even if it is small.

## The Longshot boundary

Longshot at `/home/daze/GitHub/Longshot` is a separate project and is strictly
read-only for Bomb Flower work: no writes, no formatting, no builds, no test
runs, and no `git` mutation of any kind there. Do not make this project's build
or tests depend on a checked-out Longshot path. No pull request from this
repository may target Longshot. The rules and the reason are in
[`docs/LONGSHOT-BOUNDARY.md`](docs/LONGSHOT-BOUNDARY.md).

## Licence

Bomb Flower is released under the MIT License — the full text is in
[`LICENSE`](LICENSE). Contributions are accepted under the same licence:
inbound equals outbound, and no CLA is required. If a change cannot be
contributed on those terms, raise it in the issue before you start on it.

## Where to discuss and report

GitHub Issues is the only channel this repository has; Discussions is
disabled. Open an issue for a bug report, a format question, or a proposal.

Do not report a security issue in a public issue. The private channel and the
scope are in [`SECURITY.md`](.github/SECURITY.md).
