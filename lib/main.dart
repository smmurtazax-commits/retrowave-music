import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'art_hue.dart';
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
    // (The player itself is deliberately NOT touched here — see
    // _initPlayback for why its first use waits for setup.)
    await SettingsStore.instance.load(prefs);
    await PlaylistStore.instance.load(prefs);
    recomputeEffectiveDark();
  } catch (_) {
    // A bad saved value must never freeze the launch screen.
  }
  // Background playback setup runs BEFORE runApp — this ordering is
  // load-bearing. The first screen touches the player service the
  // moment it builds, so if setup were still running at that point,
  // the player would be born before the background service exists —
  // and a player born too early fails EVERY song load on some phones
  // (builds #7–#10 on the S24: all loads failed, position/next/seek
  // dead). The wait is timeout-guarded, so the worst case is a few
  // extra seconds on the system splash — it can never freeze there.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.murtazarizvi.retrowave.channel.audio',
      androidNotificationChannelName: 'RetroWave playback',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 6), onTimeout: () {});
  } catch (_) {
    // Background support failed to start; in-app playback still works.
  }
  runApp(const RetroWaveApp());
  // The remaining playback plumbing starts only AFTER the UI is on
  // screen; each step is guarded so none of it can stall the app.
  unawaited(_initPlayback());
}

Future<void> _initPlayback() async {
  try {
    await AudioFx.setLockScreenControls(
            SettingsStore.instance.lockScreenControls.value)
        .timeout(const Duration(seconds: 3), onTimeout: () {});
  } catch (_) {}
  try {
    PlayerService.instance.applyStoredSettings();
  } catch (_) {}
  PlayerService.instance.completeInit();
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
    // When the playing song's artwork hue changes, repaint the whole
    // app so every page picks up the blended palette.
    artHue.addListener(() => appearanceVersion.value++);
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
