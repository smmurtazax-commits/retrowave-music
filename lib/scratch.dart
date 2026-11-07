import 'package:flutter/services.dart';

import 'media_query.dart';

/// Bridge to the native real-time scratch engine (DJ Disc).
///
/// The phone's media player cannot play audio backwards, so the
/// native side decodes the song into memory as raw samples and
/// renders them with a playhead the finger drags in any direction:
/// forward fast, forward slow, held still, or backwards — with the
/// actual sound following in real time, like vinyl.
class Scratch {
  static const MethodChannel _ch = MethodChannel('retrowave/scratch');

  /// Decode the song into the engine's memory. Takes a moment;
  /// false means this file cannot be scratched (the disc then stays
  /// in its speed/pitch mode — nothing breaks).
  static Future<bool> prepare(SongModel song) async {
    try {
      return await _ch.invokeMethod<bool>('prepare', {
            'path': song.data,
            'uri': song.uri,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Start rendering from [startMs] into the song.
  static Future<bool> start(int startMs) async {
    try {
      return await _ch.invokeMethod<bool>('start', {'startMs': startMs}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Point the playhead: +1.0 normal speed, 0.0 held record,
  /// negative values spin the sound backwards.
  static Future<void> setRatio(double ratio) async {
    try {
      await _ch.invokeMethod('setRatio', {'ratio': ratio});
    } catch (_) {}
  }

  static Future<int> playheadMs() async {
    try {
      return await _ch.invokeMethod<int>('playhead') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> durationMs() async {
    try {
      return await _ch.invokeMethod<int>('duration') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Stop rendering; returns where the song had reached, in ms,
  /// so the normal player can pick up from exactly there.
  static Future<int> stop() async {
    try {
      return await _ch.invokeMethod<int>('stop') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> release() async {
    try {
      await _ch.invokeMethod('release');
    } catch (_) {}
  }
}
