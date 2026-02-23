import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/services/update_service.dart';

/// Animated banner that slides in from the top when an app update is available.
///
/// Displays the new version number with a "Download" button that opens the
/// release page in the user's browser, and an "×" button to dismiss.
class UpdateBanner extends StatefulWidget {
  final UpdateInfo update;
  final Color accentColor;
  final VoidCallback onDismiss;

  const UpdateBanner({
    super.key,
    required this.update,
    required this.accentColor,
    required this.onDismiss,
  });

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDownload() async {
    final uri = Uri.parse(widget.update.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? widget.accentColor.withValues(alpha: 0.18)
                : widget.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_rounded,
                color: widget.accentColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'New version ${widget.update.version} available',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _openDownload,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Download',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: widget.onDismiss,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
