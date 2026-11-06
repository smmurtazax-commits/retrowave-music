import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'media_query.dart';

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
                  // On wide windows (Fold inner display, tablets) the
                  // player splits in two: big artwork on the left, song
                  // info and controls on the right.
                  return LayoutBuilder(
                    builder: (context, cons) {
                      // Tabletop posture (Fold half-opened, standing on
                      // a surface): the fold API reports a horizontal
                      // hinge — artwork lives above it, controls below,
                      // so nothing important sits under the fold.
                      DisplayFeature? tabletopHinge;
                      for (final f in MediaQuery.of(context).displayFeatures) {
                        if (f.type == DisplayFeatureType.hinge &&
                            f.state == DisplayFeatureState.postureHalfOpened &&
                            f.bounds.width > f.bounds.height) {
                          tabletopHinge = f;
                          break;
                        }
                      }
                      final hinge = tabletopHinge;
                      if (hinge != null) {
                        final topH = hinge.bounds.top
                            .clamp(170.0, cons.maxHeight * 0.62);
                        final art = math
                            .min(topH * 0.8, cons.maxWidth * 0.5)
                            .clamp(140.0, 340.0);
                        return Column(
                          children: [
                            SizedBox(
                              height: topH,
                              child: Center(child: _artwork(song, p, art)),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 10, 24, 14),
                                  child: Column(
                                    children: [
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
                                      const SizedBox(height: 14),
                                      _progress(svc, song, p),
                                      const SizedBox(height: 8),
                                      _controls(svc, p),
                                      const SizedBox(height: 10),
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
                                                style: TextStyle(
                                                    color: p.accent2)),
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
                                                style: TextStyle(
                                                    color: p.accent2)),
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
                          ],
                        );
                      }
                      if (cons.maxWidth >= 600) {
                        final wideArt = math.min(
                          (cons.maxHeight * 0.66).clamp(200.0, 460.0),
                          (cons.maxWidth * 0.44).clamp(200.0, 460.0),
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: Center(child: _artwork(song, p, wideArt)),
                            ),
                            SizedBox(
                              width: 400,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 16, 28, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
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
                                    Text(
                                      song.title,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      song.artist ?? 'Unknown artist',
                                      style: TextStyle(
                                          color: p.textDim, fontSize: 18),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'On this device • ${song.fileExtension?.toUpperCase() ?? 'AUDIO'}',
                                      style: TextStyle(
                                          color: p.textDim, fontSize: 13),
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
                                              style: TextStyle(
                                                  color: p.accent2)),
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
                                              style: TextStyle(
                                                  color: p.accent2)),
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
                          ],
                        );
                      }
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

/// The right-hand pane shown next to the library on wide screens
/// (Fold inner display, tablets): the current song, large, with its
/// own progress and transport controls — so the unfolded screen is
/// used as a real two-pane layout instead of a stretched phone UI.
class NowPlayingPane extends StatelessWidget {
  const NowPlayingPane({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;
    final p = palette;
    return StreamBuilder<int?>(
      stream: svc.player.currentIndexStream,
      builder: (context, snap) {
        final song = svc.currentSong;
        if (song == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.album, size: 84, color: p.accent),
                  const SizedBox(height: 16),
                  const Text(
                    'RetroWave',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a song from the library — it plays here, full size.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textDim, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: p.textDim,
                    fontSize: 12,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 18),
                QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  artworkWidth: 280,
                  artworkHeight: 280,
                  artworkBorder: BorderRadius.circular(20),
                  nullArtworkWidget: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [p.accent, p.accent2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.music_note,
                        size: 112, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  song.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  song.artist ?? 'Unknown artist',
                  style: TextStyle(color: p.textDim, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                StreamBuilder<Duration>(
                  stream: svc.player.positionStream,
                  builder: (context, s2) {
                    final pos = s2.data ?? Duration.zero;
                    final totalMs =
                        song.duration ?? svc.player.duration?.inMilliseconds;
                    final maxMs =
                        (totalMs ?? 0).toDouble();
                    final valueMs = pos.inMilliseconds
                        .toDouble()
                        .clamp(0.0, maxMs <= 0 ? 0.0 : maxMs);
                    return Column(
                      children: [
                        Slider(
                          value: maxMs <= 0 ? 0 : valueMs,
                          max: maxMs <= 0 ? 1 : maxMs,
                          activeColor: p.accent,
                          inactiveColor: p.card,
                          onChanged: (v) => svc.player
                              .seek(Duration(milliseconds: v.round())),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fmtDuration(pos.inMilliseconds),
                                style: TextStyle(
                                    color: p.textDim, fontSize: 12)),
                            Text(fmtDuration(totalMs),
                                style: TextStyle(
                                    color: p.textDim, fontSize: 12)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 34),
                      onPressed: () => svc.player.seekToPrevious(),
                    ),
                    StreamBuilder<PlayerState>(
                      stream: svc.player.playerStateStream,
                      builder: (context, s3) {
                        final playing = s3.data?.playing ?? false;
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient:
                                LinearGradient(colors: [p.accent, p.accent2]),
                          ),
                          child: IconButton(
                            iconSize: 36,
                            color: Colors.white,
                            icon:
                                Icon(playing ? Icons.pause : Icons.play_arrow),
                            onPressed: () =>
                                playing ? svc.player.pause() : svc.userPlay(),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 34),
                      onPressed: () => svc.player.seekToNext(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NowPlayingScreen()),
                  ),
                  icon: Icon(Icons.open_in_full, color: p.accent2, size: 18),
                  label: Text('Open full player',
                      style: TextStyle(color: p.accent2)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
