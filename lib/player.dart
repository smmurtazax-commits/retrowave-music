import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'settings_store.dart';

/// Single shared player for the whole app.
class PlayerService {
  PlayerService._() {
    _initEngines();
  }
  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();

  /// The songs in the current playing queue, in order.
  List<SongModel> queue = <SongModel>[];

  Future<void> playQueue(List<SongModel> songs, int startIndex) async {
    _markSelf();
    queue = List<SongModel>.of(songs);
    final sources = songs.map((s) {
      final Uri uri;
      if (s.uri != null && s.uri!.isNotEmpty) {
        uri = Uri.parse(s.uri!);
      } else {
        uri = Uri.file(s.data);
      }
      // Album art from the phone's media store, so the lock screen,
      // the notification controls and Samsung's Now Bar capsule show
      // the song's artwork, title and artist.
      final Uri? artUri = s.albumId != null
          ? Uri.parse(
              'content://media/external/audio/albumart/${s.albumId}')
          : null;
      return AudioSource.uri(
        uri,
        tag: MediaItem(
          id: s.id.toString(),
          title: s.title,
          artist: (s.artist == null || s.artist == '<unknown>')
              ? 'Unknown artist'
              : s.artist,
          album: s.album ?? '',
          artUri: artUri,
        ),
      );
    }).toList();
    await player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
    );
    await player.play();
  }

  SongModel? get currentSong {
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= queue.length) return null;
    return queue[i];
  }

  // --- Sleep timer ----------------------------------------------------

  Timer? _sleepTimer;

  /// When the sleep timer will stop playback (null = off).
  final ValueNotifier<DateTime?> sleepEndsAt = ValueNotifier<DateTime?>(null);

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt.value = null;
    SettingsStore.instance.sleepMinutes.value = minutes;
    SettingsStore.instance.save();
    if (minutes <= 0) return;
    sleepEndsAt.value = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      player.pause();
      sleepEndsAt.value = null;
      SettingsStore.instance.sleepMinutes.value = 0;
      SettingsStore.instance.save();
    });
  }

  // --- In-app vs external start ----------------------------------------

  bool _selfInitiated = false;

  void _markSelf() {
    _selfInitiated = true;
    Future.delayed(const Duration(seconds: 2), () => _selfInitiated = false);
  }

  /// Play pressed from inside the app (as opposed to a Bluetooth /
  /// car / watch media button, which reaches the player directly).
  Future<void> userPlay() async {
    _markSelf();
    await player.play();
  }

  // --- Stored playback settings ----------------------------------------

  void applyStoredSettings() {
    player.setSpeed(SettingsStore.instance.playSpeed.value);
    player.setSkipSilenceEnabled(SettingsStore.instance.skipSilence.value);
  }

  // --- Crossfade engine (fade out / fade in) + external-start guard ----

  Timer? _fadeTimer;

  void _initEngines() {
    player.playerStateStream.listen((state) {
      if (state.playing &&
          !_selfInitiated &&
          !SettingsStore.instance.externalStart.value) {
        final life = WidgetsBinding.instance.lifecycleState;
        if (life != null && life != AppLifecycleState.resumed) {
          player.pause();
        }
      }
      if (state.playing) {
        _fadeTimer ??= Timer.periodic(
            const Duration(milliseconds: 100), (_) => _fadeTick());
      } else {
        _fadeTimer?.cancel();
        _fadeTimer = null;
        player.setVolume(1.0);
      }
      if (state.processingState == ProcessingState.completed) {
        player.setVolume(1.0);
      }
    });
    player.currentIndexStream.listen((_) {
      if (SettingsStore.instance.crossfadeSeconds.value > 0) {
        player.setVolume(0.0);
      } else {
        player.setVolume(1.0);
      }
    });
  }

  void _fadeTick() {
    final fadeSec = SettingsStore.instance.crossfadeSeconds.value;
    if (fadeSec <= 0) {
      if (player.volume != 1.0) player.setVolume(1.0);
      return;
    }
    final dur = player.duration;
    if (dur == null) return;
    final fadeMs = fadeSec * 1000.0;
    final posMs = player.position.inMilliseconds.toDouble();
    final remaining = dur.inMilliseconds.toDouble() - posMs;
    var v = 1.0;
    if (remaining < fadeMs) {
      v = (remaining / fadeMs).clamp(0.0, 1.0);
    } else if (posMs < fadeMs) {
      v = (posMs / fadeMs).clamp(0.0, 1.0);
    }
    if ((player.volume - v).abs() > 0.02) player.setVolume(v);
  }
}
