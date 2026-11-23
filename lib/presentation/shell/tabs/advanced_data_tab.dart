import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../../domain/core/edit_command.dart';
import '../../../domain/core/field_metadata.dart';
import '../../../domain/core/identity.dart';
import '../../bloc/shell/tab_definition.dart';
import '../../tabs_support/save_tab_scope.dart';
import '../../tabs_support/save_tab_source.dart';
import '../../theme/bomb_flower_spacing.dart';
import '../../theme/bomb_flower_theme.dart';
import '../../theme/bomb_flower_typography.dart';
import '../../widgets/common/banner.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/parchment_panel.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/controls/brass_toggle.dart';
import '../../widgets/hex/hex.dart';
import 'placeholder_tab.dart';

/// Raw byte inspection for the active save slot, with gated hex editing.
///
/// The editor renders a defensive copy of [SaveTabSource.activeSlotBytes], so a
/// local write can never reach engine state directly. Every accepted write is
/// mediated back through [SaveTabSource.edit] as one `SetBytes` per changed
/// field, and a byte outside every editable named field is restored rather than
/// kept. Search, jump-to-address, the bit inspector, and the mark legend are
/// provided by [HexEditor]; this tab does not reimplement them.
class AdvancedDataTab extends StatefulWidget {
  /// Creates the advanced data tab.
  const AdvancedDataTab({super.key, this.controller});

  /// Optional injected controller (tests). When null the tab builds and owns a
  /// controller from [SaveTabSource.activeSlotBytes].
  final HexEditorController? controller;

  /// Key for the "Unlock editing" toggle.
  static const Key unlockToggleKey = ValueKey<String>(
    'advanced-unlock-editing',
  );

  /// Key for the embedded hex editor.
  static const Key editorKey = ValueKey<String>('advanced-hex-editor');

  /// Key for the banner shown after an out-of-field byte is restored.
  static const Key restoreBannerKey = ValueKey<String>(
    'advanced-restore-banner',
  );

  /// Key for the buffer-length read-out.
  static const Key bufferLengthKey = ValueKey<String>('advanced-buffer-length');

  @override
  State<AdvancedDataTab> createState() => _AdvancedDataTabState();
}

class _AdvancedDataTabState extends State<AdvancedDataTab> {
  /// Height reserved for the editor inside the scrolling page frame.
  static const double _editorHeight = 520;

  bool _unlocked = false;
  HexEditorController? _owned;
  Uint8List? _sourceBytes;
  Uint8List? _lastBytes;
  int _lastRevision = 0;
  bool _reverting = false;
  String? _restoreMessage;
  SaveTabSource? _source;

