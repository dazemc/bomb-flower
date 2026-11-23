# AGENTS.md — Bomb Flower

Flutter Linux-desktop save editor/creator for Longshot's Ocarina of Time Switch-2 remake saves. The pure-Dart save engine is the product and the UI is a client of it: read `docs/ARCHITECTURE.md` before moving code, `docs/SAVE-FORMAT.md` before touching bytes, `docs/LIMITATIONS.md` before claiming something works.

## This file is maintained, not archival

- When a change alters a command, the layering, a save-format invariant, the package set, the tooling, or the Longshot boundary, update this file in the same commit.
- If a line here disagrees with the code, fix the line — do not route around it, and do not leave a stale claim standing because it was once true.

## Toolchain

- Flutter 3.50.1 / Dart 3.14.0 at `/home/daze/.local/opt/flutter/bin`; plain `flutter` and `dart` on PATH already resolve there, so no wrapper is needed.
- Linux desktop is the only target: `flutter doctor`'s `[✗] Android toolchain` and `[✗] Chrome` are irrelevant, and `[✓] Linux toolchain` is the gate.
- Gate from the repo root, in order — `flutter analyze` must print exactly `No issues found!`, and `analysis_options.yaml` is never relaxed to get there: `flutter pub get` · `dart format .` · `flutter analyze` · `flutter test`
- `flutter analyze` must be clean before any commit. This checkout is shared with other workstreams, so a dirty tree and in-flight, possibly non-compiling files are normal here: re-run the gate yourself instead of trusting the last result anyone reported.
- Touching `linux/` also needs `flutter build linux --debug`.
- **There is no CI.** `.github/workflows` does not exist; paste the gate output into the commit or PR, because it is the only evidence.

## Tests

- 105 `*_test.dart` files under `test/` (116 Dart files under `test/`, all tracked), and the whole suite is headless: no `@Tags`, no `integration_test`, no display.
- One file: `flutter test test/data/progress_codec_test.dart`. One test: `flutter test test/architecture/layering_test.dart --plain-name 'domain is pure Dart'`.
- Slowest: every test in `test/presentation/dialogs/open_save_picker_test.dart` and `open_save_dialog_test.dart` sets `Timeout(Duration(seconds: 30))`.
- `.local-fixtures/` is gitignored yet present here (3 scrubbed samples + `real/`), rebuilt by `dart run tool/make_fixtures.dart`; where it is absent the fixture groups skip, and a lower `+N` with a higher `~N` is not a failure. Override with `BOMB_FLOWER_LONGSHOT_SAVES` / `BOMB_FLOWER_REAL_SAVES`; on a clone with no retail saves, `test/audit/new_save_test.dart` skips 1 test, `test/audit/validation_bounds_test.dart` skips 6, and `test/audit/real_save_roundtrip_test.dart` skips 5, each with an explicit reason, while a broken `BOMB_FLOWER_REAL_SAVES` override fails instead of skipping.
- `test/domain/engine/roundtrip_invariants_test.dart` is no longer skipped: it asserts byte-identical reserialisation of two real played slots (122,852 and 122,940 bytes — not the synthetic 120,572-byte new save), a one-byte `PlayerStatus.Life` 16→20 diff, and that the reserved `[0x0C, 0x28)` gap that no field span claims plus an opaque tail span stay untouched; it copies real saves from `~/.local/share/longshot/...` into a fresh directory under `.tmp/`. Never weaken, skip, or delete those assertions.
- Never weaken an assertion, delete a case, or edit a fixture to make a suite pass; report the failure with its output instead.
- `.tmp/` here holds 3,558 scratch Dart copies: exclude it from every glob, grep, and count or the answer is wrong.

## Build and run

- `flutter run -d linux`, or `flutter build linux --debug` then `./build/linux/x64/debug/bundle/bomb_flower` (the release bundle drops `/debug/`). Run from `bundle/`, never an intermediate `build/` dir.
- Headless smoke test, where exit `124` means it stayed alive and therefore passed: `xvfb-run -a --server-args='-screen 0 1400x900x24' timeout 15 ./build/linux/x64/debug/bundle/bomb_flower`
- `linux/runner/my_application.cc` commits four `bitsdojo_window` lines (the include, a comment, `bitsdojo_window_from(window)` and `setCustomFrame(true)`); regenerating `linux/` drops them and the window reverts to a native frame.
- New save has two entry points: the CLI `dart run tool/create_save.dart --out /tmp/new-save`, and an in-app dialog reachable from the title bar's `New save…` action and the no-save empty state's `Create new save` link. Both run the same `NewSaveBuilder` + `NewSaveWriter`, which writes one fixed `slot_00` pair (a 120,572-byte `progress.sav` plus `caption.sav`), asks before replacing a non-empty folder and keeps `.bak` copies, and **no created save has been loaded by the game**. The in-app dialog works with a save already open: it is never pre-filled with that save's folder, refuses it as a *reserved* destination (`NewSaveDialog.reservedRootError`) before writing anything, and is create-then-open — a clean project opens the new save directly, a dirty one raises `UnsavedChangesDialog` first, and Cancel keeps the current save open while a toast names the created path. Only that confirmed Discard branch calls `openPath(..., discardUnsavedChanges: true)`; every other open keeps the dirty refusal.

