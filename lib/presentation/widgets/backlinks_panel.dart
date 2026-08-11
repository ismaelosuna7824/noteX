import 'package:flutter/material.dart';

import '../../application/use_cases/get_backlinks_use_case.dart';

/// Collapsible list of the notes that link to the one being viewed.
///
/// Renders nothing at all when a note has no backlinks: an empty "Linked
/// mentions (0)" header is chrome that costs vertical space on every note that
/// has not been linked yet, which is most of them.
class BacklinksPanel extends StatelessWidget {
  /// Backlinks to display, already resolved and ordered by the use case.
  final List<Backlink> backlinks;

  /// Called with the id of the note the user wants to open.
  final ValueChanged<String> onOpen;

  final Color accentColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;

  const BacklinksPanel({
    super.key,
    required this.backlinks,
    required this.onOpen,
    required this.accentColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    if (backlinks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 15, color: accentColor),
              const SizedBox(width: 6),
              Text(
                backlinks.length == 1
                    ? '1 linked mention'
                    : '${backlinks.length} linked mentions',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final backlink in backlinks)
            _BacklinkTile(
              backlink: backlink,
              onOpen: onOpen,
              textColor: textColor,
              mutedColor: mutedColor,
            ),
        ],
      ),
    );
  }
}

class _BacklinkTile extends StatelessWidget {
  final Backlink backlink;
  final ValueChanged<String> onOpen;
  final Color textColor;
  final Color mutedColor;

  const _BacklinkTile({
    required this.backlink,
    required this.onOpen,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final source = backlink.source;
    final title = source.title.trim().isEmpty ? 'Untitled' : source.title;
    // The link text as written in the source note. Worth showing when it
    // differs from that note's title, because it is the wording the reader
    // will actually find over there.
    final showsLinkText =
        backlink.displayText.isNotEmpty && backlink.displayText != title;

    return InkWell(
      onTap: () => onOpen(source.id),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showsLinkText)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'linked as "${backlink.displayText}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mutedColor, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
