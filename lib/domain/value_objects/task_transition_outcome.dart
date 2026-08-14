/// Outcome of the task-status transition attempted as a side effect of
/// starting a timer linked to a task (design D1).
enum TaskTransitionOutcome {
  /// The timer has no linked task — no transition was attempted.
  notApplicable,

  /// The linked task was found and successfully transitioned to `doing`.
  applied,

  /// A transition was attempted and did not succeed (the task could not be
  /// found, or the write threw). The timer itself is unaffected — see
  /// [StartTimerUseCase] and design D1: a task write must never block,
  /// delay or roll back a timer write, and this outcome exists so the
  /// failure is surfaced rather than silently swallowed.
  failed,
}
