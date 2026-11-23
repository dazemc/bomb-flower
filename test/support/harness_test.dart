import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'byte_assert.dart';
import 'fixture_loader.dart';
import 'save_fixture_builder.dart';

void main() {
  group('expectByteIdentical', () {
    test('accepts byte-identical buffers', () {
      final a = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final b = Uint8List.fromList(<int>[1, 2, 3, 4]);

      expectByteIdentical(a, b);
    });

    test('reports the first differing offset with a hex window', () {
      final before = Uint8List(64)..fillRange(0, 64, 0xaa);
      final after = Uint8List.fromList(before)..[37] = 0xbb;

      expect(
        () => expectByteIdentical(after, before, reason: 'single byte flip'),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(
              contains('single byte flip'),
              contains('offset 0x00000025 (37)'),
              contains('first has 0xbb'),
              contains('second has 0xaa'),
              contains('00000025'),
              contains('|................|'),
            ),
          ),
        ),
      );
    });

    test('reports a length-only difference', () {
      final shorter = Uint8List.fromList(<int>[1, 2]);
      final longer = Uint8List.fromList(<int>[1, 2, 3]);

      expect(
        () => expectByteIdentical(shorter, longer),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('first length difference at offset 0x00000002 (2)'),
          ),
        ),
      );
    });
  });

  group('expectOnlyRegionsChanged', () {
    test('passes when only allowed regions changed', () {
      final before = Uint8List(128);
      final after = Uint8List.fromList(before)
        ..[8] = 1
        ..[9] = 2
        ..[20] = 3;

      expectOnlyRegionsChanged(before, after, const <ByteRegion>[
        ByteRegion(8, 12, 'header'),
        ByteRegion(20, 21, 'flag'),
      ]);
    });

    test('fails with every unexpected offset range', () {
      final before = Uint8List(128);
      final after = Uint8List.fromList(before)
        ..[8] = 1
        ..[40] = 2
        ..[41] = 3
        ..[42] = 4
        ..[50] = 5;

      expect(
        () => expectOnlyRegionsChanged(before, after, const <ByteRegion>[
          ByteRegion(8, 12, 'header'),
        ]),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(
              contains(
                'unexpected changed regions outside allowed regions '
                '[header]',
              ),
              contains('0x00000028..0x0000002b (3 bytes, end exclusive)'),
              contains('0x00000032..0x00000033 (1 byte, end exclusive)'),
              contains('First unexpected offset: 0x00000028 (40)'),
            ),
          ),
        ),
      );
    });

    test('rejects buffers with different lengths', () {
      expect(
        () => expectOnlyRegionsChanged(
          Uint8List(4),
          Uint8List(5),
          const <ByteRegion>[],
        ),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('region checks require equal-length buffers'),
          ),
        ),
      );
    });
  });

  group('ByteRegionDiff', () {
    test('coalesces adjacent changes into runs', () {
      final before = Uint8List(32);
      final after = Uint8List.fromList(before)
        ..[2] = 1
        ..[3] = 1
        ..[4] = 1
        ..[10] = 1
        ..[11] = 1
        ..[31] = 1;

      final diff = ByteRegionDiff.diff(before, after);

      expect(
        diff.runs.map((run) => (run.start, run.length)).toList(),
        <(int, int)>[(2, 3), (10, 2), (31, 1)],
      );
    });

    test('merges a changed last byte with an appended tail', () {
      final before = Uint8List.fromList(<int>[0, 0, 0, 0]);
      final after = Uint8List.fromList(<int>[0, 0, 0, 1, 1]);

      final diff = ByteRegionDiff.diff(before, after);

      expect(
        diff.runs.map((run) => (run.start, run.length)).toList(),
        <(int, int)>[(3, 2)],
      );
    });

    test('reports an unchanged pair as no runs', () {
      final bytes = Uint8List.fromList(<int>[7, 8, 9]);

      expect(
        ByteRegionDiff.diff(bytes, Uint8List.fromList(bytes)).hasChanges,
        isFalse,
      );
    });

    test('reports a truncation as a tail run', () {
      final before = Uint8List.fromList(<int>[1, 2, 3]);
      final after = Uint8List.fromList(<int>[1, 2]);

      final diff = ByteRegionDiff.diff(before, after);

      expect(
        diff.runs.map((run) => (run.start, run.length)).toList(),
        <(int, int)>[(2, 1)],
      );
    });
  });

  group('hexWindow', () {
    test('formats full rows with grouped hex and ASCII', () {
      final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i));

      final window = hexWindow(bytes, 15);

      expect(
        window,
        '00000000  00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f  '
        '|................|\n'
        '00000010  10 11 12 13 14 15 16 17  18 19 1a 1b 1c 1d 1e 1f  '
        '|................|',
      );
    });

    test('honours the radius and prints absolute addresses', () {
      final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i));

      expect(
        hexWindow(bytes, 8, radius: 2),
        '00000006  06 07 08 09 0a  |.....|',
      );
    });

    test('handles an empty buffer', () {
      expect(hexWindow(Uint8List(0), 0), '(empty buffer)');
    });
  });

  group('SaveFixtureBuilder progress', () {
    test('builds a zeroed 120,572-byte skeleton', () {
      final builder = SaveFixtureBuilder.progress();
      final bytes = builder.build();

      expect(builder.length, SaveFixtureBuilder.progressSaveSize);
      expect(bytes.length, 120572);
      expect(bytes.every((byte) => byte == 0), isTrue);
    });

    test('writes big-endian u8, u16, and u32 values', () {
      final bytes = SaveFixtureBuilder.progress()
          .withU8(0, 0x12)
          .withU16(1, 0x3456)
          .withU32(3, 0x789abcde)
          .build();

      expect(bytes.sublist(0, 7), <int>[
        0x12,
        0x34,
        0x56,
        0x78,
        0x9a,
        0xbc,
        0xde,
      ]);
    });

    test('build returns an independent copy', () {
      final builder = SaveFixtureBuilder.progress().withU8(0, 0x12);
      final first = builder.build()..[0] = 0xff;

      expect(builder.build()[0], 0x12);
      expect(first[0], 0xff);
    });

    test('withBytesAt writes a run and rejects out-of-bounds writes', () {
      final builder = SaveFixtureBuilder.progress().withBytesAt(120570, <int>[
        0xaa,
        0xbb,
      ]);

      expect(builder.build().sublist(120570), <int>[0xaa, 0xbb]);
      expect(() => builder.withBytesAt(120571, <int>[1, 2]), throwsRangeError);
      expect(() => builder.withBytesAt(120572, <int>[1]), throwsRangeError);
      expect(() => builder.withBytesAt(-1, <int>[1]), throwsRangeError);
      expect(() => builder.withU32(120570, 1), throwsRangeError);
    });

    test('rejects byte values outside 0..255', () {
      expect(
        () => SaveFixtureBuilder.progress().withBytesAt(0, <int>[256]),
        throwsRangeError,
      );
    });
  });

  group('SaveFixtureBuilder caption', () {
    test('builds the verified magic in a 4,741-byte skeleton', () {
      final bytes = SaveFixtureBuilder.caption().build();

      expect(bytes.length, 4741);
      expect(bytes.sublist(0, 4), SaveFixtureBuilder.captionMagic);
      expect(bytes.sublist(4).every((byte) => byte == 0), isTrue);
    });

    test('sets a little-endian JPEG length and payload', () {
      final payload = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
      final bytes = SaveFixtureBuilder.caption()
          .withJpegPayload(payload)
          .build();

      expect(
        bytes.sublist(
          SaveFixtureBuilder.captionJpegLengthOffset,
          SaveFixtureBuilder.captionJpegOffset,
        ),
        <int>[payload.length, 0, 0, 0],
      );
      expect(
        bytes.sublist(
          SaveFixtureBuilder.captionJpegOffset,
          SaveFixtureBuilder.captionJpegOffset + payload.length,
        ),
        payload,
      );
      expect(
        bytes
            .sublist(SaveFixtureBuilder.captionJpegOffset + payload.length)
            .every((byte) => byte == 0),
        isTrue,
      );
    });

    test('sets the JPEG length without writing a payload', () {
      final bytes = SaveFixtureBuilder.caption().withJpegLength(1234).build();

      expect(
        bytes.sublist(
          SaveFixtureBuilder.captionJpegLengthOffset,
          SaveFixtureBuilder.captionJpegOffset,
        ),
        <int>[0xd2, 0x04, 0x00, 0x00],
      );
    });

    test('rejects an oversized JPEG payload or length', () {
      final builder = SaveFixtureBuilder.caption();

      expect(
        () => builder.withJpegPayload(
          List<int>.filled(SaveFixtureBuilder.maxJpegLength + 1, 0),
        ),
        throwsRangeError,
      );
      expect(
        () => builder.withJpegLength(SaveFixtureBuilder.maxJpegLength + 1),
        throwsRangeError,
      );
      expect(
        () => SaveFixtureBuilder.progress().withJpegLength(1),
        throwsStateError,
      );
    });
  });

  group('fixture loader', () {
    final skip = samplesAvailable ? null : samplesUnavailableMessage;

    test('copies samples into .local-fixtures and caches reads', () async {
      final progress = await loadSample('kokiri-start', 'progress.sav');
      final caption = await loadSample('kokiri-start', 'caption.sav');

      expect(progress, isNotNull);
      expect(caption, isNotNull);
      expect(progress!.length, SaveFixtureBuilder.progressSaveSize);
      expect(caption!.length, SaveFixtureBuilder.captionSaveSize);
      expect(caption.sublist(0, 4), SaveFixtureBuilder.captionMagic);

      final localProgress = File(
        '${fixturesDirectory.path}/kokiri-start/slot_00/progress.sav',
      );
      expect(localProgress.existsSync(), isTrue);

      final again = await loadSample('kokiri-start', 'progress.sav');
      expect(identical(progress, again), isTrue);
    }, skip: skip);

    test('returns null for an absent sample', () async {
      expect(await loadSample('does-not-exist', 'progress.sav'), isNull);
    });
  });
}
