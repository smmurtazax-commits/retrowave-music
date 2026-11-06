import 'dart:ui';

import 'package:flutter/material.dart';

import 'themes.dart';

/// The app's full-screen background.
///
/// Normally this is the theme's two-color gradient. When the
/// Smokey Glass theme is active, soft clouds of the accent colors
/// drift behind everything, so the app's translucent, blurred
/// surfaces (mini player, cards) read as frosted smoky glass.
class ThemedBackground extends StatelessWidget {
  final RetroPalette palette;
  final Widget child;

  const ThemedBackground({
    super.key,
    required this.palette,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final gradient = BoxDecoration(
      gradient: LinearGradient(
        colors: [p.bgTop, p.bgBottom],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    if (!glassMode) {
      return Container(decoration: gradient, child: child);
    }
    return Container(
      decoration: gradient,
      child: Stack(
        children: [
          Positioned(top: -90, left: -70, child: _blob(p.accent, 280)),
          Positioned(bottom: -110, right: -80, child: _blob(p.accent2, 320)),
          Positioned(top: 220, right: -130, child: _blob(p.accent, 190)),
          Positioned(bottom: 160, left: -120, child: _blob(p.accent2, 170)),
          child,
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.33),
        ),
      ),
    );
  }
}
