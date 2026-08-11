import '../entities/note.dart';
import '../entities/note_project.dart';

/// One file an export will write.
class ExportEntry {
  /// Path relative to the export root, always `/`-separated. Adapters join it
  /// with the platform separator.
  final String path;

  /// Full file body, front matter included.
  final String content;

  const ExportEntry({required this.path, required this.content});

  @override
  String toString() => 'ExportEntry($path)';
}

/// Decides what files an export produces, and what goes in them.
///
/// Pure domain logic — no I/O, no Flutter, no `dart:io`. Everything that can
/// go wrong in an export is decided here (illegal characters, name clashes,
/// folder nesting, notes that outlived their project) so it can be tested
/// without ever touching a disk.
class NoteExportPlan {
  const NoteExportPlan._();

  /// Extension every exported note gets.
  static const extension = '.md';

  /// Longest a single path segment may be, before the extension.
  ///
  /// Well under the 255-byte limit common to APFS, ext4 and NTFS, leaving room
  /// for the extension and a collision suffix.
  static const maxSegmentLength = 80;

  /// Name used when a title sanitises down to nothing.
  static const fallbackName = 'Untitled';

  /// Characters no mainstream filesystem accepts in a name. `/` and `\` are
  /// included so a title can never smuggle in a directory level.
  static final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  static final _whitespace = RegExp(r'\s+');

  /// Trailing dots and spaces are legal to create on POSIX but silently
  /// rewritten by Windows, which turns a clean export into a corrupt one.
  static final _trailingJunk = RegExp(r'[. ]+$');

  /// What a sanitised name looks like when nothing meaningful survived.
  static final _placeholderOnly = RegExp(r'[-\s]');

  /// Device names Windows still reserves, with or without an extension.
  static const _windowsReserved = {
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// Builds the complete set of files for [notes], foldered by [projects].
  ///
  /// [toMarkdown] normalises a stored body to Markdown. It is injected rather
  /// than imported so this stays free of infrastructure: some notes predate the
  /// v1.50 migration and still hold Quill Delta JSON, which would otherwise be
  /// exported as unreadable JSON.
  ///
  /// Trashed notes are skipped — an export is what the user can see, not what
  /// the database happens to still hold. Output is deterministic: notes are
  /// ordered by creation date so the same library always exports identically,
  /// which also makes collision suffixes stable between runs.
  static List<ExportEntry> build({
    required List<Note> notes,
    required List<NoteProject> projects,
    required String Function(String) toMarkdown,
  }) {
    final projectsById = {for (final p in projects) p.id: p};

    final live = notes.where((n) => n.deletedAt == null).toList()
      ..sort((a, b) {
        final byDate = a.createdAt.compareTo(b.createdAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    // Compared case-insensitively: macOS and Windows treat `Notes.md` and
    // `notes.md` as the same file, so a case-sensitive check would let one
    // note silently overwrite another.
    final taken = <String>{};
    final entries = <ExportEntry>[];

    for (final note in live) {
      final folder = _folderFor(note.projectId, projectsById);
      final path = _claimPath(folder, sanitizeSegment(note.title), taken);
      entries.add(ExportEntry(
        path: path,
        content: _render(
          title: note.title,
          content: note.content,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          toMarkdown: toMarkdown,
        ),
      ));
    }

    return entries;
  }

  /// Renders one document as a standalone file, for a single-item export.
  ///
  /// Takes the fields rather than an entity so notes and Markdown files share
  /// one renderer. Two of them would drift, and the day they did, the same
  /// content would export differently depending on which library it lived in.
  ///
  /// [fileName] is the name the user picked in a save dialog, already vetted
  /// by the OS — it is used verbatim apart from ensuring the extension. When
  /// omitted the name is derived from the title, which is what a save dialog
  /// should be pre-filled with.
  static ExportEntry single({
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String Function(String) toMarkdown,
    String? fileName,
  }) {
    final name = fileName == null || fileName.trim().isEmpty
        ? suggestedFileName(title)
        : _withExtension(fileName.trim());

    return ExportEntry(
      path: name,
      content: _render(
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
        toMarkdown: toMarkdown,
      ),
    );
  }

  /// File name to pre-fill a save dialog with for a note called [title].
  static String suggestedFileName(String title) =>
      '${sanitizeSegment(title)}$extension';

  static String _withExtension(String name) =>
      name.toLowerCase().endsWith(extension) ? name : '$name$extension';

  /// Folder path for a note in [projectId], or `''` for the export root.
  ///
  /// Walks up the parent chain so nested folders survive the round trip. A
  /// project that is missing or trashed drops its notes at the root rather
  /// than inventing a folder for something the user cannot see. A corrupted
  /// parent cycle is broken rather than hung on.
  static String _folderFor(
    String? projectId,
    Map<String, NoteProject> projectsById,
  ) {
    final segments = <String>[];
    final seen = <String>{};

    var currentId = projectId;
    while (currentId != null && seen.add(currentId)) {
      final project = projectsById[currentId];
      if (project == null || project.deletedAt != null) break;
      segments.insert(0, sanitizeSegment(project.name));
      currentId = project.parentId;
    }

    return segments.join('/');
  }

  /// Reserves a unique path, disambiguating clashes as `name (2).md`.
  static String _claimPath(String folder, String name, Set<String> taken) {
    final prefix = folder.isEmpty ? '' : '$folder/';

    var candidate = '$prefix$name$extension';
    var counter = 2;
    while (!taken.add(candidate.toLowerCase())) {
      candidate = '$prefix$name ($counter)$extension';
      counter++;
    }
    return candidate;
  }

  /// Makes [raw] safe to use as a single file or folder name.
  ///
  /// Exposed for tests — every rule here corresponds to a way an export can
  /// fail on a real filesystem.
  static String sanitizeSegment(String raw) {
    var name = raw
        .replaceAll(_illegal, '-')
        .replaceAll(_whitespace, ' ')
        .trim();

    if (name.length > maxSegmentLength) {
      name = name.substring(0, maxSegmentLength).trim();
    }

    // Applied after truncation, which can expose a new trailing dot.
    name = name.replaceAll(_trailingJunk, '');

    // A title made only of characters we replaced carries no information and
    // reads as corruption ('///' would otherwise become '---.md').
    if (name.replaceAll(_placeholderOnly, '').isEmpty) return fallbackName;
    if (_windowsReserved.contains(name.toLowerCase())) return '_$name';
    return name;
  }

  /// Renders a document's file body.
  ///
  /// YAML front matter carries the fields the filesystem cannot. The title
  /// especially: sanitising strips characters a real title may depend on, so
  /// without this the true title would only survive in mangled form.
  static String _render({
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String Function(String) toMarkdown,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${_yamlString(title)}')
      ..writeln('created: ${createdAt.toIso8601String()}')
      ..writeln('updated: ${updatedAt.toIso8601String()}')
      ..writeln('---')
      ..writeln();

    buffer.write(toMarkdown(content));
    return buffer.toString();
  }

  /// Quotes a value so any title is valid YAML, including empty ones and
  /// titles containing colons, quotes or `#`.
  static String _yamlString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
