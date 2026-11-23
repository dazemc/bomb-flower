import 'package:equatable/equatable.dart';

import 'tab_definition.dart';

/// Health of the footer validation summary, which colours the status dot.
enum ShellValidationHealth {
  /// No session has reported yet; the placeholder wording is still showing.
  unknown,

  /// The session validated with no issues.
  ok,

  /// Non-blocking issues exist.
  warnings,

  /// At least one blocking error exists.
  errors,
}

/// Shell presentation state. Placeholder strings are explicit; no save values
/// are invented here.
class ShellState extends Equatable {
  const ShellState({
    this.activeTab = ShellTab.overview,
    this.navCollapsed = false,
    this.windowChromeEnabled = true,
    this.statusMessage = 'Engine pending — no save engine connected',
    this.validationSummary = 'Validation: engine pending',
    this.validationHealth = ShellValidationHealth.unknown,
    this.filePath,
    this.revision = '—',
    this.isDirty = false,
    this.saveName,
  });

  final ShellTab activeTab;
  final bool navCollapsed;
  final bool windowChromeEnabled;

  /// Connection / engine status text; the save engine is not wired yet.
  final String statusMessage;

  /// Footer validation summary. Not a count until the engine exists.
  final String validationSummary;

  /// Health behind [validationSummary], used to colour the status dot.
  final ShellValidationHealth validationHealth;

  /// Absolute or display path of the open save, null when none is open.
  final String? filePath;

  /// Save revision or version label, em dash until the engine supplies one.
  final String revision;

  /// Reserve slot for the future save engine's unsaved-change flag.
  final bool isDirty;

  /// Save identity shown in the title bar, null when no file is open.
  final String? saveName;

  ShellState copyWith({
    ShellTab? activeTab,
    bool? navCollapsed,
    bool? windowChromeEnabled,
    String? statusMessage,
    String? validationSummary,
    ShellValidationHealth? validationHealth,
    String? filePath,
    String? revision,
    bool? isDirty,
    String? saveName,
  }) {
    return ShellState(
      activeTab: activeTab ?? this.activeTab,
      navCollapsed: navCollapsed ?? this.navCollapsed,
      windowChromeEnabled: windowChromeEnabled ?? this.windowChromeEnabled,
      statusMessage: statusMessage ?? this.statusMessage,
      validationSummary: validationSummary ?? this.validationSummary,
      validationHealth: validationHealth ?? this.validationHealth,
      filePath: filePath ?? this.filePath,
      revision: revision ?? this.revision,
      isDirty: isDirty ?? this.isDirty,
      saveName: saveName ?? this.saveName,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    activeTab,
    navCollapsed,
    windowChromeEnabled,
    statusMessage,
    validationSummary,
    validationHealth,
    filePath,
    revision,
    isDirty,
    saveName,
  ];
}