## Architecture

- `lib/domain` is pure Dart, enforced at source level by `test/architecture/layering_test.dart`: no `package:flutter/`, `flutter_bloc`, `bloc`, `material_ui`, `bitsdojo_window`, `equatable`, `dart:io`, `dart:ui`. Zero such imports exist today. `lib/data` may not import UI/bloc packages, `lib/presentation` may not import `dart:io`, and deleting a layer fails it too.
- Bytes and file access therefore live in `lib/data/{io,codec,adapter,system}`; `SaveSessionCubit` is the only route from UI to engine and owns no offsets.
- The save-root resolver (`resolveProfilePath` in `lib/data/system/profile_path.dart`) accepts four shapes: a `progress.sav` file path, a slot folder that directly holds `progress.sav`, a profile folder, and a bare `save/` root; every resolved result is the profile folder (the openable root whose child holds `progress.sav`), never a slot. A slot is identified by holding `progress.sav`, never by a `slot_NN` name — `DirectoryEntry.isSlotDirectory` stays the pure name-shape fact used for picker navigation, not slot identity. A bare root with several profiles is `ProfilePathAmbiguous` with sorted, unmodifiable candidate profile paths, never a guess; a folder with no `progress.sav` beneath it is rejected by name rather than the old generic shape error. Discovery beneath a save root is bounded to three directory levels and 64 listed directories, directories only.
- progress.sav has no static layout: `ProgressLayoutResolver` + `ProgressLayoutBuilder` derive a per-file `LayoutDescriptor` and hand it to `SaveEngine.open`, so `SaveFormat.layoutFor(version)` is *not* its open path.
- Header, 40 bytes: magic `0x01020304`, revision `2982123` at `0x04`, tail `u32@0x08` (`0x175d8`), reserved `0x0c–0x27` zero; then `{u32 Murmur3(name) key, u32 value}` × 11,958 = 11,925 fields + 32 sentinels + 1 footer. Codec `lib/data/codec/progress_codec.dart`, table `lib/domain/save/progress_layout.dart`; a different revision is rejected, not guessed.
- Schema `assets/schema/gamedata_110.json` (7.2 MB, hash-verified from `GameDataList.Product.110`, `recordIndex` order from the samples): 3,608 named fields, 8,317 hash-only.
- `package:material_ui` is the Material 3 import here and `lib/` never imports `package:flutter/material.dart`. Tabs are a `ShellTab` switch in `lib/presentation/shell/app_shell.dart`; `v1_gap_panel.dart` survives but nothing constructs it.
- Two shell surfaces are session-independent: the static help sheet (`lib/presentation/widgets/help/help_surface.dart`, bound to F1 and the title-bar Help button) and the new-save dialog (`lib/presentation/dialogs/new_save_dialog.dart`, reachable from the title bar and the no-save empty state). `HelpScope` and `NewSaveScope` hand their openers to tab content, so a tab's `EmptyState` offers both links without importing the shell.

## Save-format rules — breaking these corrupts a save

- Unknown bytes round-trip exactly, `preserveUnknown` stays `true`, and only the 4-byte value word of an edited field is patched. Never reorder, insert, or delete records; never touch header or reserved bytes; preserve sentinels and the footer verbatim.
- There is no checksum — do not invent one. The footer `{2749067540, 120564}` is `filesize − 8` and otherwise opaque: preserve it, never recompute it.
- `Binary`/`BinaryArray`/`WString16Array` spans are inferred and opaque, so no typed editing; for arrays keep the stored count and edit existing elements only.
- Hash-only fields stay read-only; only named, verified fields get a write path.
- Exports keep a `.bak` and a `<root>.bombflower-original/` sidecar and never silently overwrite an original. Work on copies.
- A round-trip test is not game acceptance: one scalar edit has ever loaded in the game, and no created save has.
- Corrupt or unsupported input is rejected, never guessed; the messages are the contract — `the magic at 0x0 is 0xffffffff; expected 0x01020304`, `the data offset 95704 points past the end of the 100-byte buffer`, `SaveUnsupportedRevision(detected: 2982124, supported: 2982123)`.

