import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'art_hue.dart';
import 'settings_store.dart';

/// The four retro themes from the RetroWave Figma design.
class RetroPalette {
  final String name;
  final String era;
  final Color bgTop;
  final Color bgBottom;
  final Color accent;
  final Color accent2;
  final Color card;
  final Color textDim;

  const RetroPalette({
    required this.name,
    required this.era,
    required this.bgTop,
    required this.bgBottom,
    required this.accent,
    required this.accent2,
    required this.card,
    required this.textDim,
  });
}

const List<RetroPalette> palettes = <RetroPalette>[
  RetroPalette(
    name: 'Neon Synthwave',
    era: '80s',
    bgTop: Color(0xFF1A0533),
    bgBottom: Color(0xFF0D0217),
    accent: Color(0xFFFF2E88),
    accent2: Color(0xFF00E5FF),
    card: Color(0xFF241040),
    textDim: Color(0xFFB8A6D9),
  ),
  RetroPalette(
    name: 'Vinyl Sunset',
    era: '70s',
    bgTop: Color(0xFF3B1D0E),
    bgBottom: Color(0xFF170B04),
    accent: Color(0xFFFF9E3D),
    accent2: Color(0xFFFFD23D),
    card: Color(0xFF4A2A14),
    textDim: Color(0xFFD9BBA6),
  ),
  RetroPalette(
    name: 'Boombox Chrome',
    era: '90s',
    bgTop: Color(0xFF101418),
    bgBottom: Color(0xFF05070A),
    accent: Color(0xFFC0C8D0),
    accent2: Color(0xFF4DD0E1),
    card: Color(0xFF1C232A),
    textDim: Color(0xFF9FB0BC),
  ),
  RetroPalette(
    name: 'Cassette Walkman',
    era: 'Walkman',
    bgTop: Color(0xFF2A2118),
    bgBottom: Color(0xFF100C07),
    accent: Color(0xFFFFCC33),
    accent2: Color(0xFFFF7043),
    card: Color(0xFF3A2E20),
    textDim: Color(0xFFCBBA9E),
  ),
  RetroPalette(
    name: 'Smokey Glass',
    era: 'Frosted • Glass',
    bgTop: Color(0xFF26272E),
    bgBottom: Color(0xFF101116),
    accent: Color(0xFF8FD8D2),
    accent2: Color(0xFFC3B2DB),
    card: Color(0x2AFFFFFF),
    textDim: Color(0xFFB9BDC7),
  ),
];

/// Currently selected theme index (0 = Neon Synthwave, the design default).
final ValueNotifier<int> themeIndex = ValueNotifier<int>(0);

/// A user-picked custom color. When set, it overrides the preset theme:
/// RetroWave builds a full palette around it in the app's retro style.
final ValueNotifier<Color?> customColor = ValueNotifier<Color?>(null);

/// Bumped whenever the appearance (theme or custom color) changes,
/// so screens listening to it rebuild with the new palette.
final ValueNotifier<int> appearanceVersion = ValueNotifier<int>(0);

/// Curated colors offered in the custom-color picker — chosen to fit
/// the app's retro philosophy (neon, sunset, chrome, cassette).
const List<Color> swatchColors = <Color>[
  Color(0xFFFF2E88), // Neon Pink
  Color(0xFF00E5FF), // Cyber Cyan
  Color(0xFF8A2EFF), // Ultraviolet
  Color(0xFFFF7A3D), // Sunset Orange
  Color(0xFFFFC93D), // Vinyl Gold
  Color(0xFFB8C4CE), // Chrome Silver
  Color(0xFF9DFF3D), // Laser Lime
  Color(0xFFFF3D3D), // Turbo Red
  Color(0xFF2EE6A8), // Miami Teal
  Color(0xFF3D7BFF), // VHS Blue
];

