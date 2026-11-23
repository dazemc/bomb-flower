import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../bloc/shell/tab_definition.dart';
import '../theme/bomb_flower_colors.dart';
import '../theme/bomb_flower_spacing.dart';
import '../theme/bomb_flower_theme.dart';
import '../theme/bomb_flower_typography.dart';
import '../widgets/common/procedural_painters.dart';

/// Wood-bound primary navigation. Full width shows icons, labels, group
/// overlines, and shortcut hints; collapsed width is icon-only with tooltips.
class ShellNavRail extends StatelessWidget {
  const ShellNavRail({
    super.key,
    required this.activeTab,
    required this.collapsed,
    required this.onSelect,
  });

  final ShellTab activeTab;
  final bool collapsed;
  final ValueChanged<ShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;

    return Semantics(
      container: true,
      label: 'Primary sections',
      child: RepaintBoundary(
        child: CustomPaint(
          painter: const WoodGrainPainter(
            top: BombFlowerColors.wood,
            bottom: BombFlowerColors.woodDark,
            seed: 11,
            showBrassInlay: true,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: BombFlowerColors.stoneDark),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showGroupLabels =
                    !collapsed && constraints.maxHeight >= 620;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    collapsed ? BombFlowerSpacing.md : BombFlowerSpacing.lg,
                    BombFlowerSpacing.md,
                    collapsed ? BombFlowerSpacing.md : BombFlowerSpacing.lg,
                    BombFlowerSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final group in TabGroup.values) ...<Widget>[
                        if (showGroupLabels) ...<Widget>[
                          Padding(
                            padding: EdgeInsets.only(
                              top: group == TabGroup.character
                                  ? BombFlowerSpacing.md
                                  : BombFlowerSpacing.xxxl,
                              bottom: BombFlowerSpacing.md,
                              left: BombFlowerSpacing.lg,
                            ),
                            child: Text(
                              group == TabGroup.character
                                  ? 'CHARACTER'
                                  : 'WORLD & DATA',
                              style: BombFlowerTypography.overline.copyWith(
                                color: palette.textMutedOnDark,
                              ),
                            ),
                          ),
                        ],
                        for (final definition in kTabDefinitions)
                          if (definition.group == group)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: _NavItem(
                                definition: definition,
                                selected: definition.tab == activeTab,
                                collapsed: collapsed,
                                onTap: () => onSelect(definition.tab),
                              ),
                            ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.definition,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final TabDefinition definition;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.bombFlowerTheme;
    final height = widget.collapsed
        ? BombFlowerSpacing.navItemCollapsedHeight
        : BombFlowerSpacing.navItemHeight;
    final selected = widget.selected;
    final foreground = selected
        ? palette.textPrimary
        : _hovered
        ? palette.textOnDark
        : palette.textMutedOnDark;
    final iconColor = selected ? palette.accentInk : foreground;
    final hintColor = selected
        ? palette.textMuted
        : palette.textMutedOnDark.withValues(alpha: 0.85);

    final content = FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (value) {
        if (_hovered != value) setState(() => _hovered = value);
      },
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: BombFlowerMotion.adaptive(
                  context,
                  BombFlowerMotion.hover,
                ),
                curve: BombFlowerMotion.hoverCurve,
                height: height,
                decoration: BoxDecoration(
                  color: selected
                      ? palette.surface
                      : _hovered
                      ? BombFlowerColors.hoverDark
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(BombFlowerRadii.sm),
                  border: selected ? Border.all(color: palette.border) : null,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.collapsed ? 0 : BombFlowerSpacing.md,
                  ),
                  child: Row(
                    mainAxisAlignment: widget.collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: <Widget>[
                      Icon(widget.definition.icon, size: 18, color: iconColor),
                      if (!widget.collapsed) ...<Widget>[
                        const SizedBox(width: BombFlowerSpacing.md),
                        Expanded(
                          child: Text(
                            widget.definition.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BombFlowerTypography.button.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: BombFlowerSpacing.xs),
                        Text(
                          widget.definition.shortcutLabel,
                          style: BombFlowerTypography.overline.copyWith(
                            color: hintColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  left: -(widget.collapsed
                      ? BombFlowerSpacing.md
                      : BombFlowerSpacing.lg),
                  top: (height - 24) / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: 3,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: BombFlowerColors.brass,
                      ),
                    ),
                  ),
                ),
              if (_focused)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: const FocusRingPainter(
                          color: BombFlowerColors.brassFocus,
                          radius: BombFlowerRadii.sm,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final semantics = Semantics(
      key: Key('nav-tab-${widget.definition.tab.name}'),
      button: true,
      selected: selected,
      label: widget.definition.title,
      hint: 'Shortcut ${widget.definition.shortcutLabel}',
      excludeSemantics: true,
      child: content,
    );

    if (!widget.collapsed) return semantics;
    return Tooltip(
      message:
          '${widget.definition.title} (${widget.definition.shortcutLabel})',
      excludeFromSemantics: true,
      child: semantics,
    );
  }
}
