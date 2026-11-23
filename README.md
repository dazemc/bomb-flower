# Bomb Flower

An original-flavoured **Ocarina of Time save editor and save creator**, built
as a Flutter desktop app for Linux. Bomb Flower is the companion editor for
Longshot (`../Longshot`); the save engine is pure Dart and the UI is a young
shell while that engine is being written.

> **Not affiliated with Nintendo.** Bomb Flower contains no game assets, no
> ROMs, and no ripped artwork or audio. It reads and writes save data that you
> supply; you are responsible for owning and dumping your own game.

## Longshot boundary

Longshot (`/home/daze/GitHub/Longshot`) is a **read-only input** to this
project. Bomb Flower may read its documentation and, later, its save-format
notes, but it never writes to, builds in, or mutates that repository. See
[`docs/LONGSHOT-BOUNDARY.md`](docs/LONGSHOT-BOUNDARY.md).

## Status

Early bootstrap: frameless Linux window, custom 44 px title bar, dark
forest-green Material 3 theme, and a placeholder body. No save parsing yet.

## Requirements

- Flutter 3.50.1 / Dart 3.14.0 (stable)
- Linux desktop toolchain (`clang`, CMake, Ninja, GTK 3 dev headers)
- `xvfb-run` for headless GUI smoke tests

## Build and run

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter build linux --debug
```

Run the built bundle headlessly:

```sh
xvfb-run -a ./build/linux/x64/debug/bundle/bomb_flower
```

Or with a display:

```sh
flutter run -d linux
```

## Architecture

The intended layering is domain / data / presentation:

- `lib/domain/` — pure-Dart save model and engine, no Flutter imports
- `lib/data/` — byte-level codecs, file adapters, fixtures
- `lib/presentation/` — widgets, pages, blocs/cubits

The current shell lives in `lib/app.dart`, `lib/main.dart`, and
`lib/presentation/widgets/app_title_bar.dart`. Details and rules are in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Licence

TBD before first release. No third-party game assets are distributed.