## Longshot boundary — strictly read-only

- `/home/daze/GitHub/Longshot` is a static-recompilation game port: 28 GB, nearly all of it the gitignored `work/`. **Never grep or glob it unscoped** — scope to `docs/`, `host/`, `scripts/`.
- It has **no** `progress.sav` record parser: `host/oot_autoload.c` only stats the newest slot by mtime and `scripts/longshot_saves.py` copies and byte-patches. Field truth lives in this repo's schema and `docs/`.
- No writes, edits, formatting, builds, tests, or `git` mutation there; no PR may target it; no build or test here may depend on that path. Ignore the ~74 `~/GitHub/Longshot-*` sibling worktrees.
- Real saves: `~/.local/share/longshot/save/5a3c9e1f0b7d24680000000000000001/slot_NN/progress.sav` (`slot_00`–`05`) — copy before editing. An in-game save writes a *new* slot and Continue loads the newest by mtime, so editing an older slot can change nothing.

## Tooling

- Dart MCP is already configured in the user-level opencode config (`~/opencode.json`: server `dart-mcp-server` → `/home/daze/.local/opt/flutter/bin/dart mcp-server`, v1.2.2); there is no repo-local config and none is needed. Its tools appear as `dart.*` — prefer `analyze_files` over guessing, `lsp` for symbols, `get_runtime_errors` + `hot_reload` with `flutter run -d linux`.
- Skills in `/home/daze/.agents/skills`: use `bloc`, `testing`, `dart-add-unit-test`, `flutter-add-widget-test`, `git-commit`, `dart-write-documentation`, `differential-review`, and `flutter-clean-arch` — take the last one's dependency-direction checks only, since this repo has no usecase, entity, or model layers and bans `equatable` inside `domain`.
- `tool/perf_probe.dart` is the dev-only tab frame-time probe: it opens `--dart-define=PERF_SAVE_ROOT=<profile folder>` through the real `SaveSessionCubit`, visits every tab twice plus a 60-event wheel scroll over Inventory under `xvfb-run`, and prints `PERFVISIT` per tab visit, `PERFFRAME` once per frame, and `PERFSUMMARY` per phase (plus `PERFOPEN`, `PERFBENCH`, `PERFSCROLL`). Run it in profile mode (`flutter run --profile -d linux -t tool/perf_probe.dart …`); debug timings are meaningless, and Xvfb raster numbers are software raster — the build numbers are the meaningful figure.

## Conventions that differ from defaults

- Mandated packages: `flutter_bloc` ^9.1.1, `equatable` ^2.1.0, `material_ui` ^1.1.0, `shared_preferences` ^2.5.6 (the one persisted user-preferences store: the JSON-document store lives in `lib/presentation/settings/settings_store.dart`, the plugin sits behind the pure `PreferencesBackend` port in `lib/domain/preferences/preferences_backend.dart` and its implementation in `lib/data/system/shared_preferences_backend.dart` — do not let presentation import the plugin or data import presentation), `bitsdojo_window` ^0.1.6 (unmaintained, pinned: imported by `lib/main.dart`, `lib/app.dart`, the title bar (`lib/presentation/widgets/chrome/app_title_bar.dart`), and `lib/presentation/dialogs/open_save_browser.dart`, plus the `linux/runner/my_application.cc` include and its `bitsdojo_window_from` / `setCustomFrame(true)` calls — do not spread it further, and do not upgrade it casually).
- Human directive: prefer a maintained third-party package over hand-rolled infrastructure, but never for save bytes, which stay owned in-repo.
- Conventional Commits with a scope, one concern per commit — `feat(ui):`, `fix(app):`, `fix(adapter):`, `test(ui):`, `docs:`; scopes in use include `ui`, `app`, `adapter`, `codec`, `engine`, `newsave`, `tabs`, `theme`, `tool`.
- Stage only your own paths, never `git add -A`; branch `main`, remote `origin`; no force-push, no rebasing published history, no amending pushed commits.
- Never commit save files or ROMs (`.gitignore` blocks `*.sav`, `*.eep` and friends); fixtures must be synthetic or scrubbed, under `test/fixtures/`.
