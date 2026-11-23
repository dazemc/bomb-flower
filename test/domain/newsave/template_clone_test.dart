import 'dart:typed_data';

import 'package:bomb_flower/data/codec/caption_codec.dart';
import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/newsave/template_clone.dart';
import 'package:bomb_flower/domain/save/caption_layout.dart';
import 'package:bomb_flower/domain/save/models/progress_save.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/synthetic_caption.dart';
import '../../support/synthetic_progress.dart';

/// Builds the synthetic 16/16 save the brief asks for.
///
/// `buildSyntheticProgress` stores Life = 20 and MaxLife = 30 inline, so both
/// value words are patched in place. Length and record layout are unchanged.
({Uint8List bytes, int lifeOffset, int maxLifeOffset}) _sixteenSixteen() {
  final bytes = buildSyntheticProgress();
  final decoded = ProgressCodec.decode(bytes);
  if (decoded is! ProgressDecodeOk) {
    fail('synthetic progress did not decode: $decoded');
  }
  final save = decoded.save;
  final life = save.recordByHash(lifeFieldHash)!;
  final maxLife = save.recordByHash(maxLifeFieldHash)!;
  _writeU32Le(bytes, life.valueOffset, 16);
  _writeU32Le(bytes, maxLife.valueOffset, 16);
  return (
    bytes: bytes,
    lifeOffset: life.valueOffset,
    maxLifeOffset: maxLife.valueOffset,
  );
}

ProgressSave _decodeProgress(Uint8List bytes) {
  final decoded = ProgressCodec.decode(bytes);
  if (decoded is! ProgressDecodeOk) {
    fail('progress did not decode: $decoded');
  }
  return decoded.save;
}

int _fieldValue(Uint8List bytes, ProgressSave save, int hash) {
  final record = save.recordByHash(hash)!;
  return bytes[record.valueOffset] |
      (bytes[record.valueOffset + 1] << 8) |
      (bytes[record.valueOffset + 2] << 16) |
      (bytes[record.valueOffset + 3] << 24);
}

void _writeU32Le(Uint8List bytes, int offset, int value) {
  for (var i = 0; i < 4; i++) {
    bytes[offset + i] = (value >> (8 * i)) & 0xff;
  }
}

/// Asserts every byte outside [start, end) is unchanged.
void _expectUnchangedOutside(
  Uint8List before,
  Uint8List after,
  int start,
  int end,
) {
  expect(after.length, before.length, reason: 'length must not change');
  for (var i = 0; i < before.length; i++) {
    if (i >= start && i < end) {
      continue;
    }
    if (before[i] != after[i]) {
      fail('byte $i changed from ${before[i]} to ${after[i]}');
    }
  }
}

