/// Repository factory for the Switch 2 remake's progress saves.
library;

import '../../domain/core/layout.dart';
import '../../domain/engine/ports.dart';
import '../../domain/engine/save_engine.dart';
import '../../domain/schema/gamedata_schema.dart';
import '../io/file_save_repository.dart';
import 'progress_field_value_codec.dart';
import 'progress_layout_builder.dart';
import 'progress_layout_resolver.dart';

/// Creates [SaveRepository] instances for the Switch 2 remake.
final class ProgressSaveRepositoryFactory {
  /// Creates a factory from the verified GameData [schema].
  ProgressSaveRepositoryFactory({
    required this.schema,
    this.codec = const ProgressFieldValueCodec(),
  });

  /// GameData schema used to build per-file field layouts.
  final GameDataSchema schema;

  /// Decoder for field display values.
  final ProgressFieldValueCodec codec;

  /// Creates a repository that detects and opens a save at [rootPath].
  SaveRepository create(String rootPath) {
    final engine = SaveEngine(
      // The layouts are deliberately empty. A progress.sav's spans are derived
      // per file from its decoded records, so no static LayoutDescriptor can be
      // registered here; FileSaveRepository resolves the layout by detection
      // and hands that exact descriptor to SaveEngine.open.
      const SaveFormat(
        'oot-remake',
        'Ocarina of Time (Switch 2 remake)',
        <LayoutDescriptor>[],
      ),
      valueCodec: codec,
    );
    return FileSaveRepository(
      engine: engine,
      resolveLayout: ProgressLayoutResolver(ProgressLayoutBuilder(schema)).call,
    );
  }
}
