import 'dart:async';
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
                      // Full-height portrait windows get the showcase
                      // layout: artwork filling the top half of the
                      // page, melting into the controls through a
                      // vignette. Short windows (split-screen, pop-up)
                      // keep the compact scrolling layout below.
                      if (cons.maxHeight >= 560) {
                        return _halfPagePlayer(context, svc, song, p, cons);
                      }
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

  /// Showcase portrait layout: the album artwork fills the top half
  /// of the page edge-to-edge, and a vignette fade melts its bottom
  /// into the page background, so the art and the player-button area
  /// below it feel like one continuous picture — no hard line.
  Widget _halfPagePlayer(
    BuildContext context,
    PlayerService svc,
    SongModel song,
    RetroPalette p,
    BoxConstraints cons,
  ) {
    final artH = cons.maxHeight * 0.5;
    return Column(
      children: [
        SizedBox(
          height: artH,
          width: cons.maxWidth,
          child: Stack(
            fit: StackFit.expand,
            children: [
              QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkWidth: cons.maxWidth,
                artworkHeight: artH,
                artworkBorder: BorderRadius.zero,
                nullArtworkWidget: Container(
                  width: cons.maxWidth,
                  height: artH,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [p.accent, p.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(Icons.music_note,
                      size: cons.maxWidth * 0.3, color: Colors.white70),
                ),
              ),
              // The vignette melt between art and controls.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      p.bgBottom.withOpacity(0.55),
                      p.bgBottom,
                    ],
                    stops: const [0.0, 0.50, 0.82, 1.0],
                  ),
                ),
              ),
              // Gentle side shading, so the art feels lit from centre.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.16),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.16),
                    ],
                    stops: const [0.0, 0.18, 0.82, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: CastService.instance.connected,
                  builder: (context, casting, _) => casting
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Chip(
                            avatar: Icon(Icons.cast_connected,
                                color: p.accent2, size: 18),
                            label: const Text(
                                'Casting — tap the cast icon to stop'),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
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
                  style: TextStyle(color: p.textDim, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'On this device • ${song.fileExtension?.toUpperCase() ?? 'AUDIO'}',
                  style: TextStyle(color: p.textDim, fontSize: 12),
                ),
                const Spacer(),
                _progress(svc, song, p),
                const SizedBox(height: 8),
                _controls(svc, p),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LyricsScreen(song: song),
                        ),
                      ),
                      icon: Icon(Icons.lyrics_outlined, color: p.accent2),
                      label:
                          Text('Lyrics', style: TextStyle(color: p.accent2)),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EqualizerScreen(),
                        ),
                      ),
                      icon: Icon(Icons.graphic_eq, color: p.accent2),
                      label: Text('Equalizer',
                          style: TextStyle(color: p.accent2)),
                    ),
                    Text(
                      '${(svc.player.currentIndex ?? 0) + 1} / ${svc.queue.length}',
                      style: TextStyle(color: p.textDim, fontSize: 12),
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
        return Column(
          children: [
            WavyProgressBar(svc: svc, palette: p, total: total),
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
                LayoutBuilder(
                  builder: (context, c) {
                    // The artwork scales with the pane it actually
                    // gets — in split-screen multitasking the pane
                    // can be much narrower than the full display.
                    final art = (c.maxWidth - 48).clamp(150.0, 300.0);
                    return QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      artworkWidth: art,
                      artworkHeight: art,
                      artworkBorder: BorderRadius.circular(20),
                      nullArtworkWidget: Container(
                        width: art,
                        height: art,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [p.accent, p.accent2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(Icons.music_note,
                            size: art * 0.4, color: Colors.white70),
                      ),
                    );
                  },
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
                    return Column(
                      children: [
                        WavyProgressBar(
                          svc: svc,
                          palette: p,
                          total: Duration(milliseconds: totalMs ?? 0),
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

/// Samsung-style wavy progress line: the played part of the timeline
/// ripples like a wave while music plays (and calms down when paused),
/// with a glowing knob. Tap or drag anywhere on it to seek.
class WavyProgressBar extends StatefulWidget {
  final PlayerService svc;
  final RetroPalette palette;
  final Duration total;

  const WavyProgressBar({
    super.key,
    required this.svc,
    required this.palette,
    required this.total,
  });

  @override
  State<WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<WavyProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  StreamSubscription<PlayerState>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.svc.player.playing) _wave.repeat();
    _sub = widget.svc.player.playerStateStream.listen((s) {
      if (s.playing && !_wave.isAnimating) {
        _wave.repeat();
      } else if (!s.playing && _wave.isAnimating) {
        _wave.stop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wave.dispose();
    super.dispose();
  }

  void _seekTo(double dx, double width) {
    final totalMs = widget.total.inMilliseconds;
    if (totalMs <= 0 || width <= 0) return;
    final frac = (dx / width).clamp(0.0, 1.0);
    widget.svc.player
        .seek(Duration(milliseconds: (frac * totalMs).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return StreamBuilder<Duration>(
          stream: widget.svc.player.positionStream,
          builder: (context, snap) {
            final pos = snap.data ?? Duration.zero;
            final totalMs = widget.total.inMilliseconds;
            final frac = totalMs <= 0
                ? 0.0
                : (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seekTo(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) =>
                  _seekTo(d.localPosition.dx, width),
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => CustomPaint(
                  size: const Size(double.infinity, 30),
                  painter: _WavePainter(
                    progress: frac,
                    phase: _wave.value * 2 * math.pi,
                    playing: widget.svc.player.playing,
                    accent: widget.palette.accent,
                    track: widget.palette.card,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final double phase;
  final bool playing;
  final Color accent;
  final Color track;

  const _WavePainter({
    required this.progress,
    required this.phase,
    required this.playing,
    required this.accent,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final w = size.width;
    final px = (progress * w).clamp(0.0, w);
    final amp = playing ? 4.2 : 1.1;

    double waveY(double x) {
      final taper = x < 14 ? x / 14 : 1.0;
      return mid + math.sin(x / 16 + phase) * amp * taper;
    }

    // Remaining track: a calm straight line.
    canvas.drawLine(
      Offset(px, mid),
      Offset(w, mid),
      Paint()
        ..color = track
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Played part: the animated wave.
    if (px > 0) {
      final path = Path()..moveTo(0, waveY(0));
      for (double x = 4; x <= px; x += 4) {
        path.lineTo(x, waveY(x));
      }
      path.lineTo(px, waveY(px));
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 3.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Glowing knob riding the wave.
    final ky = px > 0 ? waveY(px) : mid;
    canvas.drawCircle(
        Offset(px, ky), 11, Paint()..color = accent.withOpacity(0.30));
    canvas.drawCircle(Offset(px, ky), 7, Paint()..color = accent);
    canvas.drawCircle(Offset(px, ky), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.playing != playing ||
      old.accent != accent;
}
