import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../theme/bomb_flower_colors.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_typography.dart';
import '../common/brass_button.dart';
import '../common/parchment_panel.dart';

/// Static reference content: shortcuts, save safety, field rules, and the
/// Linux folder chooser.
///
/// The surface reads no session and no file: it is the same page every time it
/// opens. `app_shell.dart` binds `F1` to [HelpSurface.show], so the shortcut
/// opens this surface from anywhere in the shell.
class HelpSurface extends StatelessWidget {
  /// Creates the help surface.
  const HelpSurface({super.key});

  /// Opens the surface and completes when it closes.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => const HelpSurface(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final double bodyMaxHeight = (size.height * 0.6)
        .clamp(200.0, 560.0)
        .toDouble();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          key: const Key('help-surface'),
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'Help',
          child: Dialog(
            insetPadding: const EdgeInsets.all(BombFlowerSpacing.xxxl),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BombFlowerRadii.md),
                child: ParchmentPanel(
                  grainSeed: 3,
                  footer: Align(
                    alignment: Alignment.centerRight,
                    child: BrassButton(
                      key: const Key('help-surface-close'),
                      label: 'Close',
                      variant: BrassButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Help',
                        style: BombFlowerTypography.h1.copyWith(
                          color: BombFlowerColors.ink,
                        ),
                      ),
                      const SizedBox(height: BombFlowerSpacing.sm),
                      Container(
                        key: const Key('help-surface-rule'),
                        height: 2,
                        color: BombFlowerColors.brassInk,
                      ),
                      const SizedBox(height: BombFlowerSpacing.xl),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                        child: const SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _HelpSection(
                                key: Key('help-section-shortcuts'),
                                title: 'Keyboard shortcuts',
                                children: <Widget>[
                                  _ShortcutRow(
                                    combination: 'Ctrl+O',
                                    description: 'Open a save folder',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Ctrl+,',
                                    description: 'Settings',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Alt+1 … Alt+8',
                                    description:
                                        'Overview, Player/World, Inventory, '
                                        'Equipment, Resources, Progression, '
                                        'Dungeons, Collectibles',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Alt+0',
                                    description: 'Flags',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Alt+Shift+0',
                                    description: 'Advanced Data',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Ctrl+Tab / Ctrl+Shift+Tab',
                                    description: 'Cycle through tabs',
                                  ),
                                  _ShortcutRow(
                                    combination: 'F1',
                                    description: 'Help: this surface',
                                  ),
                                  _ShortcutRow(
                                    combination: 'Esc',
                                    description:
                                        'Close this surface or the open dialog',
                                  ),
                                ],
                              ),
                              _HelpSection(
                                key: Key('help-section-saving'),
                                title: 'Opening, saving and exporting safely',
                                children: <Widget>[
                                  _HelpParagraph(
                                    'Open a save folder, then use Save, '
                                    'Save As…, or Duplicate. Save As… and '
                                    'Duplicate write to a folder you choose; '
                                    'Save replaces the files of the slot you '
                                    'opened.',
                                  ),
                                  _HelpParagraph(
                                    'Saving keeps a .bak copy beside every '
                                    'replaced file. Exporting also keeps a '
                                    '<root>.bombflower-original/ sidecar beside '
                                    'the save root; it holds the bytes captured '
                                    'when the folder was opened.',
                                  ),
                                  _HelpParagraph(
                                    'An export never silently overwrites an '
                                    'original, and an existing sidecar is only '
                                    'reused after its files match byte for '
                                    'byte. Work on copies and keep your own '
                                    'backup outside the app.',
                                  ),
                                  _HelpParagraph(
                                    'Save patches only the edited value words. '
                                    'Everything else in the file is written '
                                    'back unchanged.',
                                  ),
                                ],
                              ),
                              _HelpSection(
                                key: Key('help-section-unknown-bytes'),
                                title: 'Unknown bytes are preserved',
                                children: <Widget>[
                                  _HelpParagraph(
                                    'Only the 4-byte value word of an edited, '
                                    'named field is patched. Every other byte, '
                                    'including unknown bytes and unknown '
                                    'regions, the sentinels, the header and the '
                                    'footer, round-trips exactly.',
                                  ),
                                  _HelpParagraph(
                                    'The format has no checksum, so none is '
                                    'invented and none is recomputed. A '
                                    'successful export means the editor wrote '
                                    'what it understood; it is not an integrity '
                                    'verdict.',
                                  ),
                                ],
                              ),
                              _HelpSection(
                                key: Key('help-section-fields'),
                                title: 'Verified fields and hash-only fields',
                                children: <Widget>[
                                  _HelpParagraph(
                                    'Named fields with a verified schema entry '
                                    'are editable. A hash-only field stays '
                                    'read-only: its bytes are kept and shown by '
                                    'hash, never reinterpreted.',
                                  ),
                                  _HelpParagraph(
                                    'Binary, BinaryArray and WString16Array '
                                    'spans are inferred and opaque, so this '
                                    'editor offers no typed editing inside '
                                    'them; use Advanced Data for raw inspection.',
                                  ),
                                ],
                              ),
                              _HelpSection(
                                key: Key('help-section-badges'),
                                title: 'Modified and Invalid badges',
                                children: <Widget>[
                                  _HelpParagraph(
                                    'Modified means the value differs from the '
                                    'bytes that were opened. Invalid means it '
                                    'fails this editor\u2019s validation; the '
                                    'game may clamp it silently at runtime, and '
                                    'the file keeps the value until the next '
                                    'in-game save.',
                                  ),
                                ],
                              ),
                              _HelpSection(
                                key: Key('help-section-picker'),
                                title: 'Choosing a folder on Linux',
                                children: <Widget>[
                                  _HelpParagraph(
                                    'Under the custom window frame, the native '
                                    'folder chooser\u2019s left folder pane may '
                                    'not respond to mouse clicks (upstream '
                                    'bitsdojo_window #273). Type the path into '
                                    'the field instead, or use the in-app save '
                                    'browser.',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BombFlowerSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: BombFlowerTypography.h3.copyWith(
              color: BombFlowerColors.successInk,
            ),
          ),
          const SizedBox(height: BombFlowerSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _HelpParagraph extends StatelessWidget {
  const _HelpParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
      child: Text(
        text,
        style: BombFlowerTypography.body.copyWith(
          color: BombFlowerColors.inkSecondary,
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.combination, required this.description});

  final String combination;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 176,
            child: Text(
              combination,
              style: BombFlowerTypography.mono.copyWith(
                color: BombFlowerColors.brassInk,
              ),
            ),
          ),
          const SizedBox(width: BombFlowerSpacing.md),
          Expanded(
            child: Text(
              description,
              style: BombFlowerTypography.body.copyWith(
                color: BombFlowerColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
