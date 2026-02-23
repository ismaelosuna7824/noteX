import 'package:flutter/material.dart';
import '../../domain/services/update_service.dart';
import '../state/app_state.dart';

/// Animated banner that slides in from the top when an app update is available.
///
/// Shows "Update" button that downloads and installs the update in-place.
/// During download it displays a progress bar.
class UpdateBanner extends StatefulWidget {
  final UpdateInfo update;
  final Color accentColor;
  final VoidCallback onDismiss;
  final AppState appState;

  const UpdateBanner({
    super.key,
    required this.update,
    required this.accentColor,
    required this.onDismiss,
    required this.appState,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            final isUpdating = widget.appState.isUpdating;
            final progress = widget.appState.updateProgress;

            return Container(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.system_update_rounded,
                        color: widget.accentColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isUpdating
                              ? 'Downloading... ${(progress * 100).toInt()}%'
                              : 'New version ${widget.update.version} available',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isUpdating) ...[
                        InkWell(
                          onTap: () => widget.appState.applyUpdate(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Update',
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
                              color:
                                  isDark ? Colors.white54 : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isUpdating) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        backgroundColor:
                            widget.accentColor.withValues(alpha: 0.15),
                        valueColor:
                            AlwaysStoppedAnimation(widget.accentColor),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
