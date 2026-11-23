/// Bounded, snapshot-based undo/redo with coalescing and transactions.
library;

import 'edit_command.dart';
import 'field_metadata.dart';
import 'identity.dart';
import 'save_snapshot.dart';

/// One undoable group of commands and the snapshots on either side.
final class HistoryEntry {
  /// Creates an entry; [commands] is copied to an unmodifiable list.
  HistoryEntry(this.label, List<EditCommand> commands, this.before, this.after)
    : commands = List<EditCommand>.unmodifiable(commands);

  /// Human-readable group label.
  final String label;

  /// Commands in this group, in application order.
  final List<EditCommand> commands;

  /// State before the group.
  final SaveSnapshot before;

  /// State after the group.
  final SaveSnapshot after;

  /// The single command when this is a simple edit, otherwise `null`.
  EditCommand? get command => commands.length == 1 ? commands.single : null;

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.label == label &&
      _commandsEqual(other.commands, commands) &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode =>
      Object.hash(label, Object.hashAll(commands), before, after);

  @override
  String toString() => 'HistoryEntry("$label", ${commands.length} command(s))';
}

/// A bounded stack of history entries.
final class HistoryStack {
  /// Creates a stack retaining at most [maxDepth] entries.
  HistoryStack({this.maxDepth = 100}) {
    if (maxDepth < 1) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'must be positive');
    }
  }

  /// Maximum retained entries.
  final int maxDepth;

  final List<HistoryEntry> _entries = <HistoryEntry>[];

  /// Whether an entry can be popped.
  bool get canPop => _entries.isNotEmpty;

  /// Number of entries.
  int get length => _entries.length;

  /// Entries from oldest to newest.
  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_entries);

  /// Pushes [entry], evicting the oldest when full.
  void push(HistoryEntry entry) {
    _entries.add(entry);
    while (_entries.length > maxDepth) {
      _entries.removeAt(0);
    }
  }

  /// Removes and returns the newest entry.
  HistoryEntry? pop() => _entries.isEmpty ? null : _entries.removeLast();

  /// Removes every entry.
  void clear() => _entries.clear();

  @override
  String toString() => 'HistoryStack(${_entries.length}/$maxDepth)';
}

/// The undo stack type.
typedef UndoStack = HistoryStack;

/// The redo stack type.
typedef RedoStack = HistoryStack;

