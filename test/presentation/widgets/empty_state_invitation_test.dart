import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/presentation/dialogs/open_save_dialog.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_colors.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:bomb_flower/presentation/widgets/common/open_save_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../dialogs/dialog_test_support.dart';

/// The always-empty folder inspector: no filesystem, no IO.
final class _FakeProbe implements SaveFolderProbe {
  @override
  Future<SaveFolderInfo> inspect(String path) async =>
      SaveFolderInfo(path: path, exists: false, isDirectory: false);
}

/// An in-memory recent-folder port so the dialog stays hermetic.
final class _FakeRecentPaths implements RecentPathsStore {
  @override
  Future<List<String>> read() async => const <String>[];

  @override
  Future<void> add(String path) async {}

  @override
  Future<void> clear() async {}
}

void _useView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1100, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'the no-save screen invites opening with a large button and a Ctrl+O hint',
    (tester) async {
      _useView(tester);

      await tester.pumpWidget(
        BombFlowerApp(
          enableWindowChrome: false,
          saveFolderProbe: _FakeProbe(),
          recentPaths: _FakeRecentPaths(),
          directoryLister: FakeDirectoryLister(),
        ),
      );
      await tester.pumpAndSettle();

      // The invitation is present exactly once, at the minimum window size.
      final invitation = find.byKey(const Key('empty-state-open-save'));
      expect(invitation, findsOneWidget);
      expect(find.text('Open save…'), findsOneWidget);
      expect(find.textContaining('slot_00'), findsOneWidget);

      final button = tester.getSize(invitation);
      expect(button.height, 48);
      expect(button.width, greaterThanOrEqualTo(240));

      // Copy is legible on the dark canopy, not ink on canopy.
      final title = tester.widget<Text>(find.text('Open a save to begin'));
      expect(title.style?.color, BombFlowerColors.bone);
      final hint = tester.widget<Text>(find.textContaining('slot_00'));
      expect(hint.style?.color, BombFlowerColors.boneMuted);
      expect(hint.data, contains('Ctrl+O'));
      expect(hint.data, contains('slot_00'));
      expect(tester.takeException(), isNull);

      await tester.tap(invitation);
      await tester.pumpAndSettle();

      expect(find.byType(OpenSaveDialog), findsOneWidget);
      expect(find.text('Open save folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a standalone empty state without a scope offers nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: const Scaffold(
          body: EmptyState(
            title: 'Nothing here yet',
            message: 'Open a save to see this surface.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Open save…'), findsNothing);
    expect(find.textContaining('Ctrl+O'), findsNothing);
  });

  testWidgets('a parchment empty state keeps ink and suppresses the invite', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BombFlowerThemeData.build(),
        home: Scaffold(
          backgroundColor: BombFlowerColors.parchment,
          body: OpenSaveScope(
            open: (_) async {},
            child: const EmptyState(
              title: 'No active slot buffer',
              message: 'The open save reports no bytes for its active slot.',
              onDark: false,
              offerOpenSave: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('No active slot buffer'));
    expect(title.style?.color, BombFlowerColors.ink);
    final message = tester.widget<Text>(
      find.text('The open save reports no bytes for its active slot.'),
    );
    expect(message.style?.color, BombFlowerColors.inkMuted);
    expect(find.text('Open save…'), findsNothing);
  });

  testWidgets(
    'busy empty states keep their own actions instead of the invite',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BombFlowerThemeData.build(),
          home: Scaffold(
            body: OpenSaveScope(
              open: (_) async {},
              child: EmptyState(
                title: 'No save file open.',
                message: 'Open a save to inspect its inventory.',
                primaryAction: BrassButton(
                  label: 'Open save',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open save'), findsOneWidget);
      expect(find.text('Open save…'), findsNothing);
    },
  );
}
