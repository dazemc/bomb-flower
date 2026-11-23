import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart' hide Banner;

import '../../domain/core/core.dart';
import '../bloc/save_session/save_session_ui_state.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'save_dialog_frame.dart';

/// Reports the written files and fingerprints, or the blocking failure.
class ExportResultDialog extends StatefulWidget {
  /// Creates the dialog.
  const ExportResultDialog({
    super.key,
    this.succeeded = true,
    this.written = const <SlotWriteUi>[],
    this.issues = const <ValidationIssue>[],
    this.error,
    this.warnings = const <String>[],
    this.path,
    this.title,
    this.onCopyDetails,
  });

  /// Whether the export succeeded.
  final bool succeeded;

  /// Files written and verified.
  final List<SlotWriteUi> written;

  /// Validation or write issues.
  final List<ValidationIssue> issues;

  /// Unexpected failure text.
  final String? error;

  /// Non-fatal problems such as a failed mtime update.
  final List<String> warnings;

  /// Destination root, when known.
  final String? path;

  /// Overrides the default title.
  final String? title;

  /// Receives the assembled details instead of the clipboard, for tests.
  final void Function(String details)? onCopyDetails;

  /// Shows the dialog.
  static Future<void> show(
    BuildContext context, {
    bool succeeded = true,
    List<SlotWriteUi> written = const <SlotWriteUi>[],
    List<ValidationIssue> issues = const <ValidationIssue>[],
    String? error,
    List<String> warnings = const <String>[],
    String? path,
    String? title,
    void Function(String details)? onCopyDetails,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: BombFlowerColors.scrim,
      builder: (dialogContext) => ExportResultDialog(
        succeeded: succeeded,
        written: written,
        issues: issues,
        error: error,
        warnings: warnings,
        path: path,
        title: title,
        onCopyDetails: onCopyDetails,
      ),
    );
  }

  @override
  State<ExportResultDialog> createState() => _ExportResultDialogState();
}

class _ExportResultDialogState extends State<ExportResultDialog> {
  bool _copied = false;

  String get _details {
    final buffer = StringBuffer()
      ..writeln(
        widget.title ?? (widget.succeeded ? 'Save complete' : 'Save failed'),
      );
    if (widget.path != null) {
      buffer.writeln('Path: ${widget.path}');
    }
    if (widget.error != null) {
      buffer.writeln('Error: ${widget.error}');
    }
    if (widget.written.isNotEmpty) {
      buffer.writeln('Written:');
      for (final write in widget.written) {
        buffer.writeln(
          '  ${write.slot.value}  ${write.path}  '
          '${_fingerprintLabel(write.fingerprint)}',
        );
      }
    }
    if (widget.warnings.isNotEmpty) {
      buffer.writeln('Warnings:');
      for (final warning in widget.warnings) {
        buffer.writeln('  $warning');
      }
    }
    if (widget.issues.isNotEmpty) {
      buffer.writeln('Issues:');
      for (final issue in widget.issues) {
        buffer.writeln(
          '  [${issue.severity.name}] ${issue.code} · ${issue.slot.value} · '
          '${issue.message}'
          '${issue.remedy == null ? '' : ' · remedy: ${issue.remedy}'}',
        );
      }
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copy() async {
    final details = _details;
    final override = widget.onCopyDetails;
    if (override != null) {
      override(details);
    } else {
      await Clipboard.setData(ClipboardData(text: details));
    }
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final succeeded = widget.succeeded;
    return SaveDialogFrame(
      title:
          widget.title ??
          (succeeded ? 'Save complete' : 'The save was not written'),
      subtitle: widget.path,
      icon: succeeded ? Icons.check_circle_outline : Icons.error_outline,
      destructive: !succeeded,
      maxWidth: 560,
      footer: SaveDialogActions(
        children: <Widget>[
          BrassButton(
            key: const Key('export-copy-details'),
            label: _copied ? 'Copied' : 'Copy details',
            icon: _copied ? Icons.check : Icons.copy_all_outlined,
            variant: BrassButtonVariant.secondary,
            onPressed: _copy,
          ),
          BrassButton(
            key: const Key('export-close'),
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Banner(
            key: Key(
              succeeded ? 'export-success-banner' : 'export-failure-banner',
            ),
            variant: succeeded ? BannerVariant.success : BannerVariant.danger,
            title: succeeded
                ? '${widget.written.length} file(s) written and verified'
                : 'Nothing was written',
            message: succeeded
                ? 'Every written file was re-read and matched the payload.'
                : widget.error ??
                      'The export was refused before any file changed.',
          ),
          if (widget.warnings.isNotEmpty) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.lg),
            for (final warning in widget.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
                child: Banner(
                  key: const Key('export-warning-banner'),
                  variant: BannerVariant.warning,
                  title: 'Saved with a warning',
                  message: warning,
                ),
              ),
          ],
          if (succeeded) ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xl),
            Text(
              'Written files',
              style: BombFlowerTypography.label.copyWith(
                color: BombFlowerColors.ink,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.sm),
            if (widget.written.isEmpty)
              Text(
                'The repository did not report written paths.',
                style: BombFlowerTypography.caption.copyWith(
                  color: BombFlowerColors.inkMuted,
                ),
              )
            else
              for (final write in widget.written)
                Container(
                  key: Key('export-written-${write.slot.value}'),
                  margin: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
                  padding: const EdgeInsets.all(BombFlowerSpacing.lg),
                  decoration: BoxDecoration(
                    color: BombFlowerColors.parchmentSunken,
                    borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
                    border: Border.all(color: BombFlowerColors.stone),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            write.slot.value,
                            style: BombFlowerTypography.label.copyWith(
                              color: BombFlowerColors.ink,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _fingerprintLabel(write.fingerprint),
                            style: BombFlowerTypography.mono.copyWith(
                              fontSize: 11,
                              height: 16 / 11,
                              color: BombFlowerColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BombFlowerSpacing.xxs),
                      SelectableText(
                        write.path,
                        style: BombFlowerTypography.mono.copyWith(
                          fontSize: 11,
                          height: 16 / 11,
                          color: BombFlowerColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
          ] else ...<Widget>[
            const SizedBox(height: BombFlowerSpacing.xl),
            Text(
              'Blocking issues',
              style: BombFlowerTypography.label.copyWith(
                color: BombFlowerColors.ink,
              ),
            ),
            const SizedBox(height: BombFlowerSpacing.sm),
            if (widget.issues.isEmpty)
              Text(
                widget.error ?? 'The export was refused.',
                style: BombFlowerTypography.body.copyWith(
                  color: BombFlowerColors.inkSecondary,
                ),
              )
            else
              for (final issue in widget.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: BombFlowerSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        issue.isBlocking
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        size: 16,
                        color: issue.isBlocking
                            ? BombFlowerColors.danger
                            : BombFlowerColors.warning,
                      ),
                      const SizedBox(width: BombFlowerSpacing.md),
                      Expanded(
                        child: Text(
                          '${issue.slot.value}: ${issue.message}'
                          '${issue.remedy == null ? '' : ' (${issue.remedy})'}',
                          style: BombFlowerTypography.caption.copyWith(
                            color: BombFlowerColors.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  static String _fingerprintLabel(int? fingerprint) => fingerprint == null
      ? 'fingerprint unavailable'
      : '0x${fingerprint.toRadixString(16).padLeft(8, '0')}';
}
