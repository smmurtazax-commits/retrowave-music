import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'themes.dart';

/// Lyrics for local files.
///
/// Most music files stored on a phone do not carry synced lyrics inside
/// them, so — exactly as the design shows — this screen says so honestly
/// instead of faking a lyrics view.
class LyricsScreen extends StatelessWidget {
  final SongModel song;

  const LyricsScreen({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [p.bgTop, p.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lyrics_outlined, size: 56, color: p.textDim),
                const SizedBox(height: 16),
                Text(
                  song.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  song.artist ?? 'Unknown artist',
                  style: TextStyle(color: p.textDim),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  'Lyrics not available for local files',
                  style: TextStyle(color: p.textDim, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Lyrics are not stored inside most music files on this phone.',
                  style: TextStyle(color: p.textDim, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
