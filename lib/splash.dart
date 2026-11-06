import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'library.dart';
import 'themes.dart';

/// The opening screen: the app name in an embossed style with a small
/// embossed logo above it, on the active theme's colored background.
/// Shows briefly at launch, then fades into the library.
/// Tapping it skips straight in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 2100), _go);
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const LibraryScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      body: GestureDetector(
        onTap: _go,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [p.bgTop, p.bgBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: FadeTransition(
              opacity: _anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(
                  CurvedAnimation(parent: _anim, curve: Curves.easeOut),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _embossedLogo(p),
                        const SizedBox(width: 20),
                        _minimalName(p),
                      ],
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: 120,
                      child: LinearProgressIndicator(
                        backgroundColor: p.card,
                        color: p.accent,
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A raised, embossed disc with the wave mark pressed into it:
  /// a dark shadow below and a light rim above give the carved look.
  Widget _embossedLogo(RetroPalette p) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(p.card, p.bgTop),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            offset: const Offset(0, 8),
            blurRadius: 16,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.09),
            offset: const Offset(0, -6),
            blurRadius: 12,
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq,
        size: 46,
        color: p.accent,
        shadows: const [
          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 3),
          Shadow(color: Colors.white24, offset: Offset(0, -1), blurRadius: 1),
        ],
      ),
    );
  }

  /// The app name in a minimal style: a light, thin typeface in
  /// wide-spaced capitals — quiet and clean, no heavy effects.
  /// Sits beside the logo disc as one horizontal lockup.
  Widget _minimalName(RetroPalette p) {
    final family =
        GoogleFonts.montserrat(fontWeight: FontWeight.w300).fontFamily;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RETROWAVE',
          style: TextStyle(
            fontFamily: family,
            fontSize: 30,
            fontWeight: FontWeight.w300,
            letterSpacing: 10,
            color: Colors.white.withOpacity(0.94),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'MUSIC',
          style: TextStyle(
            fontFamily: family,
            fontSize: 13,
            fontWeight: FontWeight.w300,
            letterSpacing: 14,
            color: Colors.white.withOpacity(0.55),
          ),
        ),
      ],
    );
  }
}