void main() {
  group('cloneSaveTemplate', () {
    test('no overrides returns both inputs byte for byte', () {
      final progress = buildSyntheticProgress();
      final caption = buildSyntheticCaption(sceneTrailer: <int>[0x41, 0x42]);
      final progressBefore = Uint8List.fromList(progress);
      final captionBefore = Uint8List.fromList(caption);

      final result = cloneSaveTemplate(progress: progress, caption: caption);

      expect(result.progressBytes, equals(progress));
      expect(result.captionBytes, equals(caption));
      expect(result.changedSpans, isEmpty);
      // The caller's buffers are untouched and the outputs are copies.
      expect(progress, equals(progressBefore));
      expect(caption, equals(captionBefore));
      expect(identical(result.progressBytes, progress), isFalse);
      expect(identical(result.captionBytes, caption), isFalse);
    });

    test('life writes only the four Life bytes', () {
      final fixture = _sixteenSixteen();
      final caption = buildSyntheticCaption();

      final result = cloneSaveTemplate(
        progress: fixture.bytes,
        caption: caption,
        life: 12,
      );

      _expectUnchangedOutside(
        fixture.bytes,
        result.progressBytes,
        fixture.lifeOffset,
        fixture.lifeOffset + 4,
      );
      expect(
        result.progressBytes.sublist(
          fixture.lifeOffset,
          fixture.lifeOffset + 4,
        ),
        equals(<int>[0x0c, 0x00, 0x00, 0x00]),
      );
      final decoded = _decodeProgress(result.progressBytes);
      expect(_fieldValue(result.progressBytes, decoded, lifeFieldHash), 12);
      expect(
        _fieldValue(result.progressBytes, decoded, maxLifeFieldHash),
        16,
      );
      expect(
        result.changedSpans,
        equals(<(int, int)>[(fixture.lifeOffset, fixture.lifeOffset + 4)]),
      );
      expect(result.captionBytes, equals(caption));
    });

    test('life must satisfy 0 < life <= MaxLife', () {
      expect(
        () => cloneSaveTemplate(
          progress: buildSyntheticProgress(),
          caption: buildSyntheticCaption(),
          life: 31,
        ),
        throwsArgumentError,
        reason: 'MaxLife is 30 in the default synthetic save',
      );
      final fixture = _sixteenSixteen();
      expect(
        () => cloneSaveTemplate(
          progress: fixture.bytes,
          caption: buildSyntheticCaption(),
          life: 17,
        ),
        throwsArgumentError,
        reason: 'MaxLife is 16',
      );
      expect(
        () => cloneSaveTemplate(
          progress: buildSyntheticProgress(),
          caption: buildSyntheticCaption(),
          life: 0,
        ),
        throwsArgumentError,
      );
    });

    test('sceneName writes only its slot and NUL-terminates it', () {
      final progress = buildSyntheticProgress();
      final caption = buildSyntheticCaption(
        sceneTrailer: <int>[0x41, 0x42, 0x43],
      );

      final result = cloneSaveTemplate(
        progress: progress,
        caption: caption,
        sceneName: 'NewScene',
      );

      const start = CaptionLayout.sceneNameOffset;
      const end = start + CaptionLayout.nameLength;
      _expectUnchangedOutside(caption, result.captionBytes, start, end);
      expect(result.captionBytes[start + 8], 0);
      for (var i = start + 9; i < end; i++) {
        expect(result.captionBytes[i], 0, reason: 'slot byte $i is not zero');
      }
      // The map slot is untouched.
      expect(
        result.captionBytes.sublist(
          CaptionLayout.mapPathOffset,
          CaptionLayout.mapPathOffset + CaptionLayout.nameLength,
        ),
        equals(
          caption.sublist(
            CaptionLayout.mapPathOffset,
            CaptionLayout.mapPathOffset + CaptionLayout.nameLength,
          ),
        ),
      );
      expect(
        result.changedSpans,
        equals(<(int, int)>[(start, end)]),
      );
      expect(result.progressBytes, equals(progress));

      final decoded = CaptionCodec.decode(result.captionBytes);
      if (decoded is! CaptionDecodeOk) {
        fail('caption did not decode: $decoded');
      }
      expect(decoded.save.sceneName, 'NewScene');
      expect(decoded.save.mapPath, 'TestScene/Room_1');
    });

    test('rejects a 64-character scene', () {
      final scene = 'A' * CaptionLayout.nameLength;
      expect(scene.length, 64);
      expect(
        () => cloneSaveTemplate(
          progress: buildSyntheticProgress(),
          caption: buildSyntheticCaption(),
          sceneName: scene,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-ASCII scene', () {
      for (final scene in <String>['KokiriFôrest', 'Bad\nName']) {
        expect(
          () => cloneSaveTemplate(
            progress: buildSyntheticProgress(),
            caption: buildSyntheticCaption(),
            sceneName: scene,
          ),
          throwsArgumentError,
          reason: 'scene "$scene" is not printable ASCII',
        );
      }
    });

    test('sceneName and mapPath coalesce into one span', () {
      final caption = buildSyntheticCaption();

      final result = cloneSaveTemplate(
        progress: buildSyntheticProgress(),
        caption: caption,
        sceneName: 'NewScene',
        mapPath: 'NewScene/Room_2',
      );

      const start = CaptionLayout.sceneNameOffset;
      const end = CaptionLayout.mapPathOffset + CaptionLayout.nameLength;
      expect(result.changedSpans, equals(<(int, int)>[(start, end)]));
      _expectUnchangedOutside(caption, result.captionBytes, start, end);

      final decoded = CaptionCodec.decode(result.captionBytes);
      if (decoded is! CaptionDecodeOk) {
        fail('caption did not decode: $decoded');
      }
      expect(decoded.save.sceneName, 'NewScene');
      expect(decoded.save.mapPath, 'NewScene/Room_2');
    });

    test('mapPath alone reports only its own slot', () {
      final result = cloneSaveTemplate(
        progress: buildSyntheticProgress(),
        caption: buildSyntheticCaption(),
        mapPath: 'NewScene/Room_2',
      );

      const start = CaptionLayout.mapPathOffset;
      const end = start + CaptionLayout.nameLength;
      expect(result.changedSpans, equals(<(int, int)>[(start, end)]));
    });

    test('rejects a caption without the magic', () {
      final caption = buildSyntheticCaption();
      caption[0] = 0;
      expect(
        () => cloneSaveTemplate(
          progress: buildSyntheticProgress(),
          caption: caption,
        ),
        throwsArgumentError,
      );
    });

    test('rejects progress bytes that do not decode', () {
      expect(
        () => cloneSaveTemplate(
          progress: Uint8List(64),
          caption: buildSyntheticCaption(),
        ),
        throwsArgumentError,
      );
    });
  });
}
