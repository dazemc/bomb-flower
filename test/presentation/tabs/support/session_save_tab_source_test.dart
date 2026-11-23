import 'package:bomb_flower/domain/core/identity.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSaveTabSource _emptySource({List<SlotAge>? ages, Listenable? changes}) {
  return SessionSaveTabSource(
    project: () => null,
    edit: (_) {},
    undo: () {},
    redo: () {},
    slotAges: ages == null ? null : () => ages,
    changes: changes,
  );
}

void main() {
  test('a null project renders an honest empty source', () {
    final source = _emptySource();

    expect(source.isOpen, isFalse);
    expect(source.rootPath, isNull);
    expect(source.activeSlot, isNull);
    expect(source.isDirty, isFalse);
    expect(source.changedFieldCount, 0);
    expect(source.canUndo, isFalse);
    expect(source.canRedo, isFalse);
    expect(source.allViews, isEmpty);
  });

  test('viewsFor returns empty for every group without a project', () {
    final source = _emptySource();

    for (final group in EditorTabGroup.values) {
      expect(source.viewsFor(group), isEmpty, reason: group.id);
    }
  });

  test('changes is the supplied Listenable and the default stays silent', () {
    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    final supplied = _emptySource(changes: notifier);
    var calls = 0;
    void listener() => calls++;

    expect(supplied.changes, same(notifier));

    final defaulted = _emptySource();
    defaulted.changes.addListener(listener);
    defaulted.changes.removeListener(listener);
    expect(calls, 0);
  });

  test('newestSlot picks the latest known modification time', () {
    final source = _emptySource(
      ages: <SlotAge>[
        SlotAge(
          slot: SaveSlotId.progress(0),
          progressPath: 'slot_00/progress.sav',
          modifiedAt: DateTime.utc(2026, 11, 20),
        ),
        SlotAge(
          slot: SaveSlotId.progress(2),
          progressPath: 'slot_02/progress.sav',
          modifiedAt: DateTime.utc(2026, 11, 22),
        ),
        SlotAge(slot: SaveSlotId.account, progressPath: 'account.sav'),
      ],
    );

    expect(source.newestSlot, SaveSlotId.progress(2));
    expect(source.slotAges, hasLength(3));
  });

  test('newestSlot is null when no timestamps are known', () {
    expect(_emptySource().newestSlot, isNull);

    final untimed = _emptySource(
      ages: <SlotAge>[
        SlotAge(slot: SaveSlotId.account, progressPath: 'account.sav'),
      ],
    );
    expect(untimed.newestSlot, isNull);
  });
}
