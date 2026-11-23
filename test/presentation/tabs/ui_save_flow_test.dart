/// End-to-end UI flow over the real app shell and a real save on disk:
/// open the `kokiri-start` fixture, edit Life in the Resources tab, watch the
/// dirty state, undo on the Overview tab, edit again, Save As through the real
/// `SaveAsDialog`, and reopen the export with a fresh session.
///
/// The group is skipped with an actionable reason when the local fixture is
/// absent; when it is present every step must run. The fixture is never
/// modified: `slot_00` is copied into a system temp workspace first, and the
/// copy, its sidecar and the export destination are removed on teardown.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/dialogs/save_as_dialog.dart';
import 'package:bomb_flower/presentation/shell/tabs/resources_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/field_editor.dart';
import 'package:bomb_flower/presentation/widgets/common/brass_button.dart';
import 'package:bomb_flower/presentation/widgets/common/rune_chip.dart';
import 'package:bomb_flower/presentation/widgets/controls/control_icon_button.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/ui_flow_fixture.dart';

/// The nav-rail key the app puts on each `Semantics` entry.
Key _navTab(String tabName) => Key('nav-tab-$tabName');

void main() {
  final fixtureAvailable = uiFlowFixtureAvailable;

  group(
    'app UI flow: open, edit, undo, save as, reopen',
    skip: fixtureAvailable ? null : uiFlowFixtureMissingReason,
    () {
      if (!fixtureAvailable) {
        // A group-level skip only reports its reason when the group holds a
        // test, so the absent-fixture run explains itself.
        test('no fixture present', () {
          fail('unreachable: the group is skipped');
        });
        return;
      }

      testWidgets(
        'drives the real app from open to a byte-exact exported save',
        (tester) async {
          prepareUiFlowView(tester);

          // A private workspace: the fixture itself is only ever read.
          final workspace = Directory.systemTemp.createTempSync(
            'bomb_flower_ui_flow_',
          );
          final copyRoot = Directory('${workspace.path}/save');
          final destination = Directory('${workspace.path}/export');
          final paths = <Directory>[
            copyRoot,
            destination,
            Directory('${copyRoot.path}.bombflower-original'),
            Directory('${destination.path}.bombflower-original'),
            workspace,
          ];
          addTearDown(() {
            for (final directory in paths) {
              if (directory.existsSync()) {
                directory.deleteSync(recursive: true);
              }
            }
          });

          copyUiFlowSlot(uiFlowFixtureRoot(), copyRoot);
          final sourceProgressPath = '${copyRoot.path}/slot_00/progress.sav';
          final sourceCaptionPath = '${copyRoot.path}/slot_00/caption.sav';
          final originalProgress = Uint8List.fromList(
            File(sourceProgressPath).readAsBytesSync(),
          );
          final originalCaption = Uint8List.fromList(
            File(sourceCaptionPath).readAsBytesSync(),
          );
          expect(originalProgress, hasLength(uiFlowProgressLength));

          final schema = await tester.runAsync(loadUiFlowSchema);
          expect(schema, isNotNull, reason: 'the bundled schema must load');
          final lifeOffset = uiFlowLifeValueOffset(schema!);
          expect(lifeOffset, uiFlowLifeOffset);
          expect(hexU32(originalProgress, lifeOffset), '0c 00 00 00');

          final session = openUiFlowSession(schema);
          addTearDown(() async {
            if (!session.isClosed) {
              await session.close(force: true);
            }
          });

          await tester.pumpWidget(
            BombFlowerApp(
              enableWindowChrome: false,
              session: session,
              saveFolderProbe: const UiFlowFolderProbe(),
            ),
          );
          await tester.pumpAndSettle();

          // Real filesystem work cannot run on the fake-async clock.
          await tester.runAsync(() => session.openPath(copyRoot.path));
          await tester.pumpAndSettle();
          expect(session.state, isA<SaveSessionReady>());

          NumericField lifeField() => tester.widget<NumericField>(
            find.descendant(
              of: find.byKey(ResourcesTab.lifeFieldKey),
              matching: find.byType(NumericField),
            ),
          );
          Finder lifeInput() => find.descendant(
            of: find.byKey(ResourcesTab.lifeFieldKey),
            matching: find.byType(TextField),
          );
          // RuneChip stamps its label in upper case (rune_chip.dart:61), so
          // match the variant, not the title-case source string.
          Finder modifiedChips() => find.byWidgetPredicate(
            (widget) =>
                widget is RuneChip &&
                widget.variant == RuneChipVariant.modified,
          );
          Finder fieldModified() => find.descendant(
            of: find.byType(FieldEditor),
            matching: modifiedChips(),
          );

          // Resources: the real save's verified Life renders as 12.
          await tester.tap(find.byKey(_navTab('resources')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('tab-page-resources')), findsOneWidget);
          expect(lifeField().value, 12);
          expect(find.text('3 hearts / 3 hearts'), findsOneWidget);

          // Edit 12 -> 16 through the real control.
          await tester.ensureVisible(lifeInput());
          await tester.pump();
          await tester.enterText(lifeInput(), '16');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(lifeField().value, 16);
          expect(find.text('4 hearts / 3 hearts'), findsOneWidget);
          expect(fieldModified(), findsOneWidget);
          // The field chip and the tab header chip, and what the user reads.
          expect(modifiedChips(), findsNWidgets(2));
          expect(find.text('MODIFIED'), findsNWidgets(2));

          // Overview reports the one changed field, then its real undo button.
          await tester.tap(find.byKey(_navTab('overview')));
          await tester.pumpAndSettle();
          expect(find.text('1 modified field'), findsOneWidget);

          final undo = find.byKey(const Key('overview-undo'));
          await tester.ensureVisible(undo);
          await tester.pump();
          await tester.tap(undo);
          await tester.pumpAndSettle();
          expect(find.text('0 modified fields'), findsOneWidget);

          // Back on Resources the undo is visible: Life is 12 and clean again.
          await tester.tap(find.byKey(_navTab('resources')));
          await tester.pumpAndSettle();
          expect(lifeField().value, 12);
          expect(fieldModified(), findsNothing);
          expect(modifiedChips(), findsNothing);
          expect(find.text('MODIFIED'), findsNothing);

          // Edit again, this time to export.
          await tester.ensureVisible(lifeInput());
          await tester.pump();
          await tester.enterText(lifeInput(), '16');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(lifeField().value, 16);
          expect(fieldModified(), findsOneWidget);

          // Save As through the shell's own action: the title bar's
          // `shell-action-save-as` opens SaveAsDialog and its submit runs the
          // real export itself (app_title_bar.dart `_saveAs`).
          final saveAsAction = find.byKey(const Key('shell-action-save-as'));
          expect(saveAsAction, findsOneWidget);
          // Enabled, not merely present: a disabled control would make the tap
          // below a no-op and let the test pass without opening the dialog.
          expect(
            tester
                .widget<ControlIconButton>(
                  find.descendant(
                    of: saveAsAction,
                    matching: find.byType(ControlIconButton),
                  ),
                )
                .onPressed,
            isNotNull,
            reason: 'Save As must be enabled with a project open',
          );
          await tester.tap(saveAsAction);
          // The title bar's double-tap recognizer holds the gesture arena until
          // its timer expires; advance the fake clock as the existing
          // app_title_bar_actions_test `tapAction` helper does.
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(find.byType(SaveAsDialog), findsOneWidget);

          await tester.enterText(
            find.byKey(const Key('save-as-path')),
            destination.path,
          );
          await tester.pumpAndSettle();
          final submit = find.byKey(const Key('save-as-submit'));
          expect(tester.widget<BrassButton>(submit).onPressed, isNotNull);
          await tester.tap(submit);
          await tester.pumpAndSettle();

          // The click handler's export continuations are scheduled in the
          // fake-async zone, which `runAsync` alone cannot drain: flutter_test
          // forks the zone but never flushes FakeAsync (binding.dart
          // `runAsync`). Alternate a fake-clock pump (drain microtasks) with a
          // real delay (let file I/O complete) until the session reaches a
          // terminal state.
          final exportedFile = File('${destination.path}/slot_00/progress.sav');
          Future<void> awaitSaveTerminal() async {
            final deadline = DateTime.now().add(const Duration(seconds: 20));
            while (DateTime.now().isBefore(deadline)) {
              final state = session.state;
              if (state is SaveSessionSaved || state is SaveSessionError) {
                return;
              }
              await tester.pump(const Duration(milliseconds: 10));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
            }
          }

          await awaitSaveTerminal();
          await tester.pumpAndSettle();

          final terminal = session.state;
          if (terminal is SaveSessionError) {
            fail(
              'the Save As click ended in SaveSessionError: '
              '${terminal.message} | ${terminal.details}',
            );
          }
          if (terminal is! SaveSessionSaved) {
            fail(
              'the Save As click never reached a terminal state within 20s; '
              'actual state: ${terminal.runtimeType}, progress.sav exists: '
              '${exportedFile.existsSync()}',
            );
          }
          final savedState = terminal;
          expect(
            exportedFile.existsSync(),
            isTrue,
            reason: 'the shell Save As click must write the export',
          );
          expect(savedState.path, destination.path);
          expect(savedState.mode, ExportMode.saveAs);
          expect(savedState.statusMessage, startsWith('Saved to'));

          // Exact byte comparison of the export against the pre-open copy.
          expect(exportedFile.existsSync(), isTrue);
          final exported = Uint8List.fromList(exportedFile.readAsBytesSync());
          expect(exported.length, originalProgress.length);
          expect(exported.length, uiFlowProgressLength);

          final differing = differingByteIndices(originalProgress, exported);
          for (final index in differing) {
            expect(
              index,
              inInclusiveRange(uiFlowLifeOffset, uiFlowLifeOffset + 3),
              reason:
                  'byte 0x${index.toRadixString(16)} is outside the Life '
                  'value span',
            );
          }
          expect(differing, hasLength(1));
          expect(differing.single, uiFlowLifeOffset);
          expect(hexU32(originalProgress, lifeOffset), '0c 00 00 00');
          expect(hexU32(exported, lifeOffset), '10 00 00 00');
          stdout.writeln(
            '[ui-flow] offset=0x${lifeOffset.toRadixString(16)} '
            'original=${hexU32(originalProgress, lifeOffset)} '
            'exported=${hexU32(exported, lifeOffset)} '
            'differingBytes=${differing.length}',
          );

          // Save As must leave the source copy untouched.
          expect(
            Uint8List.fromList(File(sourceProgressPath).readAsBytesSync()),
            orderedEquals(originalProgress),
            reason: 'Save As must not rewrite the open copy',
          );
          expect(
            Uint8List.fromList(File(sourceCaptionPath).readAsBytesSync()),
            orderedEquals(originalCaption),
            reason: 'Save As must not rewrite the caption copy',
          );

          // Reopen the export with an entirely fresh session.
          final fresh = openUiFlowSession(schema);
          addTearDown(() async {
            if (!fresh.isClosed) {
              await fresh.close(force: true);
            }
          });

          await tester.runAsync(() => fresh.openPath(destination.path));
          await tester.pumpAndSettle();
          expect(fresh.state, isA<SaveSessionReady>());

          final reopenedProject = fresh.openProject;
          expect(reopenedProject, isNotNull);
          final lifeValue = reopenedProject!
              .document(SaveSlotId.progress(0))!
              .fields
              .firstWhere(
                (field) => field.descriptor.label == 'PlayerStatus.Life',
              )
              .value;
          expect(lifeValue, const IntValue(16));

          await tester.pumpWidget(
            BombFlowerApp(
              enableWindowChrome: false,
              session: fresh,
              saveFolderProbe: const UiFlowFolderProbe(),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(_navTab('resources')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('tab-page-resources')), findsOneWidget);
          expect(lifeField().value, 16);
          expect(find.text('4 hearts / 3 hearts'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
