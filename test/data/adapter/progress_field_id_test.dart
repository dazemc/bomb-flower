import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_field_id.dart';
import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/save/progress_layout.dart';
import 'package:bomb_flower/domain/save/progress_record.dart';
import 'package:flutter_test/flutter_test.dart';

const int _lifeKey = 0x31AB5580;

ProgressRecord _record(int key) => ProgressRecord(
  bytes: Uint8List(4),
  key: key,
  rawValue: 0,
  index: 0,
  type: SaveType.intValue,
  valueOffset: 0,
  dataOffset: null,
  dataLength: 4,
);

void main() {
  test('progressFieldId renders eight lower-case hex digits', () {
    expect(
      progressFieldId(_record(_lifeKey)),
      const FieldId('progress.31ab5580'),
    );
  });

  test('progressHashFromFieldId round-trips the hash', () {
    expect(
      progressHashFromFieldId(const FieldId('progress.31ab5580')),
      _lifeKey,
    );
  });

  test('progressHashFromFieldId rejects malformed ids', () {
    expect(progressHashFromFieldId(const FieldId('progress.zzzzzzzz')), isNull);
    expect(progressHashFromFieldId(const FieldId('life')), isNull);
  });

  test('isProgressFieldId accepts only the canonical form', () {
    expect(isProgressFieldId(const FieldId('progress.31ab5580')), isTrue);
    expect(isProgressFieldId(const FieldId('progress.31AB5580')), isFalse);
    expect(isProgressFieldId(const FieldId('progress.31ab558')), isFalse);
    expect(isProgressFieldId(const FieldId('progress.31ab55800')), isFalse);
    expect(isProgressFieldId(const FieldId('slot_00:0x31ab5580')), isFalse);
  });

  test('ids are stable per hash and distinct across hashes', () {
    expect(
      progressFieldId(_record(_lifeKey)),
      progressFieldId(_record(_lifeKey)),
    );
    expect(
      progressFieldId(_record(_lifeKey)),
      isNot(progressFieldId(_record(0xDEADBEEF))),
    );
  });
}
