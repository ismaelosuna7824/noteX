/// A file offered to the importer.
class ImportFile {
  /// Path relative to the import root, always `/`-separated.
  final String relativePath;

  /// Full file text.
  final String content;

  const ImportFile({required this.relativePath, required this.content});
}

/// Port (interface) for reading files to import.
///
/// This is the domain's contract — infrastructure adapters must implement it.
/// The domain never learns what a directory is; it receives relative paths and
/// text, so an import could just as well come from an archive or a sync
/// service without anything above this line changing.
abstract class NoteImportSource {
  /// Every importable file found, in a stable order.
  Future<List<ImportFile>> read();
}
