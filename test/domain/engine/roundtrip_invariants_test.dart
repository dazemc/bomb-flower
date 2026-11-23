import 'package:flutter_test/flutter_test.dart';

/// Invariants (a) and (b) need the real codec/layout supplied by the
/// offset-research agent. They are intentionally skipped rather than faked
/// against synthetic offsets.
///
/// The other four invariants are covered now:
/// * (c) undo byte identity: `test/domain/engine/save_engine_test.dart`
///   "undo and redo (invariant c)".
/// * (d) no clamping / atomic failure: `test/domain/engine/save_engine_test.dart`
///   "rejects every invalid command atomically (invariant d)" and
///   `test/domain/core/edit_command_test.dart`.
/// * (e) open never writes: `test/data/io/file_save_repository_test.dart`
///   "opens read-only and creates no sidecar or pending manifest".
/// * (f) reject never partially writes: `test/data/io/atomic_file_writer_test.dart`
///   and `test/data/io/file_save_repository_test.dart`.
void main() {
  test(
    '(a) zero-edit round-trip is byte-identical',
    () {
      // TODO(codec): open a real fixture, export unchanged to a temp root, then
      // assert SHA-256 and length equality for every output file, plus that
      // snapshot.materialize() equals the ingested bytes.
    },
    skip: 'TODO(codec): requires the verified progress.sav layout and fixtures',
  );

  test(
    '(b) a field edit changes only its declared span plus integrity bytes',
    () {
      // TODO(codec): pick a verified field with real bounds, apply an in-range
      // scalar/bit/enum edit, and assert diffIndices(before, after) is a subset
      // of descriptor.span plus confirmed integrity regions. Repeat with an
      // unconfirmed spec and assert the edit exists while export is blocked.
    },
    skip: 'TODO(codec): requires a verified field span and integrity scheme',
  );
}
