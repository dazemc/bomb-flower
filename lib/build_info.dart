/// Build identity injected by the release/build command.
///
/// Build with `--dart-define=BUILD_ID=<sha>-<timestamp>` so the running binary
/// can prove which build the human is looking at. Plain dev builds and tests
/// report `unknown`.
library;

/// Short build identifier shown in Settings → About.
const String kBuildId = String.fromEnvironment(
  'BUILD_ID',
  defaultValue: 'unknown',
);
