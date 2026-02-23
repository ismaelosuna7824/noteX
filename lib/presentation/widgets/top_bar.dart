import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../../domain/entities/note.dart';

/// Top navigation bar with search (floating dropdown), notifications, and user greeting.
///
/// Matches the reference design's top bar: app name on left, search + bell + user on right.
class TopBar extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;
  final String? userName;
  final String? avatarUrl;
  final VoidCallback? onProfileTap;

  const TopBar({
    super.key,
    required this.appState,
    required this.themeState,
    this.userName,
    this.avatarUrl,
    this.onProfileTap,
  });

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final LayerLink _bellLayerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  OverlayEntry? _updateOverlayEntry;
  List<Note> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      // Delay hiding so overlay item taps can fire first
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_searchFocusNode.hasFocus) {
          _hideOverlay();
        }
      });
    }
  }

  void _onSearchChanged(String query) {
    widget.appState.search(query);
    if (query.isEmpty) {
      _hideOverlay();
      return;
    }

    _searchResults = widget.appState.filteredNotes;
    _showOverlay();
  }

  void _showOverlay() {
    _hideOverlay();
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 50),
          showWhenUnlinked: false,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withValues(alpha: 0.15),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2130) : Colors.white.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: _searchResults.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 32,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No notes found',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                        ),
                        itemBuilder: (context, index) {
                          final note = _searchResults[index];
                          return InkWell(
                            onTap: () {
                              widget.appState.selectNote(note);
                              _searchController.clear();
                              widget.appState.search('');
                              _hideOverlay();
                              _searchFocusNode.unfocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.note_alt_outlined,
                                    size: 18,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          note.title.isEmpty
                                              ? 'Untitled'
                                              : note.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${note.updatedAt.month}/${note.updatedAt.day}/${note.updatedAt.year}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white54 : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: Colors.grey.shade300,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    _hideUpdateOverlay();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleUpdateOverlay() {
    if (_updateOverlayEntry != null) {
      _hideUpdateOverlay();
      return;
    }
    _showUpdateOverlay();
  }

  void _showUpdateOverlay() {
    _hideUpdateOverlay();
    final update = widget.appState.availableUpdate;
    if (update == null) return;

    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = widget.themeState.accentColor;

    _updateOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss on tap outside
          GestureDetector(
            onTap: _hideUpdateOverlay,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
          Positioned(
            width: 300,
            child: CompositedTransformFollower(
              link: _bellLayerLink,
              offset: const Offset(-258, 50),
              showWhenUnlinked: false,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(16),
                shadowColor: Colors.black.withValues(alpha: 0.20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E2130)
                        : Colors.white.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.system_update_rounded,
                              color: accentColor, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Update Available',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _hideUpdateOverlay,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.close_rounded,
                                  size: 16,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${update.version}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: accentColor,
                          ),
                        ),
                      ),
                      if (update.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Text(
                              update.releaseNotes,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: InkWell(
                          onTap: () async {
                            _hideUpdateOverlay();
                            final uri = Uri.parse(update.downloadUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text(
                                'Download Update',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_updateOverlayEntry!);
  }

  void _hideUpdateOverlay() {
    _updateOverlayEntry?.remove();
    _updateOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // In dark mode use a slightly dark frosted glass; in light mode keep white.
    final pillColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.85);
    final pillShadow = isDark
        ? Colors.black.withValues(alpha: 0.20)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : Colors.grey.shade800;
    final iconColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final hintColor = isDark ? Colors.white38 : Colors.grey.shade400;
    final avatarBg = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.grey.shade200;
    final avatarIconColor = isDark ? Colors.white60 : Colors.grey.shade500;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [

          const Spacer(),

          // Search bar with floating dropdown
          CompositedTransformTarget(
            link: _layerLink,
            child: SizedBox(
              width: 280,
              height: 42,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search notes...',
                  hintStyle: TextStyle(
                    color: hintColor,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: hintColor,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: pillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Notification bell (with update badge)
          CompositedTransformTarget(
            link: _bellLayerLink,
            child: Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: pillColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: pillShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  IconButton(
                    onPressed: widget.appState.hasUpdate
                        ? _toggleUpdateOverlay
                        : null,
                    icon: Icon(Icons.notifications_none_rounded,
                        size: 20, color: iconColor),
                    padding: EdgeInsets.zero,
                  ),
                  // Red badge dot when update is available
                  if (widget.appState.hasUpdate)
                    Positioned(
                      top: 9,
                      right: 10,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // User greeting + avatar
          InkWell(
            onTap: widget.onProfileTap,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: pillShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.appState.isAuthenticated
                        ? 'Hi, ${widget.userName ?? 'User'}'
                        : 'Sign In',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: avatarBg,
                    backgroundImage: widget.avatarUrl != null
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                    child: widget.avatarUrl == null
                        ? Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: avatarIconColor,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
