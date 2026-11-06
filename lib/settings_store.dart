import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All user settings (Samsung Music-style), held as notifiers and
/// persisted in SharedPreferences. This file is deliberately free of
/// player/UI imports so anything can read it without import cycles.
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  /// Sleep timer length in minutes (0 = off).
  final ValueNotifier<int> sleepMinutes = ValueNotifier<int>(0);

  /// Playback speed multiplier (0.5–2.0).
  final ValueNotifier<double> playSpeed = ValueNotifier<double>(1.0);

  /// Crossfade length in seconds (0 = off). Implemented as a smooth
  /// fade-out / fade-in between tracks.
  final ValueNotifier<int> crossfadeSeconds = ValueNotifier<int>(0);

  /// Trim silence from the start/end of tracks.
  final ValueNotifier<bool> skipSilence = ValueNotifier<bool>(false);

  /// Whether media controls may appear on the lock screen.
  final ValueNotifier<bool> lockScreenControls = ValueNotifier<bool>(true);

  /// Library layout for songs and playlists: false = list rows,
  /// true = grid (rows and columns of artwork cards).
  final ValueNotifier<bool> gridView = ValueNotifier<bool>(false);

  /// What tapping a song does: 'all' = queue the whole list from that
  /// song, 'single' = play only that song.
  final ValueNotifier<String> queueMode = ValueNotifier<String>('all');

  /// Keep duplicate songs out of queues and playlists.
  final ValueNotifier<bool> noDuplicates = ValueNotifier<bool>(true);

  /// Library tab ids, in display order.
  static const List<String> allTabs = <String>[
    'songs',
    'albums',
    'artists',
    'folders',
    'playlists',
    'favourites',
  ];

  /// Which library tabs are visible (see Manage tabs).
  final ValueNotifier<List<String>> enabledTabs =
      ValueNotifier<List<String>>(List<String>.of(allTabs));

  /// Dark mode: 'system' | 'dark' | 'light'.
  final ValueNotifier<String> darkMode = ValueNotifier<String>('system');

  /// Let external devices (Bluetooth, car, watch) start playback.
  final ValueNotifier<bool> externalStart = ValueNotifier<bool>(true);

  Future<void> load(SharedPreferences prefs) async {
    sleepMinutes.value = prefs.getInt('set.sleepMinutes') ?? 0;
    playSpeed.value = prefs.getDouble('set.playSpeed') ?? 1.0;
    crossfadeSeconds.value = prefs.getInt('set.crossfade') ?? 0;
    skipSilence.value = prefs.getBool('set.skipSilence') ?? false;
    lockScreenControls.value = prefs.getBool('set.lockScreen') ?? true;
    gridView.value = prefs.getBool('set.gridView') ?? false;
    queueMode.value = prefs.getString('set.queueMode') ?? 'all';
    noDuplicates.value = prefs.getBool('set.noDuplicates') ?? true;
    final tabs = prefs.getStringList('set.tabs');
    if (tabs != null && tabs.isNotEmpty) {
      enabledTabs.value = tabs.where(allTabs.contains).toList();
      if (enabledTabs.value.isEmpty) {
        enabledTabs.value = List<String>.of(allTabs);
      }
    }
    darkMode.value = prefs.getString('set.darkMode') ?? 'system';
    externalStart.value = prefs.getBool('set.externalStart') ?? true;
  }

  /// Persists every setting at once (cheap; called on any change).
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('set.sleepMinutes', sleepMinutes.value);
    await prefs.setDouble('set.playSpeed', playSpeed.value);
    await prefs.setInt('set.crossfade', crossfadeSeconds.value);
    await prefs.setBool('set.skipSilence', skipSilence.value);
    await prefs.setBool('set.lockScreen', lockScreenControls.value);
    await prefs.setBool('set.gridView', gridView.value);
    await prefs.setString('set.queueMode', queueMode.value);
    await prefs.setBool('set.noDuplicates', noDuplicates.value);
    await prefs.setStringList('set.tabs', enabledTabs.value);
    await prefs.setString('set.darkMode', darkMode.value);
    await prefs.setBool('set.externalStart', externalStart.value);
  }
}

/// Display labels for library tab ids.
const Map<String, String> tabLabels = <String, String>{
  'songs': 'Tracks',
  'albums': 'Albums',
  'artists': 'Artists',
  'folders': 'Folders',
  'playlists': 'Playlists',
  'favourites': 'Favourites',
};
