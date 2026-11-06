import 'package:flutter/services.dart';

/// Bridge to the phone's built-in audio effects engine (Android audiofx),
/// wired to the player's audio session from Kotlin in MainActivity.
///
/// This gives the app a real equalizer, bass boost and virtualizer on any
/// Android phone — using the phone's own audio hardware support.
class AudioFx {
  static const MethodChannel _ch = MethodChannel('retrowave/audiofx');

  static Future<bool> init(int sessionId) async {
    try {
      final ok =
          await _ch.invokeMethod<bool>('init', {'sessionId': sessionId});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns band count, level range (millibels), center freqs (millihertz),
  /// current levels and preset names — or null if unavailable.
  static Future<Map<String, dynamic>?> info() async {
    try {
      final res = await _ch.invokeMethod<Map<dynamic, dynamic>>('info');
      if (res == null) return null;
      return res.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setBandLevel(int band, int levelMillibels) async {
    try {
      await _ch.invokeMethod('setBandLevel', {
        'band': band,
        'level': levelMillibels,
      });
    } catch (_) {}
  }

  static Future<void> usePreset(int preset) async {
    try {
      await _ch.invokeMethod('usePreset', {'preset': preset});
    } catch (_) {}
  }

  /// strength: 0–1000 (0 = off)
  static Future<void> setBassBoost(int strength) async {
    try {
      await _ch.invokeMethod('setBassBoost', {'strength': strength});
    } catch (_) {}
  }

  /// strength: 0–1000 (0 = off)
  static Future<void> setVirtualizer(int strength) async {
    try {
      await _ch.invokeMethod('setVirtualizer', {'strength': strength});
    } catch (_) {}
  }

  /// Sets whether the playback controls may appear on the lock screen.
  /// Applied by creating the playback notification channel early with
  /// the chosen visibility, so it takes effect from the next app start.
  static Future<void> setLockScreenControls(bool on) async {
    try {
      await _ch.invokeMethod('setLockScreenControls', {'on': on});
    } catch (_) {}
  }

  /// Opens this app's page in the phone's system settings
  /// (where its permissions live).
  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// Opens the phone's own sound-effects panel (e.g. Samsung SoundAlive /
  /// Dolby Atmos page) or falls back to the system sound settings.
  /// System effects like Dolby Atmos and UHQ Upscaler are controlled by the
  /// phone, not by apps — when they are ON in phone settings they apply to
  /// RetroWave automatically, because RetroWave plays on the standard
  /// media audio stream.
  static Future<void> openSystemEffects() async {
    try {
      await _ch.invokeMethod('openSystemEffects');
    } catch (_) {}
  }
}
