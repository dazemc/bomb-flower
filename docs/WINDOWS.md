# Windows

## Status

The Windows runner is generated and committed (`windows/`). The
Windows-specific Dart — the per-platform save-location rules, the folder-picker
choice, and the recent-folders directory — is analysed by `flutter analyze` and
exercised by unit tests that run on Linux through injected seams
(`lib/data/system/host_platform.dart`, `test/data/system/`). The settings-store
location is not unit-tested; it is derived from the plugin and the runner's
VERSIONINFO, as set out below. **No Windows build has been produced or run,
because the project has only ever been built on Linux.** Treat Windows as
scaffolded and unverified, not supported. Everything below the Dart layer is a
recipe, not a record of something that happened.

## Prerequisites

- Windows 10 or 11, x64.
- Flutter 3.50.1 stable, which bundles Dart 3.14.0 and matches the
  `sdk: ^3.14.0` constraint in `pubspec.yaml`.
- Visual Studio 2022 with the **Desktop development with C++** workload
  installed (MSVC v143, a Windows 10 or 11 SDK, and CMake). The Flutter Windows
  build drives MSVC and CMake; a plain Visual Studio Code install is not enough.
  These and the OS/Flutter versions are the Flutter toolchain's documented
  Windows requirements, not facts this repository has verified.
- Enable the desktop target once, then confirm the toolchain:

  ```bat
  flutter config --enable-windows-desktop
  flutter doctor
  ```

  `flutter doctor` must report `[✓] Visual Studio - develop Windows apps` and
  `[✓] Windows Version`. On this host it instead reports the Linux toolchain and
  `[✗] Android toolchain` / `[✗] Chrome`; those lines are irrelevant on Windows,
  just as the Visual Studio lines are irrelevant on Linux.

## Build

From the repository root:

