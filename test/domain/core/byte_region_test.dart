import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteRegion construction', () {
    test('copies source bytes defensively', () {
      final source = Uint8List.fromList(<int>[1, 2, 3]);
      final region = ByteRegion.fromBytes(source);

      source[0] = 99;

      expect(region.readByte(0), 1);
      expect(region.length, 3);
      expect(region.isPristine, isTrue);
      expect(region.patchCount, 0);
    });

    test('materialize returns a fresh buffer each time', () {
      final region = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final first = region.materialize();
      final second = region.materialize();

      expect(identical(first, second), isFalse);
      first[0] = 99;
      expect(region.readByte(0), 1);
      expect(second, <int>[1, 2, 3]);
    });
  });

  group('ByteRegion copy-on-write', () {
    test('replace shares the base and appends one patch', () {
      final base = ByteRegion.fromBytes(List<int>.generate(128, (i) => i));
      final edited = base.replace(const ByteSpan(4, 2), <int>[0xaa, 0xbb]);

      expect(identical(base.debugBase, edited.debugBase), isTrue);
      expect(base.patchCount, 0);
      expect(edited.patchCount, 1);
      expect(edited.patchByteCount, 2);
      expect(edited.length, base.length);
      expect(edited.readByte(4), 0xaa);
      expect(edited.readByte(5), 0xbb);
      expect(edited.readByte(6), 6);
    });

    test('many edits share the base until compaction', () {
      final base = ByteRegion.fromBytes(List<int>.generate(128, (i) => i));
      var region = base;
      for (var i = 0; i < 10; i++) {
        region = region.replace(ByteSpan(i, 1), <int>[0xff - i]);
      }

      expect(identical(base.debugBase, region.debugBase), isTrue);
      expect(region.patchCount, 10);
      expect(region.patchByteCount, 10);
      expect(region.readByte(0), 0xff);
      expect(region.readByte(9), 0xf6);
      expect(region.readByte(10), 10);
    });

    test('compaction preserves bytes and bounds patch overhead', () {
      final original = Uint8List.fromList(List<int>.generate(128, (i) => i));
      var region = ByteRegion.fromBytes(original);
      for (var i = 0; i < 70; i++) {
        region = region.replace(ByteSpan(i, 1), <int>[0xff - (i % 16)]);
      }

      expect(region.patchCount, lessThanOrEqualTo(ByteRegion.maxPatches));
      expect(
        region.patchByteCount,
        lessThanOrEqualTo(ByteRegion.maxPatchBytes),
      );
      final bytes = region.materialize();
      for (var i = 0; i < 70; i++) {
        expect(bytes[i], 0xff - (i % 16), reason: 'byte $i after compaction');
      }
      expect(bytes[70], 70);
    });

    test(
      'replace rejects out-of-range spans without changing the original',
      () {
        final region = ByteRegion.fromBytes(<int>[1, 2, 3]);

        expect(
          () => region.replace(const ByteSpan(3, 1), <int>[0]),
          throwsRangeError,
        );
        expect(
          () => region.replace(const ByteSpan(-1, 1), <int>[0]),
          throwsRangeError,
        );
        expect(
          () => region.replace(const ByteSpan(2, 2), <int>[0, 0]),
          throwsRangeError,
        );
        expect(region.patchCount, 0);
        expect(region.materialize(), <int>[1, 2, 3]);
      },
    );

    test('replace rejects a byte count that does not match the span', () {
      final region = ByteRegion.fromBytes(<int>[1, 2, 3]);

      expect(
        () => region.replace(const ByteSpan(0, 2), <int>[1]),
        throwsArgumentError,
      );
      expect(region.patchCount, 0);
    });

    test('BytePatch rejects mismatched lengths', () {
      expect(
        () => BytePatch(const ByteSpan(0, 2), <int>[1]),
        throwsArgumentError,
      );
      expect(
        () => BytePatch(const ByteSpan(-1, 1), <int>[1]),
        throwsRangeError,
      );
    });

    test('slice returns patched bytes in a new buffer', () {
      final region = ByteRegion.fromBytes(<int>[1, 2, 3, 4])
          .replace(const ByteSpan(1, 2), <int>[9, 8]);

      final slice = region.slice(const ByteSpan(1, 2));
      expect(slice, <int>[9, 8]);
      slice[0] = 0;
      expect(region.readByte(1), 9);
      expect(() => region.slice(const ByteSpan(3, 2)), throwsRangeError);
    });
  });

  group('ByteRegion reads', () {
    final region = ByteRegion.fromBytes(<int>[1, 2, 3, 4, 0xaa, 0xbb, 5, 6]);

    test('reads integers in both byte orders', () {
      expect(region.readByte(0), 1);
      expect(region.readU16BE(0), 0x0102);
      expect(region.readU16LE(0), 0x0201);
      expect(region.readU32BE(0), 0x01020304);
      expect(region.readU32LE(0), 0x04030201);
      expect(region.readU32BE(4), 0xaabb0506);
      expect(region.readU16BE(1), 0x0203);
    });

    test('reads see patches newest-over-oldest', () {
      final edited = region
          .replace(const ByteSpan(0, 2), <int>[0x11, 0x22])
          .replace(const ByteSpan(1, 2), <int>[0x33, 0x44]);

      expect(edited.readU16BE(0), 0x1133);
      expect(edited.readU16BE(1), 0x3344);
      expect(edited.materialize().sublist(0, 4), <int>[0x11, 0x33, 0x44, 4]);
    });

    test('throws RangeError for every out-of-bounds read', () {
      expect(() => region.readByte(-1), throwsRangeError);
      expect(() => region.readByte(region.length), throwsRangeError);
      expect(() => region.readU16BE(-1), throwsRangeError);
      expect(() => region.readU16BE(7), throwsRangeError);
      expect(() => region.readU16LE(7), throwsRangeError);
      expect(() => region.readU32BE(5), throwsRangeError);
      expect(() => region.readU32LE(5), throwsRangeError);
      expect(() => region.readU32BE(-1), throwsRangeError);
    });
  });

  group('fingerprint', () {
    test('is stable, cached, and changes with edits', () {
      final region = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final first = region.fingerprint;

      expect(region.fingerprint, first);
      final edited = region.replace(const ByteSpan(0, 1), <int>[9]);
      expect(edited.fingerprint, isNot(first));
      expect(edited.fingerprint, Fnv1a.hash32(edited.materialize()));
    });

    test('FNV-1a 32 matches published vectors', () {
      expect(Fnv1a.hash32(const <int>[]), 0x811c9dc5);
      expect(Fnv1a.hash32('a'.codeUnits), 0xe40c292c);
      expect(Fnv1a.hash32('foobar'.codeUnits), 0xbf9cf968);
      expect(Fnv1a.hex32(0x0abc), '00000abc');
    });

    test('hashes only the requested range', () {
      final bytes = <int>[1, 2, 3, 4];
      expect(Fnv1a.hash32(bytes, start: 1, end: 3), Fnv1a.hash32(<int>[2, 3]));
      expect(() => Fnv1a.hash32(bytes, start: -1), throwsRangeError);
      expect(() => Fnv1a.hash32(bytes, end: 5), throwsRangeError);
      expect(() => Fnv1a.hash32(bytes, start: 3, end: 2), throwsRangeError);
    });
  });
}
