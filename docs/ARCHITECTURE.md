# Architecture

Bomb Flower is a Linux desktop Flutter app with a pure-Dart save engine. The
engine is the product; the UI is a client of it.

## Layers

```
lib/
  domain/         pure Dart: models, validation, save engine
  data/           byte codecs, file I/O adapters, repository implementations
  presentation/   pages, widgets, blocs/cubits
```

### domain

- No imports of `package:flutter/*`, `dart:ui`, or `bitsdojo_window`.
- Owns the save document model, slot/checksum rules, and edit operations.
- Must be testable with `dart test`-style pure unit tests (via `flutter test`).
- All byte offsets and invariants live here, documented next to the code.

### data

- Converts between bytes and domain models.
- Owns file access and fixture loading; never contains UI state.
- Repositories expose narrow interfaces consumed by presentation.

### presentation

- Flutter widgets, pages, and `flutter_bloc` blocs/cubits.
- May import domain types; domain never imports presentation.
- Window chrome lives in `presentation/widgets/app_title_bar.dart`. The only
  other place that touches `bitsdojo_window` is `main.dart`.

## State management

`flutter_bloc` (bloc/cubit) is the chosen state layer. Cubits are preferred for
simple editor state; blocs where events need explicit ordering. UI widgets stay
dumb and receive state plus callbacks.

## Save engine rules

- Pure Dart; deterministic; no global mutable state.
- Round-trip safe: decode -> encode with no edits must be byte-identical
  (barring documented normalisation such as checksum recomputation).
- Invalid input returns typed failures, never throws for user data.
- Checksums and version differences are explicit, tested behaviours.

## Current shell

- `lib/main.dart` — bitsdojo window setup (size, min size, title, show).
- `lib/app.dart` — `MaterialApp`, theme, `BombFlowerShell`.
- `lib/presentation/widgets/app_title_bar.dart` — draggable custom chrome.

`BombFlowerApp(enableWindowChrome: false)` renders the shell in tests without
native window calls.

## Near-term seams

1. `domain` save model and parser for Ocarina of Time save files.
2. `data` byte codec with fixture-backed round-trip tests.
3. `presentation` slot overview page and edit cubit.
