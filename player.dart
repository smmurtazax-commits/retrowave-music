import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'media_query.dart';

import 'art_hue.dart';
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

  /// Completed by main() once the background-playback setup has run
  /// (or timed out). Playback waits for it — briefly — because the
  /// player must never be used before that setup finishes.
  final Completer<void> _initGate = Completer<void>();
  void completeInit() {
    if (!_initGate.isCompleted) _initGate.complete();
  }

  Future<void> _ready() async {
    try {
      await _initGate.future.timeout(const Duration(seconds: 3),
          onTimeout: () {});
    } catch (_) {}
  }

  /// A user-visible playback problem ("That song couldn't be played"),
  /// or null. The library shows it as a small message instead of the
  /// old behaviour: failing silently and sitting at 0:00.
  final ValueNotifier<String?> playbackError = ValueNotifier<String?>(null);

  List<AudioSource> _sourcesFor(List<SongModel> songs,
      {required bool filePaths}) {
    return songs.map((s) {
      final Uri uri;
      if (!filePaths && s.uri != null && s.uri!.isNotEmpty) {
        uri = Uri.parse(s.uri!);
      } else {
        uri = Uri.file(s.data);
      }
      // No artUri on purpose (build #11): a media-store artwork
      // address rides along with every song's load, and a bad one can
      // poison the load itself on some phones. The app still shows
      // artwork everywhere in its own UI; only the lock-screen /
      // notification picture is paused until playback is proven.
      return AudioSource.uri(
        uri,
        tag: MediaItem(
          id: s.id.toString(),
          title: s.title,
          artist: (s.artist == null || s.artist == '<unknown>')
              ? 'Unknown artist'
              : s.artist,
          album: s.album ?? '',
        ),
      );
    }).toList();
  }

  /// The most recent player-side error text, captured so a failure
  /// can be READ (in the message shown to the user) instead of
  /// guessed at. Set by the load ladder below and by the player's
  /// own error stream.
  String? lastPlayerError;

  String _shortError(Object e) {
    var s = e.toString().replaceAll('\n', ' ');
    if (s.length > 220) s = '${s.substring(0, 220)}…';
    return s;
  }

  Future<void> playQueue(List<SongModel> songs, int startIndex) async {
    _markSelf();
    await _ready();
    queue = List<SongModel>.of(songs);
    playbackError.value = null;
    lastPlayerError = null;
    Object? loadError;

    // Load ladder — each rung removes one suspect, and every refusal
    // is kept so the final message can quote the phone's own words:
    //   1. the whole queue via media-store addresses
    //   2. the whole queue via plain file paths
    //   3. just the tapped song on its own (no queue machinery)
    final attempts = <Future<void> Function()>[
      () => player.setAudioSource(
            ConcatenatingAudioSource(
                children: _sourcesFor(songs, filePaths: false)),
            initialIndex: startIndex,
          ),
      () => player.setAudioSource(
            ConcatenatingAudioSource(
                children: _sourcesFor(songs, filePaths: true)),
            initialIndex: startIndex,
          ),
      () => player.setAudioSource(
            _sourcesFor([songs[startIndex]], filePaths: false).single,
          ),
    ];
    var loadedRung = -1;
    for (var i = 0; i < attempts.length; i++) {
      try {
        await attempts[i]();
        loadedRung = i;
        break;
      } catch (e) {
        loadError = e;
        lastPlayerError = _shortError(e);
      }
    }
    if (loadedRung < 0) {
      playbackError.value = "That song couldn't be played. "
          'Reason: ${lastPlayerError ?? loadError}';
      return;
    }
    if (loadedRung == 2) {
      // The single-song rung loaded — shrink the queue to match what
      // the player actually holds, so Next/Previous and the current
      // song display stay truthful for this session.
      queue = [songs[startIndex]];
    }
    try {
      await player.play();
    } catch (e) {
      lastPlayerError = _shortError(e);
      playbackError.value = "That song couldn't be played. Reason: $lastPlayerError";
    }
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
    // Fire-and-forget, but never unhandled: on a player that is still
    // waking up these can refuse, and a refusal here must stay quiet.
    player
        .setSpeed(SettingsStore.instance.playSpeed.value)
        .catchError((_) {});
    player
        .setSkipSilenceEnabled(SettingsStore.instance.skipSilence.value)
        .catchError((_) {});
  }

  // --- Crossfade engine (fade out / fade in) + external-start guard ----

  Timer? _fadeTimer;

  void _initEngines() {
    // Keep the player's own error reports readable: when a load or
    // playback fails asynchronously, the platform's words land here
    // and in the message the user sees, instead of vanishing.
    player.playbackEventStream.listen((_) {}, onError: (Object e) {
      lastPlayerError = _shortError(e);
      if (playbackError.value == null) {
        playbackError.value =
            "That song couldn't be played. Reason: $lastPlayerError";
      }
    });
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
      updateArtHue(currentSong);
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
