import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'cast.dart';
import 'equalizer.dart';
import 'glass.dart';
import 'library.dart' show fmtDuration;
import 'lyrics.dart';
import 'player.dart';
import 'themes.dart';
import 'themes_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: appearanceVersion,
      builder: (context, _, __) {
        final p = palette;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              p.name,
              style: TextStyle(color: p.textDim, fontSize: 14),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.cast),
                tooltip: 'Cast to a device',
                onPressed: () => CastService.instance.onCastButton(
                  PlayerService.instance.queue,
                  PlayerService.instance.player.currentIndex ?? 0,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.palette_outlined),
                tooltip: 'Appearance',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemesScreen()),
                ),
              ),
            ],
          ),
          extendBodyBehindAppBar: true,
          body: ThemedBackground(
            palette: p,
            child: SafeArea(
              child: StreamBuilder<int?>(
                stream: svc.player.currentIndexStream,
                builder: (context, snap) {
                  final song = svc.currentSong;
                  if (song == null) {
                    return Center(
                      child: Text(
                        'Nothing playing',
                        style: TextStyle(color: p.textDim),
                      ),
                    );
                  }
                  // Responsive layout: the artwork scales with the window
                  // and the page scrolls when the window is short, so the
                  // screen stays usable in split-screen and pop-up view.
                  return LayoutBuilder(
                    builder: (context, cons) {
                      final artSize = math.min(
                        (cons.maxWidth * 0.64).clamp(120.0, 300.0),
                        (cons.maxHeight * 0.40).clamp(120.0, 300.0),
                      );
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: cons.maxHeight),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 8, 24, 16),
                              child: Column(
                                children: [
                                  const SizedBox(height: 8),
                                  ValueListenableBuilder<bool>(
                                    valueListenable:
                                        CastService.instance.connected,
                                    builder: (context, casting, _) => casting
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 10),
                                            child: Chip(
                                              avatar: Icon(
                                                  Icons.cast_connected,
                                                  color: p.accent2,
                                                  size: 18),
                                              label: const Text(
                                                  'Casting — tap the cast icon to stop'),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  _artwork(song, p, artSize),
                                  const SizedBox(height: 24),
                                  Text(
                                    song.title,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    song.artist ?? 'Unknown artist',
                                    style: TextStyle(
                                        color: p.textDim, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'On this device • ${song.fileExtension?.toUpperCase() ?? 'AUDIO'}',
                                    style: TextStyle(
                                        color: p.textDim, fontSize: 12),
                                  ),
                                  const Spacer(),
                                  _progress(svc, song, p),
                                  const SizedBox(height: 8),
                                  _controls(svc, p),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                LyricsScreen(song: song),
                                          ),
                                        ),
                                        icon: Icon(Icons.lyrics_outlined,
                                            color: p.accent2),
                                        label: Text('Lyrics',
                                            style:
                                                TextStyle(color: p.accent2)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const EqualizerScreen(),
                                          ),
                                        ),
                                        icon: Icon(Icons.graphic_eq,
                                            color: p.accent2),
                                        label: Text('Equalizer',
                                            style:
                                                TextStyle(color: p.accent2)),
                                      ),
                                      Text(
                                        '${(svc.player.currentIndex ?? 0) + 1} / ${svc.queue.length}',
                                        style: TextStyle(
                                            color: p.textDim, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _artwork(SongModel song, RetroPalette p, double size) {
    return QueryArtworkWidget(
      id: song.id,
      type: ArtworkType.AUDIO,
      artworkWidth: size,
      artworkHeight: size,
      artworkBorder: BorderRadius.circular(20),
      nullArtworkWidget: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [p.accent, p.accent2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.music_note,
            size: size * 0.4, color: Colors.white70),
      ),
    );
  }

  Widget _progress(PlayerService svc, SongModel song, RetroPalette p) {
    return StreamBuilder<Duration>(
      stream: svc.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final totalMs = song.duration ?? svc.player.duration?.inMilliseconds;
        final total = totalMs != null
            ? Duration(milliseconds: totalMs)
            : Duration.zero;
        final maxMs = total.inMilliseconds.toDouble();
        final valueMs =
            pos.inMilliseconds.toDouble().clamp(0.0, maxMs <= 0 ? 0.0 : maxMs);
        return Column(
          children: [
            Slider(
              value: maxMs <= 0 ? 0 : valueMs,
              max: maxMs <= 0 ? 1 : maxMs,
              activeColor: p.accent,
              inactiveColor: p.card,
              onChanged: (v) =>
                  svc.player.seek(Duration(milliseconds: v.round())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmtDuration(pos.inMilliseconds),
                    style: TextStyle(color: p.textDim, fontSize: 12)),
                Text(fmtDuration(totalMs),
                    style: TextStyle(color: p.textDim, fontSize: 12)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _controls(PlayerService svc, RetroPalette p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: svc.player.shuffleModeEnabledStream,
          builder: (context, snap) {
            final on = snap.data ?? false;
            return IconButton(
              icon: Icon(Icons.shuffle,
                  color: on ? p.accent : p.textDim, size: 24),
              onPressed: () => svc.player.setShuffleModeEnabled(!on),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 38),
          onPressed: () => svc.player.seekToPrevious(),
        ),
        StreamBuilder<PlayerState>(
          stream: svc.player.playerStateStream,
          builder: (context, snap) {
            final state = snap.data;
            final playing = state?.playing ?? false;
            final loading = state?.processingState == ProcessingState.loading ||
                state?.processingState == ProcessingState.buffering;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [p.accent, p.accent2]),
              ),
              child: IconButton(
                iconSize: 40,
                color: Colors.white,
                icon: loading
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () =>
                    playing ? svc.player.pause() : svc.userPlay(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 38),
          onPressed: () => svc.player.seekToNext(),
        ),
        StreamBuilder<LoopMode>(
          stream: svc.player.loopModeStream,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            return IconButton(
              icon: Icon(
                mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: mode != LoopMode.off ? p.accent : p.textDim,
                size: 24,
              ),
              onPressed: () {
                final next = mode == LoopMode.off
                    ? LoopMode.all
                    : mode == LoopMode.all
                        ? LoopMode.one
                        : LoopMode.off;
                svc.player.setLoopMode(next);
              },
            );
          },
        ),
      ],
    );
  }
}
