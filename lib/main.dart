import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiofx.dart';
import 'fonts.dart';
import 'library.dart';
import 'splash.dart';
import 'player.dart';
import 'playlists.dart';
import 'settings_store.dart';
import 'themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore saved appearance choices (theme, custom color, font).
  final prefs = await SharedPreferences.getInstance();
  themeIndex.value = prefs.getInt('theme') ?? 0;
  fontIndex.value = prefs.getInt('font') ?? 0;
  final savedColor = prefs.getInt('customColor');
  if (savedColor != null) {
    customColor.value = Color(savedColor);
  }
  // Settings, playlists, and the playback preferences they drive.
  await SettingsStore.instance.load(prefs);
  await PlaylistStore.instance.load(prefs);
  recomputeEffectiveDark();
  PlayerService.instance.applyStoredSettings();
  await AudioFx.setLockScreenControls(
      SettingsStore.instance.lockScreenControls.value);
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.murtazarizvi.retrowave.channel.audio',
    androidNotificationChannelName: 'RetroWave playback',
    androidNotificationOngoing: true,
  );
  runApp(const RetroWaveApp());
}

class RetroWaveApp extends StatefulWidget {
  const RetroWaveApp({super.key});

  @override
  State<RetroWaveApp> createState() => _RetroWaveAppState();
}

class _RetroWaveAppState extends State<RetroWaveApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final before = effectiveDark.value;
    recomputeEffectiveDark();
    if (effectiveDark.value != before) {
      appearanceVersion.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appearanceVersion,
      builder: (context, _, __) {
        final p = palette;
        return ValueListenableBuilder<int>(
          valueListenable: fontIndex,
          builder: (context, fIdx, __) {
            return MaterialApp(
              title: 'RetroWave Music',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness:
                    effectiveDark.value ? Brightness.dark : Brightness.light,
                fontFamily: fontFamilyFor(fIdx),
                scaffoldBackgroundColor: p.bgBottom,
                colorScheme: ColorScheme(
                  brightness:
                      effectiveDark.value ? Brightness.dark : Brightness.light,
                  primary: p.accent,
                  onPrimary: Colors.white,
                  secondary: p.accent2,
                  onSecondary: Colors.black,
                  surface: p.card,
                  onSurface: effectiveDark.value
                      ? Colors.white
                      : const Color(0xFF1A1A1A),
                  error: Colors.redAccent,
                  onError: Colors.white,
                ),
                useMaterial3: true,
              ),
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
