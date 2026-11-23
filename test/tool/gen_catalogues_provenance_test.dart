import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_catalogues.dart';

void main() {
  const repoRoot = '/repo';
  const scenes = '/repo/.tmp/catalogue/scenes/scenes.longshot.json';

  test('a resolved path under the repo yields the repo-relative form', () {
    final provenance = catalogueProvenancePath(scenes, repoRoot: repoRoot);
    expect(provenance, '.tmp/catalogue/scenes/scenes.longshot.json');
    expect(provenance, isNot(startsWith('/')));
    expect(catalogueRangesPath(provenance), '.tmp/catalogue/scenes/RANGES.md');
  });

  test('a resolved path outside the repo stays absolute', () {
    const outside = '/srv/extract/scenes/scenes.longshot.json';
    expect(catalogueProvenancePath(outside, repoRoot: repoRoot), outside);
    expect(catalogueRangesPath(outside), '/srv/extract/scenes/RANGES.md');
  });

  test('a .tmp-based resolution never records the pre-move path', () {
    final provenance = catalogueProvenancePath(scenes, repoRoot: repoRoot);
    expect(provenance, isNot(contains('/tmp/opencode')));
    expect(catalogueRangesPath(provenance), isNot(contains('/tmp/opencode')));
  });

  test('output is stable across repeated calls', () {
    final first = catalogueProvenancePath(scenes, repoRoot: repoRoot);
    final second = catalogueProvenancePath(scenes, repoRoot: repoRoot);
    expect(second, first);
    // A trailing separator on the repo root normalizes identically.
    expect(catalogueProvenancePath(scenes, repoRoot: '/repo/'), first);
  });
}
