import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One reversible action.
class UndoEntry {
  const UndoEntry(this.label, this.undo);

  final String label;
  final Future<void> Function() undo;
}

/// Cmd+Z stack — the last 20 reversible actions (read/star toggles,
/// moves, deletions-to-trash).
class UndoStackNotifier extends Notifier<List<UndoEntry>> {
  @override
  List<UndoEntry> build() => const [];

  void push(String label, Future<void> Function() undo) {
    state = [
      ...state.length >= 20 ? state.sublist(state.length - 19) : state,
      UndoEntry(label, undo),
    ];
  }

  /// Undoes the most recent action; returns its label, or null when the
  /// stack is empty.
  Future<String?> undoLast() async {
    if (state.isEmpty) return null;
    final entry = state.last;
    state = state.sublist(0, state.length - 1);
    await entry.undo();
    return entry.label;
  }
}

final undoProvider = NotifierProvider<UndoStackNotifier, List<UndoEntry>>(
  UndoStackNotifier.new,
);
