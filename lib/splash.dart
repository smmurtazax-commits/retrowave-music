import 'dart:async';

import 'package:flutter/material.dart';

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
                    _embossedLogo(p),
                    const SizedBox(height: 26),
                    _embossedText('RetroWave', p, 40),
                    const SizedBox(height: 6),
                    Text(
                      'M U S I C',
                      style: TextStyle(
                        color: p.accent2,
                        fontSize: 15,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
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

  /// Embossed lettering: deepened accent fill, a dark shadow dropped
  /// below and a light highlight above, like the name is pressed
  /// into the surface.
  Widget _embossedText(String text, RetroPalette p, double size) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        color: Color.alphaBlend(p.accent.withOpacity(0.9), p.bgBottom),
        shadows: const [
          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 3),
          Shadow(color: Colors.white30, offset: Offset(0, -1), blurRadius: 1),
        ],
      ),
    );
  }
}