```bat
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

`flutter analyze` must print `No issues found!`. The unit suite is headless and
runs on any host; on Windows it does not exercise a Windows window, only the
same Dart the Linux suite exercises.

Release output lands in:

```text
build\windows\x64\runner\Release\
```

That folder is the runnable bundle: `bomb_flower.exe` (the name is
`BINARY_NAME` in `windows/CMakeLists.txt`), `flutter_windows.dll`, the DLLs that
`windows/flutter/generated_plugins.cmake` bundles (`bitsdojo_window_windows`,
`file_selector_windows`, and the `jni` FFI plugin's library), and `data\`
(Flutter assets, `icudtl.dat`, and the AOT `app.so`). Copy or mirror the whole
folder; `bomb_flower.exe` alone will not start. The file list follows the
install rules in `windows/CMakeLists.txt` and the plugin registrations; it is
not an observed directory listing, because no build has run.

Debug builds are `flutter build windows --debug`, written to
`build\windows\x64\runner\Debug\`, and produce a JIT bundle instead of an AOT
`data\app.so`.

## Window chrome

The app is frameless on Windows exactly as it is on Linux. The native runner
opts in before the Flutter engine starts, in `windows/runner/main.cpp`:

```cpp
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
```

`main.cpp` creates the window at 1280×720 with the working title `bomb_flower`
and leaves it hidden. `lib/main.dart` then configures and shows it from
`doWhenWindowReady`: title `Bomb Flower`, minimum size 800×600, alignment
centred, `appWindow.show()`.

The custom title bar
(`lib/presentation/widgets/chrome/app_title_bar.dart`) drives dragging,
minimising, maximising/restoring and closing through `appWindow` only. It
contains no GTK call and no `dart:io` platform check, and presentation cannot
import `dart:io` at all. The same bar is therefore the Windows bar by
construction — but it has never been rendered on Windows.

## Where saves live

Longshot's own documentation (`docs/user/saves.md`, "Where Longshot keeps them";
`docs/user/updates-and-saves.md`; `docs/user/advanced.md`, `--user`) gives three
layouts:

| How the game was started | Save folder |
|---|---|
| Installed nightly launcher (the launcher passes `--user`) | `%APPDATA%\Longshot\save` — normally `%USERPROFILE%\AppData\Roaming\Longshot\save` |
| Game started directly without `--user` | `<game folder>\user\save`; the game folder is `%USERPROFILE%\Games\Longshot` unless another was chosen |
| `--user <folder>`, or a portable launcher | that folder (a portable launcher keeps `LongshotLauncher-data\user\save` beside itself) |

The launcher's backups are `%LOCALAPPDATA%\Longshot\oot-save-backups`.

Bomb Flower's resolver
(`resolveLongshotSaveLocations` in `lib/data/system/profile_path.dart`) mirrors
the first two rows with environment variables, not filesystem probing:

- `%APPDATA%\Longshot\save` when `%APPDATA%` is set;
- `%USERPROFILE%\Games\Longshot\user\save` only when `%APPDATA%` is not set;
- `%LOCALAPPDATA%\Longshot\oot-save-backups` as `backupBase`.

Two consequences worth stating plainly. Because `%APPDATA%` is normally always
set, a player who starts the game directly still gets the launcher path
proposed; Bomb Flower does not detect the direct-start layout, so that save
folder has to be opened by hand. And the backup folder is never offered as an
openable root — it is a `backupBase` value that no current UI reads. When
nothing is discovered under the proposed base, the open dialog falls back to the
last used folder, then the home folder (`%USERPROFILE%` or `HOME`), and only
then starts empty for the user to type a path. No location is invented.

For comparison, the Linux rules are `$XDG_DATA_HOME/longshot/save` (then
`$HOME/.local/share/longshot/save`) with backups at `longshot/save-backup`;
macOS and unknown hosts resolve to `null` rather than a guess.

## Where editor settings live

The editor's preferences (`lib/presentation/settings/settings_store.dart`) are
persisted through `shared_preferences` and
`SharedPreferencesBackend` (`lib/data/system/shared_preferences_backend.dart`).
On Windows the resolved implementation is the Dart-only
`shared_preferences_windows 2.4.1`, which writes
`<path_provider_windows getApplicationSupportPath()>/shared_preferences.json`.
`path_provider_windows 2.3.0` builds that support path as
`%APPDATA%\<CompanyName>\<ProductName>` read from the executable's VERSIONINFO,
and `windows/runner/Runner.rc` sets `CompanyName` to `bomb-flower` and
`ProductName` to `Bomb Flower`. The file is therefore:

```text
%APPDATA%\bomb-flower\Bomb Flower\shared_preferences.json
```

Renaming either string in `Runner.rc` moves the settings file with it. Recent
save folders are a separate convenience file,
`RecentPathsFileStore.defaultDirectory` (`lib/data/system/directory_picker.dart`)
puts it at `%APPDATA%\bomb-flower\recent.json`.

On Linux the same `shared_preferences` store uses
`shared_preferences_linux 2.4.1`, whose support path is
`$XDG_DATA_HOME/<APPLICATION_ID>`; `linux/CMakeLists.txt` sets
`APPLICATION_ID "dev.dazemc.bomb_flower"`, so the file is
`~/.local/share/dev.dazemc.bomb_flower/shared_preferences.json`, and recent
folders are at `$XDG_CONFIG_HOME/bomb-flower/recent.json`
(`~/.config/bomb-flower/recent.json`).

## Native folder picker

`PlatformDirectoryPicker` (`lib/data/system/directory_picker.dart`) chooses at
call time: Windows, macOS and unknown hosts get
`FileSelectorDirectoryPicker`, i.e. `package:file_selector`
(`file_selector_windows 0.9.3+6` here); Linux and Fuchsia keep the
zenity → kdialog → qarma chain, because those programs are Linux-only. The
choice of `file_selector` over `file_picker` is the recorded human ruling in
[`LIMITATIONS.md`](LIMITATIONS.md) ("Dependency rulings that are settled"):
`file_picker` cannot resolve alongside the pinned `bitsdojo_window`/`win32`
versions. The Windows COM `IFileDialog` itself has never been opened on this
host.

## Verification checklist a Windows user must run

None of these steps has been performed by this repository's maintainers, and
none can be performed on the Linux development host.

1. `flutter doctor -v` — the Visual Studio section must show the C++ workload,
   MSVC v143, a Windows SDK, and CMake, with no `[✗]` for Windows.
2. `flutter pub get` — must resolve `file_selector_windows`,
   `bitsdojo_window_windows`, `shared_preferences_windows` and `jni`.
3. `flutter build windows --release` — must finish without an MSVC or CMake
   error. This is the first compile the runner and those plugins will ever get.
4. Confirm `build\windows\x64\runner\Release\bomb_flower.exe`,
   `flutter_windows.dll`, the plugin DLLs and `data\` all exist.
5. Launch `bomb_flower.exe` and confirm: no native title bar or frame; drag by
   the custom title bar; minimise, maximise/restore and close all work; the
   window refuses to shrink below 800×600; the title reads `Bomb Flower`.
6. Create a new save into a scratch folder, then open a copy of an existing
   save (never the original) and confirm the slot list appears.
7. Change one verified scalar field, save, and reopen the result — byte-level
   round-trip in the app, not in-game acceptance.
8. Confirm `%APPDATA%\bomb-flower\Bomb Flower\shared_preferences.json` was
   created, and that changing a setting survives a restart.
9. If a save folder is proposed that does not match the game's real one, open
   the correct folder by hand and note it: that is the direct-start case
   described above.

Positive results from this list would justify changing the status at the top of
this file. Nothing less would.

## What remains unverified on Linux

- No MSVC compile of `windows/runner/` and no native compile of
  `bitsdojo_window_windows`, `file_selector_windows`, or `jni` for Windows. The
  Dart is analysed; the C++ and the plugin binaries are not compiled anywhere.
- No COM folder dialog: the Windows picker path is unit-tested through the
  injected chooser seam, so no `IFileDialog` has been shown.
- No live `%APPDATA%`, `%USERPROFILE%` or `%LOCALAPPDATA%` lookup. The rules are
  tested with injected environment maps and `package:path`'s Windows context,
  not by reading a real Windows environment.
- No NTFS behaviour: separator handling, case-insensitive names, junction and
  symlink traversal, and long paths are untested on the real filesystem.
- No window-manager behaviour: custom frame, drag, minimise/maximise, DPI
  scaling, multi-monitor placement, and the 800×600 minimum.
- No in-game save acceptance on Windows. The only in-game load ever recorded is
  one Linux scalar edit, and no created save has been loaded by the game on any
  platform.
