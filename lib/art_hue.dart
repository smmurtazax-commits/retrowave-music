import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'media_query.dart';

/// The dominant hue of the current song's album artwork, extracted
/// on the phone. While a song with artwork is loaded, every page
/// blends its theme colors toward this hue — the app quietly wears
/// the colors of whatever is playing. Null keeps the pure theme.
final ValueNotifier<Color?> artHue = ValueNotifier<Color?>(null);

final Map<int, Color?> _hueCache = <int, Color?>{};
int _lastKey = -1;

/// Extracts (or recalls) the artwork hue for [song] and publishes it.
Future<void> updateArtHue(SongModel? song) async {
  if (song == null) {
    _lastKey = -1;
    artHue.value = null;
    return;
  }
  final albumKey = song.albumId;
  final key = albumKey ?? song.id;
  _lastKey = key;
  if (_hueCache.containsKey(key)) {
    artHue.value = _hueCache[key];
    return;
  }
  try {
    final bytes = albumKey != null
        ? await QueryArtworkWidget.artworkBytes(ArtworkType.ALBUM, albumKey)
        : await QueryArtworkWidget.artworkBytes(ArtworkType.AUDIO, song.id);
    if (bytes == null || bytes.isEmpty) {
      _hueCache[key] = null;
      if (_lastKey == key) artHue.value = null;
      return;
    }
    final generated = await PaletteGenerator.fromImageProvider(
      MemoryImage(bytes),
      maximumColorCount: 12,
    );
    final color =
        (generated.vibrantColor ?? generated.dominantColor)?.color;
    _hueCache[key] = color;
    // A fast skip may have moved on while we were extracting — only
    // publish if this song is still the latest request.
    if (_lastKey == key) artHue.value = color;
  } catch (_) {
    _hueCache[key] = null;
    if (_lastKey == key) artHue.value = null;
  }
}
