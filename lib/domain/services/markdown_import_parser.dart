/// A note recovered from a Markdown file, before it is given an identity.
class ImportedNote {
  /// Title for the new note.
  final String title;

  /// Markdown body, front matter stripped.
  final String content;

  /// Creation date recovered from front matter, or null when the file did not
  /// carry one. Callers decide what to use instead.
  final DateTime? createdAt;

  /// Last-modified date recovered from front matter, or null.
  final DateTime? updatedAt;

  /// Folder path the file sat in, outermost first. Empty for a root file.
  final List<String> folders;

  const ImportedNote({
    required this.title,
    required this.content,
    required this.folders,
    this.createdAt,
    this.updatedAt,
  });
}

/// Turns a Markdown file into an [ImportedNote].
///
/// Pure domain logic — no I/O, no Flutter. It reads the front matter this app
/// writes on export, but must also survive files that never came from here:
/// a plain `.md` with no front matter is a perfectly valid import.
class MarkdownImportParser {
  const MarkdownImportParser._();

  /// Extension the importer accepts.
  static const extension = '.md';

  /// A front matter fence: exactly `---` on its own line.
  static final _fence = RegExp(r'^---\s*$');

  /// A `key: value` line inside front matter.
  static final _field = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$');

  /// Parses [raw], using [relativePath] for the folder path and as the title
  /// of last resort.
  ///
  /// Front matter is only honoured when the file opens with a `---` fence and
  /// a closing fence is actually found. A document that merely starts with a
  /// horizontal rule keeps all of its content.
  static ImportedNote parse({
    required String relativePath,
    required String raw,
  }) {
    final segments = relativePath.split('/').where((s) => s.isNotEmpty).toList();
    final fileName = segments.isEmpty ? '' : segments.removeLast();

    final lines = raw.split('\n');
    final frontMatter = _readFrontMatter(lines);

    final body = frontMatter == null
        ? raw
        : lines.skip(frontMatter.endLine + 1).join('\n').trimLeft();

    final title = frontMatter?.fields['title']?.trim() ?? '';

    return ImportedNote(
      title: title.isNotEmpty ? title : _titleFromFileName(fileName),
      content: body,
      folders: segments,
      createdAt: _parseDate(frontMatter?.fields['created']),
      updatedAt: _parseDate(frontMatter?.fields['updated']),
    );
  }

  /// Whether [relativePath] is a file this importer should read at all.
  static bool accepts(String relativePath) =>
      relativePath.toLowerCase().endsWith(extension);

  static _FrontMatter? _readFrontMatter(List<String> lines) {
    if (lines.isEmpty || !_fence.hasMatch(lines.first)) return null;

    for (var i = 1; i < lines.length; i++) {
      if (_fence.hasMatch(lines[i])) {
        final fields = <String, String>{};
        for (final line in lines.getRange(1, i)) {
          final match = _field.firstMatch(line);
          if (match != null) {
            fields[match.group(1)!.toLowerCase()] =
                _unquote(match.group(2)!.trim());
          }
        }
        return _FrontMatter(fields: fields, endLine: i);
      }
    }

    // Opened but never closed — not front matter, just a document that begins
    // with a horizontal rule.
    return null;
  }

  /// Reverses the quoting the exporter applies to string values.
  static String _unquote(String value) {
    if (value.length < 2) return value;
    final quoted = (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"));
    if (!quoted) return value;

    return value
        .substring(1, value.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', r'\');
  }

  static String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.toLowerCase().endsWith(extension)
        ? fileName.substring(0, fileName.length - extension.length)
        : fileName;
    final trimmed = withoutExtension.trim();
    return trimmed.isEmpty ? 'Untitled' : trimmed;
  }

  /// Dates are best-effort: an unparseable value is dropped rather than
  /// failing the import of an otherwise fine note.
  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class _FrontMatter {
  final Map<String, String> fields;

  /// Index of the closing fence.
  final int endLine;

  const _FrontMatter({required this.fields, required this.endLine});
}