/// Bounded interactive history.
///
/// * [maxDepth] entries per stack, oldest evicted.
/// * Rapid edits to the same field and command type inside [coalesceWindow]
///   collapse into one entry unless sealed or inside a transaction.
/// * Redo is cleared by every committed new edit.
/// * One transaction is one undo entry.
/// * [clock] is injectable so coalescing tests are deterministic.
final class EditHistory {
  /// Creates history with a 100-entry depth and a 400 ms coalesce window.
  EditHistory({
    int maxDepth = 100,
    this.coalesceWindow = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : undoStack = UndoStack(maxDepth: maxDepth),
       redoStack = RedoStack(maxDepth: maxDepth),
       _clock = clock ?? DateTime.now {
    if (coalesceWindow.isNegative) {
      throw ArgumentError.value(
        coalesceWindow,
        'coalesceWindow',
        'must not be negative',
      );
    }
  }

  /// The undo stack.
  final UndoStack undoStack;

  /// The redo stack.
  final RedoStack redoStack;

  /// Window in which same-field edits may collapse.
  final Duration coalesceWindow;

  final DateTime Function() _clock;

  _Transaction? _transaction;
  _CoalesceKey? _lastKey;
  DateTime? _lastRecordAt;
  bool _sealPending = false;

  /// Whether an undo entry is available.
  bool get canUndo => undoStack.canPop;

  /// Whether a redo entry is available.
  bool get canRedo => redoStack.canPop;

  /// Whether a transaction is open.
  bool get inTransaction => _transaction != null;

  /// The snapshot captured at the start of the open transaction, if any.
  ///
  /// A caller that rolls back can install this snapshot to restore bytes.
  SaveSnapshot? get transactionBefore => _transaction?.before;

  /// Committed entries, oldest first.
  List<HistoryEntry> get changelist => undoStack.entries;

  /// A newest-first, one-line-per-entry summary of committed changes.
  String get changelistSummary => changelist.reversed
      .map((entry) => '${entry.label} (${entry.commands.length} edit(s))')
      .join('\n');

  /// Opens a transaction group labelled [label].
  ///
  /// Nested transactions throw [StateError].
  void beginTransaction(String label) {
    if (_transaction != null) {
      throw StateError('A transaction is already open');
    }
    _transaction = _Transaction(label);
  }

  /// Closes the open transaction and pushes one history entry.
  ///
  /// Throws [StateError] when no transaction is open.
  void commitTransaction() {
    final transaction = _transaction;
    if (transaction == null) {
      throw StateError('No transaction is open');
    }
    if (transaction.before != null && transaction.after != null) {
      undoStack.push(
        HistoryEntry(
          transaction.label,
          transaction.commands,
          transaction.before!,
          transaction.after!,
        ),
      );
      redoStack.clear();
    }
    _transaction = null;
    _resetCoalescing();
  }

  /// Discards the open transaction.
  ///
  /// Returns the pre-transaction snapshot when the group had at least one
  /// record, otherwise `null`. The caller installs that snapshot to restore
  /// bytes; this class never owns current project state.
  SaveSnapshot? rollbackTransaction() {
    final transaction = _transaction;
    if (transaction == null) {
      throw StateError('No transaction is open');
    }
    _transaction = null;
    _resetCoalescing();
    return transaction.before;
  }

  /// Records one committed edit.
  ///
  /// [before] and [after] are snapshot handles. Coalescing is considered only
  /// when [coalesce] is true, no transaction is open, no [seal] is pending,
  /// the top entry has the same field and command type (and, for `SetBytes`,
  /// the same target span), and the clock is inside [coalesceWindow].
  void record(
    EditCommand command,
    SaveSnapshot before,
    SaveSnapshot after, {
    bool coalesce = true,
  }) {
    final now = _clock();
    final transaction = _transaction;
    if (transaction != null) {
      transaction.add(command, before, after);
      return;
    }

    final key = _CoalesceKey.of(command);
    final lastAt = _lastRecordAt;
    final withinWindow =
        lastAt != null &&
        !now.isBefore(lastAt) &&
        now.difference(lastAt) <= coalesceWindow;
    final mayCoalesce =
        coalesce &&
        !_sealPending &&
        withinWindow &&
        _lastKey == key &&
        undoStack.canPop;

    if (mayCoalesce) {
      final top = undoStack.pop()!;
      undoStack.push(
        HistoryEntry(
          top.label,
          <EditCommand>[...top.commands, command],
          top.before,
          after,
        ),
      );
    } else {
      undoStack.push(
        HistoryEntry(
          command.description,
          <EditCommand>[command],
          before,
          after,
        ),
      );
    }

    redoStack.clear();
    _lastKey = key;
    _lastRecordAt = now;
    _sealPending = false;
  }

  /// Records a synthetic entry that has no [EditCommand], such as a reset.
  void recordSynthetic(String label, SaveSnapshot before, SaveSnapshot after) {
    if (_transaction != null) {
      throw StateError('Cannot record a synthetic entry during a transaction');
    }
    undoStack.push(HistoryEntry(label, const <EditCommand>[], before, after));
    redoStack.clear();
    _resetCoalescing();
  }

  /// Stops the next edit from coalescing with the previous one.
  ///
  /// The UI calls this on field blur, selection change, or tab change. A new
  /// coalescing group may start with the following edit.
  void seal() {
    _sealPending = true;
    _lastKey = null;
    _lastRecordAt = null;
  }

  /// Undoes the newest entry and returns it, or `null` when empty.
  ///
  /// Throws [StateError] while a transaction is open.
  HistoryEntry? undo() {
    if (_transaction != null) {
      throw StateError('Cannot undo during a transaction');
    }
    final entry = undoStack.pop();
    if (entry == null) {
      return null;
    }
    redoStack.push(entry);
    _resetCoalescing();
    return entry;
  }

  /// Redoes the newest undone entry and returns it, or `null` when empty.
  ///
  /// Throws [StateError] while a transaction is open.
  HistoryEntry? redo() {
    if (_transaction != null) {
      throw StateError('Cannot redo during a transaction');
    }
    final entry = redoStack.pop();
    if (entry == null) {
      return null;
    }
    undoStack.push(entry);
    _resetCoalescing();
    return entry;
  }

  /// Empties both stacks without changing bytes.
  ///
  /// Throws [StateError] while a transaction is open.
  void clear() {
    if (_transaction != null) {
      throw StateError('Cannot clear history during a transaction');
    }
    undoStack.clear();
    redoStack.clear();
    _resetCoalescing();
  }

  void _resetCoalescing() {
    _lastKey = null;
    _lastRecordAt = null;
    _sealPending = false;
  }

  @override
  String toString() =>
      'EditHistory(undo: ${undoStack.length}, redo: ${redoStack.length})';
}

final class _CoalesceKey {
  const _CoalesceKey(this.field, this.type, this.target);

  factory _CoalesceKey.of(EditCommand command) => _CoalesceKey(
    command.field,
    command.runtimeType,
    command is SetBytes ? command.target : null,
  );

  final FieldId field;
  final Type type;
  final ByteSpan? target;

  @override
  bool operator ==(Object other) =>
      other is _CoalesceKey &&
      other.field == field &&
      other.type == type &&
      other.target == target;

  @override
  int get hashCode => Object.hash(field, type, target);
}

final class _Transaction {
  _Transaction(this.label);

  final String label;
  final List<EditCommand> commands = <EditCommand>[];
  SaveSnapshot? before;
  SaveSnapshot? after;

  void add(
    EditCommand command,
    SaveSnapshot entryBefore,
    SaveSnapshot entryAfter,
  ) {
    before ??= entryBefore;
    after = entryAfter;
    commands.add(command);
  }
}

bool _commandsEqual(List<EditCommand> a, List<EditCommand> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
