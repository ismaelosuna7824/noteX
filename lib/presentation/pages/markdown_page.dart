import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/markdown_project.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/markdown_state.dart';
import '../widgets/editor_text_controls.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/animated_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Preset colors for new markdown projects
// ─────────────────────────────────────────────────────────────────────────────
const _projectColors = [
  Color(0xFF6C5CE7), // Purple
  Color(0xFF0984E3), // Blue
  Color(0xFF00B894), // Teal
  Color(0xFFE17055), // Coral
  Color(0xFFF5A623), // Amber
  Color(0xFFE84393), // Pink
  Color(0xFF2D3436), // Dark
  Color(0xFF00CEC9), // Cyan
  Color(0xFFD63031), // Red
  Color(0xFF6AB04C), // Green
];

// ─────────────────────────────────────────────────────────────────────────────
// Markdown Page
// ─────────────────────────────────────────────────────────────────────────────

class MarkdownPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const MarkdownPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<MarkdownPage> createState() => _MarkdownPageState();
}

class _MarkdownPageState extends State<MarkdownPage> {
  late final MarkdownState _mdState;
  TextEditingController? _titleController;
  TextEditingController? _contentController;
  String? _loadedFileId;

  @override
  void initState() {
    super.initState();
    _mdState = GetIt.instance<MarkdownState>();
    _mdState.initialize();
    _mdState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _forceSave();
    _mdState.autoSaveService.unwatch();
    _mdState.removeListener(_onStateChanged);
    _titleController?.dispose();
    _contentController?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _loadFile() {
    final file = _mdState.currentFile;
    if (file == null || file.id == _loadedFileId) return;

    _forceSave();
    _loadedFileId = file.id;

    _titleController?.dispose();
    _titleController = TextEditingController(text: file.title);

    _contentController?.dispose();
    _contentController = TextEditingController(text: file.content);

    // Register lazy getters once — the periodic timer reads them every 3 s.
    _mdState.autoSaveService.watch(
      fileId: file.id,
      getTitle: () => _titleController?.text ?? '',
      getContent: () => _contentController!.text,
    );
  }

  void _forceSave() {
    final fileId = _loadedFileId;
    if (fileId == null || _contentController == null) return;

    _mdState.autoSaveService.forceSave(
      fileId: fileId,
      title: _titleController?.text ?? '',
      content: _contentController!.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.themeState.accentColor;
    final isDark = theme.brightness == Brightness.dark;

    // Reload editor if file changed
    if (_mdState.currentFile?.id != _loadedFileId) {
      _loadFile();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // Left: file list panel
          SizedBox(
            width: 320,
            child: GlassmorphicContainer(
              borderRadius: 20,
              opacity: isDark ? 0.90 : 0.92,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildListHeader(theme, accentColor, isDark),
                  const SizedBox(height: 8),
                  _buildProjectFilter(theme, accentColor, isDark),
                  const SizedBox(height: 8),
                  _buildSearchBar(accentColor, isDark),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildFileList(theme, accentColor, isDark),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Right: editor / preview
          Expanded(
            child: _buildEditorPanel(context, theme, accentColor, isDark),
          ),
        ],
      ),
    );
  }

  // ── List Header ─────────────────────────────────────────────────────────

  Widget _buildListHeader(ThemeData theme, Color accentColor, bool isDark) {
    return Row(
      children: [
        Text(
          'Markdown',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        // New project button
        _IconBtn(
          icon: Icons.create_new_folder_rounded,
          tooltip: 'New project',
          accentColor: accentColor,
          onTap: () => _showCreateProjectDialog(accentColor),
        ),
        const SizedBox(width: 6),
        // New file button
        InkWell(
          onTap: () async {
            // Create in current filter project or root
            final projectId = _mdState.selectedProjectId == '__root__'
                ? null
                : _mdState.selectedProjectId;
            await _mdState.createFile(projectId: projectId);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 16),
          ),
        ),
      ],
    );
  }

  // ── Project Filter ──────────────────────────────────────────────────────

  Widget _buildProjectFilter(ThemeData theme, Color accentColor, bool isDark) {
    final selected = _mdState.selectedProjectId;

    return SizedBox(
      height: 30,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _FilterChip(
              label: 'All',
              isSelected: selected == null,
              accentColor: accentColor,
              isDark: isDark,
              onTap: () => _mdState.filterByProject(null),
            ),
            const SizedBox(width: 6),
            _FilterChip(
              label: 'Root',
              isSelected: selected == '__root__',
              accentColor: accentColor,
              isDark: isDark,
              onTap: () => _mdState.filterByProject('__root__'),
            ),
            for (final project in _mdState.projects) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onSecondaryTapUp: (details) =>
                    _showProjectContextMenu(details.globalPosition, project),
                child: _FilterChip(
                  label: project.name,
                  isSelected: selected == project.id,
                  accentColor: accentColor,
                  isDark: isDark,
                  color: project.color,
                  onTap: () => _mdState.filterByProject(project.id),
                  onLongPress: () => _showDeleteProjectDialog(project),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Search Bar ────────────────────────────────────────────────────────

  Widget _buildSearchBar(Color accentColor, bool isDark) {
    return SizedBox(
      height: 34,
      child: TextField(
        onChanged: (q) => _mdState.search(q),
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 0,
          ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade100,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: accentColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  // ── File List ───────────────────────────────────────────────────────────

  Widget _buildFileList(ThemeData theme, Color accentColor, bool isDark) {
    final files = _mdState.filteredFiles;

    if (files.isEmpty) {
      final hasSearch = _mdState.searchQuery.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.article_outlined,
              size: 40,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch ? 'No files found' : 'No markdown files',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade400,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = file.id == _mdState.currentFile?.id;
        final project = _mdState.projectForId(file.projectId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () {
              _mdState.selectFile(file);
              _loadFile();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: isDark ? 0.25 : 0.1)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: accentColor.withValues(alpha: 0.4), width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description_rounded,
                    size: 18,
                    color: isSelected
                        ? accentColor
                        : (isDark ? Colors.white54 : Colors.grey.shade500),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                            color: isSelected
                                ? accentColor
                                : (isDark ? Colors.white : Colors.grey.shade800),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (project != null) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: project.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                project.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '${file.updatedAt.month}/${file.updatedAt.day}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Delete button
                  InkWell(
                    onTap: () => _mdState.deleteFile(file.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: isDark ? Colors.white30 : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Editor / Preview Panel ──────────────────────────────────────────────

  Widget _buildEditorPanel(
      BuildContext context, ThemeData theme, Color accentColor, bool isDark) {
    final file = _mdState.currentFile;

    if (file == null || _contentController == null) {
      return GlassmorphicContainer(
        borderRadius: 20,
        opacity: isDark ? 0.90 : 0.92,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_rounded,
                  size: 56, color: isDark ? Colors.white30 : Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Select a file to edit',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade400,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isPreview = _mdState.isPreviewMode;

    return GlassmorphicContainer(
      borderRadius: 20,
      opacity: isDark ? 0.90 : 0.95,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header: title + toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              children: [
                // Editable title
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) => _mdState.autoSaveService.markDirty(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    decoration: InputDecoration(
                      hintText: 'File title...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12,
                          color:
                              isDark ? Colors.white54 : Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${file.updatedAt.month}/${file.updatedAt.day}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              isDark ? Colors.white54 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                EditorTextControls(
                    themeState: widget.themeState, isMarkdown: true),
                const SizedBox(width: 6),
                // Editor / Preview toggle
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleBtn(
                        icon: Icons.edit_rounded,
                        label: 'Edit',
                        isSelected: !isPreview,
                        accentColor: accentColor,
                        isDark: isDark,
                        onTap: () => _mdState.setPreviewMode(false),
                      ),
                      _buildToggleBtn(
                        icon: Icons.visibility_rounded,
                        label: 'Preview',
                        isSelected: isPreview,
                        accentColor: accentColor,
                        isDark: isDark,
                        onTap: () {
                          // Force save before preview so it shows latest content
                          _forceSave();
                          _mdState.setPreviewMode(true);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(color: theme.dividerColor.withValues(alpha: 0.1), height: 1),

          // Body: Editor or Preview
          Expanded(
            child: isPreview ? _buildPreview(isDark) : _buildEditor(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? accentColor
                  : (isDark ? Colors.white54 : Colors.grey.shade400),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white54 : Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _contentController,
        onChanged: (_) => _mdState.autoSaveService.markDirty(),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: isDark ? Colors.white : Colors.black,
        cursorHeight: widget.themeState.markdownFontSize,
        style: GoogleFonts.sourceCodePro(
          fontSize: widget.themeState.markdownFontSize,
          height: widget.themeState.markdownLineHeight,
          color: isDark ? Colors.white : Colors.grey.shade800,
        ),
        decoration: InputDecoration(
          hintText: 'Write your markdown here...',
          border: InputBorder.none,
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    final content = _contentController?.text ?? '';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: content.isEmpty
          ? Center(
              child: Text(
                'Nothing to preview',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
            )
          : Builder(builder: (context) {
              final baseFontSize = widget.themeState.markdownFontSize;
              final lineHeight = widget.themeState.markdownLineHeight;
              final scale = baseFontSize / 14.0;
              return Markdown(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontSize: baseFontSize,
                  height: lineHeight,
                  color: isDark ? Colors.white : Colors.grey.shade800,
                ),
                h1: TextStyle(
                  fontSize: (28 * scale).roundToDouble(),
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                ),
                h2: TextStyle(
                  fontSize: (22 * scale).roundToDouble(),
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                ),
                h3: TextStyle(
                  fontSize: (18 * scale).roundToDouble(),
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                ),
                code: GoogleFonts.sourceCodePro(
                  fontSize: (13 * scale).roundToDouble(),
                  color: isDark ? Colors.greenAccent.shade200 : Colors.pink.shade700,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                ),
                codeblockDecoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isDark ? Colors.white30 : Colors.grey.shade300,
                      width: 3,
                    ),
                  ),
                ),
              ),
            );
            }),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────

  void _showCreateProjectDialog(Color accentColor) {
    final nameController = TextEditingController();
    int selectedColor = _projectColors[0].toARGB32();

    showAnimatedDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('New Markdown Project'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Project name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _projectColors.map((c) {
                    final isSelected = c.toARGB32() == selectedColor;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedColor = c.toARGB32()),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  )
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  await _mdState.createProject(
                    name: name,
                    colorValue: selectedColor,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                ),
                child: const Text('Create'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showProjectContextMenu(
      Offset position, MarkdownProject project) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete project',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (result == 'delete') {
      _showDeleteProjectDialog(project);
    }
  }

  void _showDeleteProjectDialog(MarkdownProject project) {
    final fileCount =
        _mdState.files.where((f) => f.projectId == project.id).length;

    showAnimatedDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Delete "${project.name}"?'),
          content: Text(
            'This will permanently delete the project and all $fileCount file${fileCount == 1 ? '' : 's'} inside it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _mdState.deleteProject(project.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color accentColor;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accentColor, size: 16),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
    this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: isDark ? 0.3 : 0.12)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: accentColor.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white54 : Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
