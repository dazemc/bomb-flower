/// Development-only frame-time probe for the tab shell.
///
/// Replicates `lib/main.dart`'s production wiring, opens the save root named by
/// `--dart-define=PERF_SAVE_ROOT=<path>`, then drives the real widget tree
/// through every [ShellTab] twice and a 60-event wheel scroll over Inventory,
/// logging one machine-readable line per frame.
///
/// Run it in profile mode; debug timings are meaningless.
///
/// ```sh
/// xvfb-run -a --server-args='-screen 0 1400x900x24' \
///   flutter run --profile -d linux -t tool/perf_probe.dart \
///   --dart-define=PERF_SAVE_ROOT=$PWD/.tmp/perf/profile
/// ```
///
/// Output lines:
///
/// - `PERFOPEN` — save-root open cost and slot count.
/// - `PERFBENCH` — wall-clock cost of the [SaveTabSource] getters.
/// - `PERFVISIT` — selectTab() to the end of the first frame that built it.
/// - `PERFFRAME` — one line per delivered frame after the phase is known:
///   `PERFFRAME phase=<label> tab=<tab> build_us=<n> raster_us=<n>`.
/// - `PERFSCROLL` — wheel-scroll notifications observed.
/// - `PERFSUMMARY` — p50/p90/max per phase and the scroll verdict.
library;

import 'dart:async';
import 'dart:io' show exit, stderr, stdout;
import 'dart:math' as math;

import 'dart:ui' show FramePhase;

import 'package:flutter/gestures.dart'
    show GestureBinding, HitTestResult, PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bomb_flower/data/adapter/progress_field_value_codec.dart';
import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/domain/core/layout.dart';
import 'package:bomb_flower/domain/core/validation.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/fields/field_groups.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_scope.dart';
import 'package:bomb_flower/presentation/tabs_support/save_tab_source.dart';
import 'package:bomb_flower/presentation/tabs_support/session_save_tab_source.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';

const String _saveRoot = String.fromEnvironment(
  'PERF_SAVE_ROOT',
  defaultValue: '.tmp/perf/profile',
);

/// How long each tab visit is given, in milliseconds.
const int _visitSettleMs = 1200;

/// Frames the wheel is turned for.
const int _scrollFrames = 60;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final binding = SchedulerBinding.instance;
  binding.addTimingsCallback(_Probe.instance.recordTimings);

  final schema = await GameDataSchema.load(
    () => rootBundle.loadString('assets/schema/gamedata_110.json'),
  );
  final engine = const SaveEngine(
    SaveFormat(
      'oot-remake',
      'Ocarina of Time (Switch 2 remake)',
      <LayoutDescriptor>[],
    ),
    valueCodec: ProgressFieldValueCodec(),
  );
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  final repository = FileSaveRepository(
    engine: engine,
    resolveLayout: resolver.call,
  );
  final session = SaveSessionCubit(
    engine: engine,
    repository: repository,
    resolveLayout: resolver.call,
  );

  final openWatch = Stopwatch()..start();
  await session.openPath(_saveRoot);
  openWatch.stop();
  final project = _uiProject(session.state);
  stdout.writeln(
    'PERFOPEN root=$_saveRoot ok=${project != null} '
    'ms=${openWatch.elapsedMilliseconds} '
    'slots=${project?.slots.length ?? 0}',
  );
  if (project == null) {
    stderr.writeln('PERFERROR the save root did not open');
    exit(2);
  }

  final changes = _SessionChanges(session.stream);
  final source = _createSource(session, changes);

  _benchSource(source);

  final shell = ShellCubit(windowChromeEnabled: false);
  final probe = _Probe.instance..attach(shell: shell);
  runApp(
    _ProbeApp(session: session, shell: shell, source: source, changes: changes),
  );
  unawaited(probe.run());

  // The probe exits the process itself once the scripted sequence finishes.
  await Completer<void>().future;
}

/// Mirrors `_BombFlowerAppState._createSource`.
SessionSaveTabSource _createSource(
  SaveSessionCubit session,
  _SessionChanges changes,
) {
  return SessionSaveTabSource(
    project: () => session.openProject,
    edit: session.edit,
    undo: session.undo,
    redo: session.redo,
    issues: () =>
        _uiProject(session.state)?.issues ?? const <ValidationIssue>[],
    activeSlot: () => _uiProject(session.state)?.activeSlot,
    slotAges: () => const <SlotAge>[],
    changes: changes,
    canUndo: () => _uiProject(session.state)?.canUndo ?? false,
    canRedo: () => _uiProject(session.state)?.canRedo ?? false,
  );
}

SaveProjectUi? _uiProject(SaveSessionUiState state) => switch (state) {
  SaveSessionReady(:final project) => project,
  SaveSessionSaving(:final project) => project,
  SaveSessionPendingDiscard(:final project) => project,
  SaveSessionSaved(:final project) => project,
  SaveSessionError(:final project) => project,
  SaveSessionOpening() || SaveSessionClosed() => null,
};

