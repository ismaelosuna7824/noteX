import '../services/note_export_plan.dart';

/// Port (interface) for writing an export somewhere.
///
/// This is the domain's contract — infrastructure adapters must implement it.
/// The domain never learns what a directory is: it hands over entries with
/// `/`-separated relative paths and lets the adapter decide what that means.
abstract class NoteExportSink {
  /// Writes every entry, creating whatever structure their paths imply.
  ///
  /// Implementations must treat [ExportEntry.path] as relative and must not
  /// escape their own root, no matter what a path contains.
  Future<void> write(List<ExportEntry> entries);
}
