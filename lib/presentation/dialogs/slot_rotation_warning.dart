import 'package:material_ui/material_ui.dart' hide Banner;

import '../bloc/save_session/save_session_ui_state.dart';
import '../widgets/common/banner.dart';
import '../widgets/common/brass_button.dart';
import 'dialog_copy.dart';

/// Persistent warning when the active slot is not the one Longshot will load.
///
/// The banner is deliberately not dismissible: the load order remains wrong
/// until the user switches slots or updates the timestamp.
class SlotRotationWarning extends StatelessWidget {
  /// Creates the warning.
  const SlotRotationWarning({
    super.key,
    required this.project,
    this.onUseNewestSlot,
  });

  /// Project whose active/newest slots are compared.
  final SaveProjectUi project;

  /// Called when the user chooses "Use newest slot".
  final VoidCallback? onUseNewestSlot;

  @override
  Widget build(BuildContext context) {
    final newest = project.newestSlot;
    if (newest == null || project.isActiveSlotNewest) {
      return const SizedBox.shrink();
    }
    return Banner(
      key: const Key('slot-rotation-warning'),
      variant: BannerVariant.warning,
      title: 'Not the newest slot',
      message: SaveWorkflowCopy.notNewestSlot(newest),
      action: project.canUseNewestSlot && onUseNewestSlot != null
          ? BrassButton(
              key: const Key('use-newest-slot'),
              label: 'Use newest slot',
              variant: BrassButtonVariant.text,
              onPressed: onUseNewestSlot,
            )
          : null,
    );
  }
}
