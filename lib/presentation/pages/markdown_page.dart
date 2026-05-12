import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/markdown_file.dart';
import '../../domain/entities/markdown_project.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/markdown_state.dart';
import '../utils/platform_utils.dart';
import '../widgets/editor_text_controls.dart';
import '../widgets/folder_tree_widgets.dart';
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

  /// On mobile, tracks whether we show the editor (true) or file list (false).
  bool _mobileShowEditor = false;

  // ── Save indicator & debounce ──────────────────────────────────────
  final ValueNotifier<String> _saveStatus = ValueNotifier('');
  Timer? _debounce;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _mdState = GetIt.instance<MarkdownState>();
    _mdState.initialize();
    _mdState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    _forceSave();
    _mdState.autoSaveService.unwatch();
    _mdState.removeListener(_onStateChanged);
    _titleController?.dispose();
    _contentController?.dispose();
    _saveStatus.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _loadFile() {
    final file = _mdState.currentFile;
    if (file == null || file.id == _loadedFileId) return;

    _forceSave();
    _debounce?.cancel();
    _hideTimer?.cancel();
    _saveStatus.value = '';
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

  void _onUserEdit() {
    if (!mounted) return;
    _hideTimer?.cancel();
    _saveStatus.value = '';
    _mdState.autoSaveService.markDirty();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    if (!mounted) return;
    final fileId = _loadedFileId;
    if (fileId == null || _contentController == null) return;

    final ok = await _mdState.autoSaveService.forceSave(
      fileId: fileId,
      title: _titleController?.text ?? '',
      content: _contentController!.text,
    );

    if (!mounted) return;
    if (ok) {
      _saveStatus.value = 'saved';
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _saveStatus.value = '';
      });
    }
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

    final fileListPanel = GlassmorphicContainer(
      borderRadius: 20,
      color: widget.themeState.editorBgColor,
      opacity: isDark ? 0.90 : 0.92,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildListHeader(theme, accentColor, isDark),
          const SizedBox(height: 8),
          _buildSearchBar(accentColor, isDark),
          const SizedBox(height: 8),
          Expanded(
            child: _buildFileList(theme, accentColor, isDark),
          ),
        ],
      ),
    );

    // On mobile: show file list or editor (not both side-by-side)
    if (kIsMobile) {
      final showEditor = _mdState.currentFile != null && _mobileShowEditor;
      final padding = const EdgeInsets.fromLTRB(12, 0, 12, 12);

      if (showEditor) {
        return Padding(
          padding: padding,
          child: Column(
            children: [
              // Back button to return to file list
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _mobileShowEditor = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded,
                                size: 16,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              'Files',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildEditorPanel(context, theme, accentColor, isDark),
              ),
            ],
          ),
        );
      }

      return Padding(padding: padding, child: fileListPanel);
    }

    // Desktop: side-by-side file list + editor
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          SizedBox(width: 320, child: fileListPanel),
          const SizedBox(width: 16),
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

  // ── Unified Tree (replaces horizontal project chips) ───────────────────

  /// File-explorer-style vertical tree: an "All" pseudo-row, then each
  /// project as an expandable folder containing its files, then root files
  /// as leaves at depth 0. Matches the notes sidebar conventions
  /// (L-bracket guides, single visible selection — file wins).
  Widget _buildUnifiedTree(ThemeData theme, Color accentColor, bool isDark) {
    final state = _mdState;
    final currentFileId = state.currentFile?.id;
    final selectedProjectId = state.selectedProjectId;
    final hasOpenFile = currentFileId != null;
    final rows = <Widget>[];

    // "All" pseudo-row at the top — click to clear the create-context, hover
    // actions are pinned so users can add a root file or new project without
    // hunting for a button.
    rows.add(FolderTreeRow(
      label: 'All',
      guides: const [],
      color: accentColor,
      isDark: isDark,
      isSelected: selectedProjectId == null && !hasOpenFile,
      hasChildren: false,
      isExpanded: false,
      count: 0,
      leadingIcon: Icons.inbox_rounded,
      onTap: () => state.filterByProject(null),
      onCreatePrimary: () async {
        state.filterByProject(null);
        await state.createFile(projectId: null);
      },
      createPrimaryTooltip: 'New file at root',
      createPrimaryIcon: Icons.note_add_outlined,
      onCreateSecondary: () => _showCreateProjectDialog(accentColor),
      createSecondaryTooltip: 'New project',
      createSecondaryIcon: Icons.create_new_folder_outlined,
      alwaysShowActions: true,
    ));

    rows.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Container(
        height: 1,
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
      ),
    ));

    final projects = state.projects;
    final rootFiles = state.filesInProject(null);

    if (projects.isEmpty && rootFiles.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.article_outlined,
                  size: 32, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'No markdown files',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ));
    } else {
      for (var i = 0; i < projects.length; i++) {
        final p = projects[i];
        final filesIn = state.filesInProject(p.id);
        final hasChildren = filesIn.isNotEmpty;
        final isExpanded = state.isProjectExpanded(p.id);

        rows.add(GestureDetector(
          onSecondaryTapUp: (details) =>
              _showProjectContextMenu(details.globalPosition, p),
          child: FolderTreeRow(
            label: p.name,
            guides: const [],
            color: p.color,
            isDark: isDark,
            isSelected: selectedProjectId == p.id && !hasOpenFile,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            count: filesIn.length,
            leadingIcon: Icons.folder_rounded,
            onTap: () {
              state.filterByProject(p.id);
              if (hasChildren && !isExpanded) {
                state.toggleProjectExpanded(p.id);
              }
            },
            onChevronTap: hasChildren
                ? () => state.toggleProjectExpanded(p.id)
                : null,
            onLongPress: () => _showDeleteProjectDialog(p),
            onCreatePrimary: () async {
              state.filterByProject(p.id);
              if (!state.isProjectExpanded(p.id)) {
                state.toggleProjectExpanded(p.id);
              }
              await state.createFile(projectId: p.id);
            },
            createPrimaryTooltip: 'New file in this project',
            createPrimaryIcon: Icons.note_add_outlined,
          ),
        ));

        if (hasChildren && isExpanded) {
          for (var j = 0; j < filesIn.length; j++) {
            rows.add(_buildFileLeaf(
              file: filesIn[j],
              accentColor: accentColor,
              isDark: isDark,
              currentFileId: currentFileId,
              guides: [
                j == filesIn.length - 1 ? GuideKind.ell : GuideKind.tee,
              ],
            ));
          }
        }
      }

      // Root files: render as leaves at depth 0, after all projects.
      for (final file in rootFiles) {
        rows.add(_buildFileLeaf(
          file: file,
          accentColor: accentColor,
          isDark: isDark,
          currentFileId: currentFileId,
          guides: const [],
        ));
      }
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _buildFileLeaf({
    required MarkdownFile file,
    required Color accentColor,
    required bool isDark,
    required String? currentFileId,
    required List<GuideKind> guides,
  }) {
    final title = file.title.trim().isEmpty ? 'Untitled' : file.title;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showFileContextMenu(details.globalPosition, file),
      child: LeafTreeRow(
        label: title,
        guides: guides,
        isDark: isDark,
        accentColor: accentColor,
        isSelected: file.id == currentFileId,
        onTap: () => _openFile(file),
      ),
    );
  }

  /// Open a file in the editor. Also nudges the project filter to match the
  /// file's project so subsequent "new file" actions land in the same scope.
  void _openFile(MarkdownFile file) {
    _mdState.filterByProject(file.projectId ?? '__root__');
    _mdState.selectFile(file);
    _loadFile();
    if (kIsMobile) {
      setState(() => _mobileShowEditor = true);
    }
  }

  Future<void> _showFileContextMenu(
      Offset position, MarkdownFile file) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete file',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (result == 'delete' && mounted) {
      await _mdState.deleteFile(file.id);
    }
  }

  // ── Search Bar ────────────────────────────────────────────────────────

  Widget _buildSearchBar(Color accentColor, bool isDark) {
    return SizedBox(
      height: 34,
      child: TextField(
        onChanged: (q) => _mdState.search(q),
        style: TextStyle(
          fontSize: 12,
          color: widget.themeState.editorTextColor,
        ),
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: widget.themeState.editorMutedTextColor,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: widget.themeState.editorMutedTextColor,
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

  /// During search, show a flat result list (project + date metadata helps
  /// disambiguate matches across projects). Otherwise render the unified
  /// tree so projects and files stay in their hierarchy.
  Widget _buildFileList(ThemeData theme, Color accentColor, bool isDark) {
    if (_mdState.searchQuery.isNotEmpty) {
      return _buildSearchResults(theme, accentColor, isDark);
    }
    return _buildUnifiedTree(theme, accentColor, isDark);
  }

  Widget _buildSearchResults(
      ThemeData theme, Color accentColor, bool isDark) {
    final q = _mdState.searchQuery.toLowerCase();
    // Search ignores the project filter — show every file whose title or
    // body matches, no matter where it lives.
    final files = _mdState.files
        .where((f) =>
            f.title.toLowerCase().contains(q) ||
            f.content.toLowerCase().contains(q))
        .toList();

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              'No files found',
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
      itemBuilder: (context, index) =>
          _buildFlatFileCard(files[index], accentColor, isDark),
    );
  }

  /// Rich card used in search results — keeps project + date metadata so
  /// matches are easy to scan across projects.
  Widget _buildFlatFileCard(
      MarkdownFile file, Color accentColor, bool isDark) {
    final isSelected = file.id == _mdState.currentFile?.id;
    final project = _mdState.projectForId(file.projectId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _openFile(file),
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
                            : widget.themeState.editorTextColor,
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
  }

  // ── Editor / Preview Panel ──────────────────────────────────────────────

  Widget _buildEditorPanel(
      BuildContext context, ThemeData theme, Color accentColor, bool isDark) {
    final file = _mdState.currentFile;

    if (file == null || _contentController == null) {
      return GlassmorphicContainer(
        borderRadius: 20,
        color: widget.themeState.editorBgColor,
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
      color: widget.themeState.editorBgColor,
      opacity: isDark ? 0.90 : 0.95,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header: title + toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 560;

                // ── Save indicator (shared) ──
                final saveIndicator = ValueListenableBuilder<String>(
                  valueListenable: _saveStatus,
                  builder: (context, status, _) {
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.centerLeft,
                      child: status == 'saved'
                          ? Container(
                              height: 32,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.green.withValues(alpha: 0.30)
                                      : Colors.green.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Saved',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                );

                // ── Date chip (shared) ──
                final dateChip = Container(
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
                );

                // ── Editor / Preview toggle (shared) ──
                final editorToggle = Container(
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
                        label: isMobile ? null : 'Edit',
                        isSelected: !isPreview,
                        accentColor: accentColor,
                        isDark: isDark,
                        onTap: () => _mdState.setPreviewMode(false),
                      ),
                      _buildToggleBtn(
                        icon: Icons.visibility_rounded,
                        label: isMobile ? null : 'Preview',
                        isSelected: isPreview,
                        accentColor: accentColor,
                        isDark: isDark,
                        onTap: () {
                          _forceSave();
                          _mdState.setPreviewMode(true);
                        },
                      ),
                    ],
                  ),
                );

                if (isMobile) {
                  // Mobile: two rows
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: title + save indicator + toggle
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              onChanged: (_) => _onUserEdit(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'File title...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade400,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          saveIndicator,
                          const SizedBox(width: 6),
                          editorToggle,
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Row 2: date + text controls
                      Row(
                        children: [
                          dateChip,
                          const SizedBox(width: 6),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: EditorTextControls(
                                  themeState: widget.themeState,
                                  isMarkdown: true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // Desktop: single row (original)
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        onChanged: (_) => _onUserEdit(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        decoration: InputDecoration(
                          hintText: 'File title...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    saveIndicator,
                    const SizedBox(width: 8),
                    dateChip,
                    const SizedBox(width: 6),
                    EditorTextControls(
                        themeState: widget.themeState, isMarkdown: true),
                    const SizedBox(width: 6),
                    editorToggle,
                  ],
                );
              },
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
    String? label,
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
            if (label != null) ...[
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
        onChanged: (_) => _onUserEdit(),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: widget.themeState.editorTextColor,
        cursorHeight: widget.themeState.markdownFontSize,
        style: GoogleFonts.sourceCodePro(
          fontSize: widget.themeState.markdownFontSize,
          height: widget.themeState.markdownLineHeight,
          color: widget.themeState.editorTextColor,
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
              final textColor = widget.themeState.editorTextColor;
              final mutedTextColor = widget.themeState.editorMutedTextColor;
              final accentColor = widget.themeState.accentColor;

              final inlineCodeColor = isDark
                  ? const Color(0xFFFFB38A) // soft peach
                  : const Color(0xFFB3261E); // warm red
              final inlineCodeBg = isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFF4ECE6);
              final codeBlockBg = isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF7F7F9);
              final codeBlockBorder = isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06);
              final tableBorderColor = isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.1);
              final blockquoteBg = isDark
                  ? accentColor.withValues(alpha: 0.06)
                  : accentColor.withValues(alpha: 0.04);

              return Markdown(
              data: content,
              selectable: true,
              onTapLink: (text, href, title) {},
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontSize: baseFontSize,
                  height: lineHeight,
                  color: textColor,
                ),
                h1: TextStyle(
                  fontSize: (28 * scale).roundToDouble(),
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
                h2: TextStyle(
                  fontSize: (22 * scale).roundToDouble(),
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                h3: TextStyle(
                  fontSize: (18 * scale).roundToDouble(),
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                a: TextStyle(
                  color: accentColor,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor.withValues(alpha: 0.5),
                ),
                code: GoogleFonts.sourceCodePro(
                  fontSize: (13 * scale).roundToDouble(),
                  color: inlineCodeColor,
                  backgroundColor: inlineCodeBg,
                ),
                codeblockDecoration: BoxDecoration(
                  color: codeBlockBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: codeBlockBorder, width: 1),
                ),
                blockquote: TextStyle(
                  fontSize: baseFontSize,
                  height: lineHeight,
                  color: mutedTextColor,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: BoxDecoration(
                  color: blockquoteBg,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border(
                    left: BorderSide(color: accentColor, width: 3),
                  ),
                ),
                blockquotePadding:
                    const EdgeInsets.fromLTRB(14, 10, 14, 10),
                tableHead: TextStyle(
                  fontSize: baseFontSize,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                tableBody: TextStyle(
                  fontSize: baseFontSize,
                  color: textColor,
                ),
                tableHeadAlign: TextAlign.left,
                tableBorder: TableBorder.all(
                  color: tableBorderColor,
                  width: 1,
                  borderRadius: BorderRadius.circular(8),
                ),
                tableCellsPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                listBullet: TextStyle(
                  fontSize: baseFontSize,
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: tableBorderColor, width: 1),
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

