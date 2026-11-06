import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Selectable app fonts, matched to the retro themes.
/// The choice applies across the whole app.
class AppFont {
  final String name;
  final String feel;
  const AppFont(this.name, this.feel);
}

const List<AppFont> fontOptions = <AppFont>[
  AppFont('Default', 'Clean system font'),
  AppFont('Orbitron', '80s neon tech'),
  AppFont('Audiowide', 'Retro display'),
  AppFont('Rajdhani', 'Clean tech'),
  AppFont('Share Tech Mono', 'Cassette computer'),
];

/// Currently selected font index (0 = Default).
final ValueNotifier<int> fontIndex = ValueNotifier<int>(0);

/// Resolves the font family name for an option index.
/// Google Fonts are fetched once and then cached on the phone.
String? fontFamilyFor(int index) {
  switch (index) {
    case 1:
      return GoogleFonts.orbitron().fontFamily;
    case 2:
      return GoogleFonts.audiowide().fontFamily;
    case 3:
      return GoogleFonts.rajdhani().fontFamily;
    case 4:
      return GoogleFonts.shareTechMono().fontFamily;
    default:
      return null;
  }
}

/// Applies a font choice and saves it for the next launch.
void applyFont(int index) {
  fontIndex.value = index;
  SharedPreferences.getInstance().then((p) => p.setInt('font', index));
}