/// Builds a complete retro palette around any base color: deep dark
/// tinted backgrounds, a glowing accent, a harmonized second accent,
/// and a soft dim text color — the same recipe as the preset themes.
RetroPalette paletteFor(Color base) {
  final hsl = HSLColor.fromColor(base);
  final sat = hsl.saturation;
  Color shade(double lightness, double saturation) => hsl
      .withLightness(lightness.clamp(0.0, 1.0))
      .withSaturation(saturation.clamp(0.0, 1.0))
      .toColor();
  return RetroPalette(
    name: 'Custom',
    era: 'Your color',
    bgTop: shade(0.10, (sat * 0.85).clamp(0.18, 0.85)),
    bgBottom: shade(0.045, (sat * 0.8).clamp(0.15, 0.8)),
    accent: hsl
        .withLightness(0.62)
        .withSaturation(sat.clamp(0.45, 1.0))
        .toColor(),
    accent2: hsl
        .withHue((hsl.hue + 55) % 360)
        .withLightness(0.62)
        .withSaturation(sat.clamp(0.45, 1.0))
        .toColor(),
    card: shade(0.15, (sat * 0.7).clamp(0.12, 0.7)),
    textDim: shade(0.74, (sat * 0.5).clamp(0.10, 0.5)),
  );
}

/// Whether the app is currently in dark mode, after applying the
/// user's Dark mode setting ('system' follows the phone).
final ValueNotifier<bool> effectiveDark = ValueNotifier<bool>(true);

/// A light-mode version of a palette: same accent hues, bright tinted
/// backgrounds, for the Dark mode = Light / Match phone options.
RetroPalette lightVariant(RetroPalette d) {
  final hsl = HSLColor.fromColor(d.accent);
  final s = hsl.saturation;
  Color c(double lightness, double satScale) => hsl
      .withLightness(lightness)
      .withSaturation((s * satScale).clamp(0.0, 1.0))
      .toColor();
  return RetroPalette(
    name: d.name,
    era: d.era,
    bgTop: c(0.93, 0.35),
    bgBottom: c(0.97, 0.30),
    accent: d.accent,
    accent2: d.accent2,
    card: c(0.89, 0.30),
    textDim: c(0.36, 0.55),
  );
}

/// The palette the app should use right now. While a song is loaded,
/// its artwork hue (see art_hue.dart) is blended through every color,
/// so all pages quietly wear the playing album's colors.
/// A soft fade for opening screens (Now Playing above all): the
/// new page melts in instead of sliding over. Used by the music
/// flow — library taps, the mini player, AI Studio playback.
PageRoute<T> fadeRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

RetroPalette get palette {
  final c = customColor.value;
  final base = c != null
      ? paletteFor(c)
      : palettes[themeIndex.value.clamp(0, palettes.length - 1)];
  final themed = effectiveDark.value ? base : lightVariant(base);
  final hue = artHue.value;
  if (hue == null) return themed;
  return RetroPalette(
    name: themed.name,
    era: themed.era,
    bgTop: Color.lerp(themed.bgTop, hue, 0.10)!,
    bgBottom: Color.lerp(themed.bgBottom, hue, 0.07)!,
    accent: Color.lerp(themed.accent, hue, 0.45)!,
    accent2: Color.lerp(themed.accent2, hue, 0.22)!,
    card: Color.lerp(themed.card, hue, 0.12)!,
    textDim: themed.textDim,
  );
}

/// Index of the Smokey Glass preset in [palettes].
const int glassThemeIndex = 4;

/// True when the Smokey Glass theme is active — surfaces turn into
/// frosted glass (see ThemedBackground in glass.dart).
bool get glassMode =>
    customColor.value == null && themeIndex.value == glassThemeIndex;

/// Recomputes dark/light from the setting + the phone's brightness.
void recomputeEffectiveDark() {
  final mode = SettingsStore.instance.darkMode.value;
  if (mode == 'dark') {
    effectiveDark.value = true;
  } else if (mode == 'light') {
    effectiveDark.value = false;
  } else {
    effectiveDark.value =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
  }
}

/// Applies a Dark mode choice ('system' | 'dark' | 'light') and saves it.
void applyDarkMode(String mode) {
  SettingsStore.instance.darkMode.value = mode;
  recomputeEffectiveDark();
  appearanceVersion.value++;
  SettingsStore.instance.save();
}

/// Applies a preset theme, clearing any custom color, and saves the choice.
void applyTheme(int index) {
  themeIndex.value = index;
  customColor.value = null;
  appearanceVersion.value++;
  SharedPreferences.getInstance().then((p) {
    p.setInt('theme', index);
    p.remove('customColor');
  });
}

/// Applies a custom color theme and saves the choice.
void applyCustomColor(Color color) {
  customColor.value = color;
  appearanceVersion.value++;
  SharedPreferences.getInstance().then((p) {
    p.setInt('customColor', color.toARGB32());
  });
}