/// Wall-clock cost of the source getters the tabs hit on every build.
///
/// Profile mode is AOT, so there is no JIT warm-up to confuse the figures; the
/// only warming that can happen is inside the source itself, so each getter is
/// timed twice and both numbers are printed.
void _benchSource(SaveTabSource source) {
  void bench(String name, void Function() body) {
    final cold = Stopwatch()..start();
    body();
    cold.stop();
    final warm = Stopwatch()..start();
    body();
    warm.stop();
    stdout.writeln(
      'PERFBENCH $name cold_us=${cold.elapsedMicroseconds} '
      'warm_us=${warm.elapsedMicroseconds}',
    );
  }

  // Force a fresh read: every call may return a lazy iterable.
  bench('allViews_materialize', () => source.allViews.length);
  bench('isDirty', () => source.isDirty);
  bench('changedFieldCount', () => source.changedFieldCount);
  bench('viewsFor_inventory', () {
    source.viewsFor(EditorTabGroup.inventory).length;
  });
  bench('viewsFor_overview', () {
    source.viewsFor(EditorTabGroup.overview).length;
  });
}

/// Bridges the session stream to a [Listenable], exactly as the app does.
final class _SessionChanges extends ChangeNotifier {
  _SessionChanges(Stream<SaveSessionUiState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<SaveSessionUiState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// The probe's widget tree: production wiring, no window chrome, no test fakes.
class _ProbeApp extends StatelessWidget {
  const _ProbeApp({
    required this.session,
    required this.shell,
    required this.source,
    required this.changes,
  });

  final SaveSessionCubit session;
  final ShellCubit shell;
  final SessionSaveTabSource source;
  final _SessionChanges changes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bomb Flower perf probe',
      debugShowCheckedModeBanner: false,
      theme: BombFlowerThemeData.build(),
      home: BlocProvider<ShellCubit>.value(
        value: shell,
        child: BlocProvider<SaveSessionCubit>.value(
          value: session,
          child: ListenableBuilder(
            listenable: changes,
            builder: (context, _) {
              final state = session.state;
              final project = _uiProject(state);
              final unverifiedCount =
                  project?.issues
                      .where(
                        (issue) =>
                            issue.code == ValidationCodes.fieldUnverified,
                      )
                      .length ??
                  0;
              return SaveTabScope(
                source: source,
                child: Listener(
                  onPointerSignal: (_) => _Probe.instance.pointerSignals++,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0) {
                        _Probe.instance.scrollNotifications++;
                        _Probe.instance.lastScrollPixels =
                            notification.metrics.pixels;
                      }
                      return false;
                    },
                    child: AppShell(
                      settingsStore: InMemorySettingsStore(),
                      unverifiedFieldCount: unverifiedCount,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Receives frame timings and drives the autopilot.
final class _Probe {
  _Probe._();

  static final _Probe instance = _Probe._();

  final List<_Frame> _frames = <_Frame>[];
  final List<String> _frameLabels = <String>[];
  final List<_PhaseMark> _marks = <_PhaseMark>[];
  final Map<String, List<_Frame>> _byPhase = <String, List<_Frame>>{};

  ShellCubit? _shell;
  int scrollNotifications = 0;
  int pointerSignals = 0;
  double lastScrollPixels = 0;

  void attach({required ShellCubit shell}) {
    _shell = shell;
    _mark('startup');
    // Label each frame as it begins, so attribution never depends on clock
    // skew between `FrameTiming.vsyncStart` and the engine's raw timestamp.
    SchedulerBinding.instance.addPersistentFrameCallback(
      (_) => _frameLabels.add(_marks.isEmpty ? 'startup' : _marks.last.label),
    );
  }

  /// Called by the engine for every completed frame.
  void recordTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames.add(
        _Frame(
          vsyncUs: timing.timestampInMicroseconds(FramePhase.vsyncStart),
          buildUs: timing.buildDuration.inMicroseconds,
          rasterUs: timing.rasterDuration.inMicroseconds,
        ),
      );
    }
  }

  void _mark(String label) {
    _marks.add(
      _PhaseMark(
        atUs: SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds,
        label: label,
      ),
    );
  }

  String _labelFor(int vsyncUs) {
    // `FrameTiming`'s vsync timestamp and `currentSystemFrameTimeStamp` share a
    // clock but differ by a few hundred microseconds on the same frame, so a
    // phase mark is allowed to claim a frame whose vsync is just before it.
    // Phases are at least 600 ms apart, so 5 ms can never cross a boundary.
    const int skewUs = 5000;
    var label = _marks.isEmpty ? 'startup' : _marks.first.label;
    for (final mark in _marks) {
      if (mark.atUs - skewUs <= vsyncUs) {
        label = mark.label;
      } else {
        break;
      }
    }
    return label;
  }

  Future<void> _waitForFirstFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }

  Future<void> run() async {
    await _waitForFirstFrame();
    // Let the first layout settle before the scripted sequence starts.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final tabs = ShellTab.values;
    for (var visit = 1; visit <= 2; visit++) {
      for (final tab in tabs) {
        await _visit(tab, visit);
      }
    }

    // Steady-state wheel scroll over Inventory, after its fade has settled.
    await _visit(ShellTab.inventory, 3, settleMs: 600);
    // The page starts at the top, so a wheel-up event is a deliberate no-op;
    // wheel down first to reach the middle of the page, then measure wheel-up.
    _mark('scroll:warmup');
    await _scroll(30, const Offset(0, 40));
    _mark('scroll:inventory');
    await _scroll(_scrollFrames, const Offset(0, -40));

    _summarise();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  Future<void> _visit(
    ShellTab tab,
    int visit, {
    int settleMs = _visitSettleMs,
  }) async {
    final shell = _shell;
    if (shell == null) return;
    final label = 'tab:${tab.name}:v$visit';
    // The visit label is set before the switch: the frame that builds the new
    // tab is the very next frame, and labels are captured when a frame begins.
    _mark(label);
    final watch = Stopwatch()..start();
    shell.selectTab(tab);
    await SchedulerBinding.instance.endOfFrame;
    watch.stop();
    stdout.writeln(
      'PERFVISIT tab=${tab.name} visit=$visit '
      'first_frame_ms=${watch.elapsedMilliseconds}',
    );
    await Future<void>.delayed(Duration(milliseconds: settleMs));
  }

  Future<void> _scroll(int frames, Offset delta) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final position = Offset(size.width / 2, size.height / 2);
    final hit = HitTestResult();
    GestureBinding.instance.hitTestInView(hit, position, view.viewId);
    stdout.writeln(
      'PERFSCROLLINFO size=${size.width}x${size.height} '
      'viewId=${view.viewId} hit_path=${hit.path.length} '
      'centre=${position.dx},${position.dy} frames=$frames '
      'delta=${delta.dx},${delta.dy}',
    );
    var sent = 0;
    final done = Completer<void>();

    void step(Duration _) {
      if (sent >= frames) {
        if (!done.isCompleted) done.complete();
        return;
      }
      sent++;
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          viewId: view.viewId,
          position: position,
          scrollDelta: delta,
          kind: PointerDeviceKind.mouse,
          device: 910,
        ),
      );
      SchedulerBinding.instance.addPostFrameCallback(step);
      SchedulerBinding.instance.scheduleFrame();
    }

    SchedulerBinding.instance.addPostFrameCallback(step);
    SchedulerBinding.instance.scheduleFrame();
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  void _summarise() {
    final aligned = _frames.length == _frameLabels.length;
    stdout.writeln(
      'PERFFRAMEALIGN frames=${_frames.length} labels=${_frameLabels.length} '
      'aligned=$aligned',
    );
    for (var i = 0; i < _frames.length; i++) {
      final frame = _frames[i];
      final label = aligned ? _frameLabels[i] : _labelFor(frame.vsyncUs);
      _byPhase.putIfAbsent(label, () => <_Frame>[]).add(frame);
      stdout.writeln(
        'PERFFRAME phase=$label build_us=${frame.buildUs} '
        'raster_us=${frame.rasterUs}',
      );
    }

    final shell = _shell;
    final tab = shell?.state.activeTab.name ?? '?';
    stdout.writeln(
      'PERFSCROLL notifications=$scrollNotifications '
      'pointer_signals=$pointerSignals last_pixels=${lastScrollPixels.toStringAsFixed(1)} '
      'frames=${_byPhase['scroll:inventory']?.length ?? 0} active_tab=$tab',
    );

    final keys = _byPhase.keys.toList(growable: false);
    for (final key in keys) {
      final frames = _byPhase[key]!;
      final builds = frames.map((f) => f.buildUs).toList()..sort();
      final rasters = frames.map((f) => f.rasterUs).toList()..sort();
      final worst = frames.reduce(
        (a, b) => a.buildUs + a.rasterUs >= b.buildUs + b.rasterUs ? a : b,
      );
      final janky = frames.where((f) => f.buildUs + f.rasterUs > 16700).length;
      stdout.writeln(
        'PERFSUMMARY phase=$key frames=${frames.length} '
        'build_p50_us=${_percentile(builds, 50)} '
        'build_p90_us=${_percentile(builds, 90)} '
        'build_max_us=${builds.isEmpty ? 0 : builds.last} '
        'raster_p50_us=${_percentile(rasters, 50)} '
        'raster_p90_us=${_percentile(rasters, 90)} '
        'raster_max_us=${rasters.isEmpty ? 0 : rasters.last} '
        'worst_build_us=${worst.buildUs} worst_raster_us=${worst.rasterUs} '
        'janky=$janky',
      );
    }
  }

  int _percentile(List<int> sorted, int percent) {
    if (sorted.isEmpty) return 0;
    final index = ((sorted.length - 1) * percent / 100).round();
    return sorted[math.min(index, sorted.length - 1)];
  }
}

final class _Frame {
  const _Frame({
    required this.vsyncUs,
    required this.buildUs,
    required this.rasterUs,
  });

  final int vsyncUs;
  final int buildUs;
  final int rasterUs;
}

final class _PhaseMark {
  const _PhaseMark({required this.atUs, required this.label});

  final int atUs;
  final String label;
}