  HexEditorController? get _controller => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _attachInjected(injected);
    }
  }

  @override
  void didUpdateWidget(covariant AdvancedDataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onControllerChanged);
    if (widget.controller != null) {
      _replaceOwned(null);
      _attachInjected(widget.controller!);
    } else {
      _sourceBytes = null;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _owned?.removeListener(_onControllerChanged);
    _owned?.dispose();
    super.dispose();
  }

  void _attachInjected(HexEditorController controller) {
    controller.addListener(_onControllerChanged);
    _lastBytes = Uint8List.fromList(controller.bytes);
    _lastRevision = controller.revision;
  }

  @override
  Widget build(BuildContext context) {
    final source = SaveTabScope.maybeOf(context);
    if (source == null || !source.isOpen) {
      return const TabPageFrame(
        child: EmptyState(
          title: 'Open a save to begin',
          message:
              'Open a save folder to inspect its raw bytes and edit the named '
              'fields the layout verifies.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: source.changes,
      builder: (BuildContext context, Widget? _) {
        _source = source;
        if (widget.controller == null) {
          _syncFromSource(source);
        }
        final controller = _controller;
        if (controller == null || controller.isEmpty) {
          return _noBufferPage();
        }
        return _bufferPage(context, source, controller);
      },
    );
  }

  /// Keeps the owned controller in step with the source without rebuilding it
  /// on every frame: only new source bytes or an unlock change recreate it.
  void _syncFromSource(SaveTabSource source) {
    final bytes = source.activeSlotBytes;
    if (bytes == null || bytes.isEmpty) {
      _sourceBytes = null;
      _replaceOwned(null);
      return;
    }
    final unchanged = _sourceBytes != null && listEquals(bytes, _sourceBytes);
    if (_owned != null && unchanged) return;

    _sourceBytes = Uint8List.fromList(bytes);
    _replaceOwned(
      HexEditorController(
        bytes: Uint8List.fromList(bytes),
        readOnly: !_unlocked,
        editableRange: _unlocked
            ? HexEditableRange(start: 0, end: bytes.length)
            : null,
      ),
    );
  }

  void _replaceOwned(HexEditorController? next) {
    final previous = _owned;
    if (previous == next) return;
    previous?.removeListener(_onControllerChanged);
    _owned = next;
    next?.addListener(_onControllerChanged);
    if (next == null) {
      _lastBytes = null;
      _lastRevision = 0;
    } else {
      _lastBytes = Uint8List.fromList(next.bytes);
      _lastRevision = next.revision;
    }
    if (previous != null) {
      // Let the editor detach its listener first; removeListener is safe on a
      // disposed notifier, but a notification between frames is not.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _setUnlocked(bool value) {
    setState(() {
      _unlocked = value;
      if (widget.controller == null) {
        _sourceBytes = null;
      }
    });
  }

  /// The single write gate. Compares the controller buffer with the last
  /// accepted buffer and turns each changed offset into either exactly one
  /// `SetBytes` per owning field or a restore from [_lastBytes].
  void _onControllerChanged() {
    if (!mounted || _reverting) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.revision == _lastRevision) return;

    final previous = _lastBytes;
    if (previous == null || previous.length != controller.length) {
      _lastRevision = controller.revision;
      _lastBytes = Uint8List.fromList(controller.bytes);
      return;
    }

    final changed = <int>[];
    for (var offset = 0; offset < previous.length; offset++) {
      if (previous[offset] != controller.bytes[offset]) {
        changed.add(offset);
      }
    }
    if (changed.isEmpty) {
      _lastRevision = controller.revision;
      return;
    }

    final source = _source;
    final editable = source == null
        ? const <TabFieldView>[]
        : _editableViews(source, controller.length);
    final targets = <FieldId, TabFieldView>{};
    final rejected = <int>[];
    for (final offset in changed) {
      final view = _viewContaining(editable, offset);
      if (view == null) {
        rejected.add(offset);
      } else {
        targets[view.descriptor.id] = view;
      }
    }

    String? restored;
    if (rejected.isNotEmpty) {
      _reverting = true;
      try {
        for (final offset in rejected) {
          controller.writeByte(offset, previous[offset]);
        }
      } finally {
        _reverting = false;
      }
      restored = rejected.length == 1
          ? 'Byte 0x${_hex2(rejected.single)} was not inside an editable named '
                'field and was restored.'
          : '${rejected.length} bytes were not inside editable named fields '
                'and were restored.';
    }

    _lastRevision = controller.revision;
    _lastBytes = Uint8List.fromList(controller.bytes);

    if (source != null) {
      for (final view in targets.values) {
        final span = view.descriptor.span;
        source.edit(
          SetBytes(
            view.descriptor.id,
            target: span,
            bytes: controller.bytes.sublist(span.offset, span.end),
          ),
        );
      }
    }

    if (restored != null && mounted) {
      setState(() => _restoreMessage = restored);
    }
  }

  List<TabFieldView> _editableViews(SaveTabSource source, int length) {
    final seen = <FieldId>{};
    final views = <TabFieldView>[];
    for (final view in source.allViews) {
      final descriptor = view.descriptor;
      if (!descriptor.isEditable || !seen.add(descriptor.id)) continue;
      final span = descriptor.span;
      if (!span.isValid ||
          span.length == 0 ||
          span.offset < 0 ||
          span.end > length) {
        continue;
      }
      views.add(view);
    }
    return views;
  }

  TabFieldView? _viewContaining(List<TabFieldView> views, int offset) {
    for (final view in views) {
      final span = view.descriptor.span;
      if (offset >= span.offset && offset < span.end) return view;
    }
    return null;
  }

  Widget _noBufferPage() {
    final definition = ShellTab.advancedData.definition;
    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 9,
        padding: const EdgeInsets.fromLTRB(
          BombFlowerSpacing.panelPadding,
          0,
          BombFlowerSpacing.panelPadding,
          BombFlowerSpacing.panelPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              eyebrow: definition.eyebrow,
              title: definition.title,
              description: definition.purpose,
            ),
            const EmptyState(
              title: 'No active slot buffer',
              message:
                  'The open save reports no bytes for its active slot. Nothing '
                  'is fabricated; open a save with a loaded slot to inspect its '
                  'bytes.',
              // This state sits inside a parchment panel, not on the canopy.
              onDark: false,
              offerOpenSave: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bufferPage(
    BuildContext context,
    SaveTabSource source,
    HexEditorController controller,
  ) {
    final definition = ShellTab.advancedData.definition;
    final palette = context.bombFlowerTheme;
    final slot = source.activeSlot;
    final marks = _marksFor(source, controller.length);
    final bitLabels = _bitLabelsFor(source, controller.length);

    return TabPageFrame(
      child: ParchmentPanel(
        grainSeed: 9,
        padding: const EdgeInsets.fromLTRB(
          BombFlowerSpacing.panelPadding,
          0,
          BombFlowerSpacing.panelPadding,
          BombFlowerSpacing.panelPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              eyebrow: definition.eyebrow,
              title: definition.title,
              description: definition.purpose,
              isModified: source.isDirty,
            ),
            Wrap(
              spacing: BombFlowerSpacing.xl,
              runSpacing: BombFlowerSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                BrassToggle(
                  key: AdvancedDataTab.unlockToggleKey,
                  value: _unlocked,
                  onChanged: _setUnlocked,
                  label: 'Unlock editing',
                  description: _unlocked
                      ? 'Writes are limited to editable named fields.'
                      : 'Read-only. Turn on to write through named fields.',
                ),
                Text(
                  '${controller.length} bytes in the active slot buffer',
                  key: AdvancedDataTab.bufferLengthKey,
                  style: BombFlowerTypography.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                if (slot != null)
                  Text(
                    'Slot ${slot.value}',
                    style: BombFlowerTypography.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: BombFlowerSpacing.md),
            Text(
              'Edits are refused outside editable named fields; such a byte is '
              'restored immediately. Search and jump cover the whole buffer.',
              style: BombFlowerTypography.caption.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (_restoreMessage case final message?) ...<Widget>[
              const SizedBox(height: BombFlowerSpacing.md),
              Banner(
                key: AdvancedDataTab.restoreBannerKey,
                title: 'Edit refused',
                message: message,
                variant: BannerVariant.danger,
                onDismiss: () => setState(() => _restoreMessage = null),
              ),
            ],
            const SizedBox(height: BombFlowerSpacing.lg),
            SizedBox(
              height: _editorHeight,
              child: HexEditor(
                key: AdvancedDataTab.editorKey,
                controller: controller,
                marks: marks,
                modifiedOffsets: controller.modifiedOffsets,
                bitLabelProvider: (int offset, int bit) =>
                    bitLabels[offset]?[bit],
                title: 'Raw bytes',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dirty spans are marked modified; spans with an issue are marked invalid.
  /// A byte can carry only one mark, and an issue is the stronger signal.
  Map<int, ByteMarkKind> _marksFor(SaveTabSource source, int length) {
    final marks = <int, ByteMarkKind>{};
    final seen = <FieldId>{};
    for (final view in source.allViews) {
      if (!seen.add(view.descriptor.id)) continue;
      final span = view.descriptor.span;
      if (!span.isValid ||
          span.length == 0 ||
          span.offset < 0 ||
          span.end > length) {
        continue;
      }
      if (view.isDirty) {
        for (var offset = span.offset; offset < span.end; offset++) {
          marks[offset] = ByteMarkKind.modified;
        }
      }
      if (view.issueMessage != null) {
        for (var offset = span.offset; offset < span.end; offset++) {
          marks[offset] = ByteMarkKind.invalid;
        }
      }
    }
    return marks;
  }

  /// Bit meanings are derived only from verified descriptors: bit 0 names a
  /// boolean field, and every bit of a bitfield span is named. Nothing else is
  /// labelled, so no meaning is invented.
  Map<int, List<String?>> _bitLabelsFor(SaveTabSource source, int length) {
    final labels = <int, List<String?>>{};
    final seen = <FieldId>{};
    for (final view in source.allViews) {
      final descriptor = view.descriptor;
      if (!seen.add(descriptor.id)) continue;
      if (descriptor.confidence != FieldConfidence.verified) continue;
      final span = descriptor.span;
      if (!span.isValid ||
          span.length == 0 ||
          span.offset < 0 ||
          span.end > length) {
        continue;
      }
      if (descriptor.kind == FieldKind.boolean) {
        final row = labels.putIfAbsent(
          span.offset,
          () => List<String?>.filled(8, null),
        );
        row[0] ??= descriptor.label;
      } else if (descriptor.kind == FieldKind.bitfield) {
        for (var offset = span.offset; offset < span.end; offset++) {
          final row = labels.putIfAbsent(
            offset,
            () => List<String?>.filled(8, null),
          );
          for (var bit = 0; bit < 8; bit++) {
            row[bit] ??= '${descriptor.label} bit $bit';
          }
        }
      }
    }
    return labels;
  }
}

String _hex2(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
