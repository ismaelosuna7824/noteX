import 'dart:ui';
import 'package:flutter/material.dart';

/// Reusable glassmorphic container widget.
///
/// Creates a frosted glass effect with blur, transparency, and rounded corners.
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final double opacity;
  final Color? color;
  final double? width;
  final double? height;
  final Border? border;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.margin,
    this.blur = 10,
    this.opacity = 0.15,
    this.color,
    this.width,
    this.height,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        color ?? (isDark ? Colors.black : Colors.white);

    final radius = BorderRadius.circular(borderRadius);

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            color: baseColor.withValues(alpha: opacity),
            child: child,
          ),
        ),
      ),
    );
  }
}
