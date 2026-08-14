import '../state/timer_state.dart';

/// Starts the timer if none is running, stops it if one is — the
/// Cmd/Ctrl+Shift+T shortcut's toggle semantics (see `AppShortcuts` /
/// `AppShell`). Goes through [TimerState] only, never a direct repository
/// write, so the running-entry state stays consistent with the rest of the
/// app (timer bar, task transitions, week totals).
Future<void> toggleRunningTimer(TimerState timerState) {
  return timerState.isRunning
      ? timerState.stopTimer()
      : timerState.startTimer();
}
