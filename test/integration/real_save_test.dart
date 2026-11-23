/// Opt-in integration test over a real, played save (no scrubbing).
///
/// The save is read-only input: `progress.sav` is read into memory and every
/// assertion runs against those bytes. Nothing is copied into the repository
/// and nothing under the save root is written.
///
/// The group is skipped with an actionable reason when no save is present; the
/// root is `BOMB_FLOWER_REAL_SAVES` when set, else the default path.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/codec/progress_codec.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'support/real_save_loader.dart';

/// `PlayerStatus.Life` in the real save.
const int _lifeKey = 0x31AB5580;

/// `PlayerStatus.MaxLife` in the real save.
const int _maxLifeKey = 0xFBE01DA1;

/// `Sequence_CurrentRupee` / rupee counter in the real save.
const int _rupeeKey = 0xA77921D7;

/// Verified record count of a played `progress.sav`.
const int _expectedRecordCount = 11958;

/// Verified field count of a played `progress.sav`.
const int _expectedFieldCount = 11925;

/// Verified sentinel count of a played `progress.sav`.
const int _expectedSentinelCount = 32;

void main() {
  final slots = discoverRealSlots();
  final skipReason = slots.isEmpty ? realSaveSkipReason() : null;

  group('real played save', skip: skipReason, () {
    if (slots.isEmpty) {
      // A group-level skip only surfaces a reason when the group holds at
      // least one test, so the absent-save run reports why instead of
      // "No tests were found".
      test('no real save present', () {
        fail('unreachable: the group is skipped');
      });
      return;
    }

    for (final slot in slots) {
      test('${slot.path}: decodes and round-trips byte-identically', () {
        final bytes = Uint8List.fromList(
          File('${slot.path}/progress.sav').readAsBytesSync(),
        );

        final decoded = ProgressCodec.decode(bytes);
        expect(
          decoded,
          isA<ProgressDecodeOk>(),
          reason: 'slot ${slot.path} must decode: $decoded',
        );
        final save = (decoded as ProgressDecodeOk).save;

        expect(
          save.recordCount,
          _expectedRecordCount,
          reason: 'slot ${slot.path} record count',
        );
        expect(
          save.fieldCount,
          _expectedFieldCount,
          reason: 'slot ${slot.path} field count',
        );
        expect(
          save.sentinels.length,
          _expectedSentinelCount,
          reason: 'slot ${slot.path} sentinel count',
        );
        expect(
          <int>[for (final sentinel in save.sentinels) sentinel.rawValue],
          <int>[for (var i = 1; i <= _expectedSentinelCount; i++) i],
          reason: 'slot ${slot.path} sentinel values must be 1..32',
        );
        expect(
          save.footer.key,
          ProgressLayout.footerKey,
          reason: 'slot ${slot.path} footer key',
        );

        expect(
          save.encode(),
          bytes,
          reason:
              'slot ${slot.path} ProgressSave.encode must reproduce the file',
        );
        expect(
          ProgressCodec.encode(save),
          bytes,
          reason:
              'slot ${slot.path} ProgressCodec.encode must reproduce the file',
        );

        expect(
          save.recordByHash(_lifeKey)?.asInt(),
          16,
          reason: 'slot ${slot.path} PlayerStatus.Life is expected to be 16',
        );
        expect(
          save.recordByHash(_maxLifeKey)?.asInt(),
          16,
          reason: 'slot ${slot.path} PlayerStatus.MaxLife is expected to be 16',
        );
        expect(
          save.recordByHash(_rupeeKey)?.asInt(),
          27,
          reason: 'slot ${slot.path} current rupee count is expected to be 27',
        );

        // The footer names the end of the last verified tail span; the bytes
        // between it and EOF are an unverified opaque gap that the final span
        // absorbs. Measured real saves leave 280..608 bytes of it.
        final gap = bytes.length - save.footer.rawValue;
        expect(
          save.footer.rawValue,
          lessThan(bytes.length),
          reason: 'slot ${slot.path} footer must end before EOF',
        );
        expect(
          gap,
          inInclusiveRange(280, 608),
          reason: 'slot ${slot.path} trailing gap $gap',
        );
        expect(
          save.encode().sublist(save.footer.rawValue),
          bytes.sublist(save.footer.rawValue),
          reason: 'slot ${slot.path} post-footer bytes must be preserved',
        );

        debugPrint(
          '[real-save] slot ${slot.path} | '
          'fileLength ${bytes.length} | '
          'trailingGap $gap | '
          'decode ProgressDecodeOk | '
          'encode identical | '
          'Life ${save.recordByHash(_lifeKey)?.asInt()} '
          'MaxLife ${save.recordByHash(_maxLifeKey)?.asInt()} '
          'Rupee ${save.recordByHash(_rupeeKey)?.asInt()}',
        );
      });
    }
  });
}
