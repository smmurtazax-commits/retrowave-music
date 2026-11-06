import 'dart:async';

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
  // Restore saved appearance choices (theme, custom color, font) and
  // the local stores. These are local reads, but they are guarded
  // anyway: nothing before runApp may ever keep the app from opening.
  try {
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
  } catch (_) {
    // A bad saved value must never freeze the launch screen.
  }
  runApp(const RetroWaveApp());
  // Playback plumbing starts only AFTER the UI is on screen. The
  // background-audio handshake can stall on some phones; it must
  // never hold the opening screen hostage, so each step has a
  // timeout and failures are swallowed — playback itself still works.
  unawaited(_initPlayback());
}

Future<void> _initPlayback() async {
  try {
    await AudioFx.setLockScreenControls(
            SettingsStore.instance.lockScreenControls.value)
        .timeout(const Duration(seconds: 3), onTimeout: () {});
  } catch (_) {}
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.murtazarizvi.retrowave.channel.audio',
      androidNotificationChannelName: 'RetroWave playback',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 10), onTimeout: () {});
  } catch (_) {}
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
