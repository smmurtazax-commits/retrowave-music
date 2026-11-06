import 'dart:io';
import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'media_query.dart';

import 'glass.dart';
import 'now_playing.dart';
import 'player.dart';
import 'playlists.dart';
import 'settings.dart';
import 'settings_store.dart';
import 'themes.dart';
import 'themes_screen.dart';

String fmtDuration(int? ms) {
  if (ms == null) return '';
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool _checking = true;
  bool _hasPermission = false;
  bool _loading = false;
  List<SongModel> _songs = <SongModel>[];
  List<AlbumModel> _albums = <AlbumModel>[];
  List<ArtistModel> _artists = <ArtistModel>[];
  int _tab = 0; // 0 Songs, 1 Albums, 2 Folders
  String _query = '';

  @override
  void initState() {
    super.initState();
    PlayerService.instance.playbackError.addListener(_showPlaybackError);
    _init();
  }

  @override
  void dispose() {
    PlayerService.instance.playbackError.removeListener(_showPlaybackError);
    super.dispose();
  }

  /// Playback problems used to fail silently (song stuck at 0:00).
  /// Now the user sees one small, honest message instead.
  void _showPlaybackError() {
    final msg = PlayerService.instance.playbackError.value;
    if (msg == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
      PlayerService.instance.playbackError.value = null;
    });
  }

  Future<void> _init() async {
    final ok = await _audioQuery.permissionsStatus();
    if (!mounted) return;
    setState(() {
      _hasPermission = ok;
      _checking = false;
    });
    if (ok) await _load();
  }

  Future<void> _requestPermission() async {
    final ok = await _audioQuery.permissionsRequest();
    if (!mounted) return;
    setState(() => _hasPermission = ok);
    if (ok) await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    final albums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    final artists = await _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _albums = albums;
      _artists = artists;
      _loading = false;
    });
    LibraryData.songs = songs;
  }

  List<SongModel> get _filteredSongs {
    if (_query.isEmpty) return _songs;
    final q = _query.toLowerCase();
    return _songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            (s.artist ?? '').toLowerCase().contains(q) ||
            (s.album ?? '').toLowerCase().contains(q))
        .toList();
  }

  Map<String, List<SongModel>> get _folders {
    final map = <String, List<SongModel>>{};
    for (final s in _songs) {
      final parent = File(s.data).parent.path;
      map.putIfAbsent(parent, () => <SongModel>[]).add(s);
    }
    return map;
  }

  Future<void> _playFrom(List<SongModel> list, int index) async {
    final store = SettingsStore.instance;
    var effective = list;
    var start = index;
    if (store.queueMode.value == 'single') {
      effective = <SongModel>[list[index]];
      start = 0;
    } else if (store.noDuplicates.value) {
      final seen = <int>{};
      final deduped = <SongModel>[];
      for (final s in list) {
        if (seen.add(s.id)) deduped.add(s);
      }
      start = deduped.indexWhere((s) => s.id == list[index].id);
      if (start < 0) start = 0;
      effective = deduped;
    }
    await PlayerService.instance.playQueue(effective, start);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appearanceVersion,
      builder: (context, _, __) {
        final p = palette;
        return Scaffold(
          body: ThemedBackground(
            palette: p,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, cons) {
                  final column = Column(
                    children: [
                      _header(p),
                  if (_hasPermission && !_checking) _sourceSwitch(p),
                  if (_hasPermission && !_checking) _searchField(p),
                  if (_hasPermission && !_checking)
                    ValueListenableBuilder<List<String>>(
                      valueListenable: SettingsStore.instance.enabledTabs,
                      builder: (context, _, __) => _chips(p),
                    ),
                  Expanded(
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: SettingsStore.instance.enabledTabs,
                      builder: (context, _, __) => _body(p),
                    ),
                  ),
                      const MiniPlayer(),
                    ],
                  );
                  // Wide screens (Fold inner display, tablets): two
                  // panes — library on the left, the player on the
                  // right — instead of one stretched phone column.
                  if (cons.maxWidth < 600) return column;
                  // Proper foldable behaviour (Jetpack WindowManager
                  // display features, surfaced by Flutter): when the
                  // phone reports a vertical hinge, split the panes
                  // exactly at the hinge instead of a fixed width.
                  var paneWidth = 400.0;
                  for (final f in MediaQuery.of(context).displayFeatures) {
                    if (f.type == DisplayFeatureType.hinge &&
                        f.bounds.height > f.bounds.width) {
                      final w = cons.maxWidth - f.bounds.left;
                      if (w >= 328 && w <= 560) paneWidth = w;
                    }
                  }
                  return Row(
                    children: [
                      Expanded(child: column),
                      Container(width: 1, color: p.card.withOpacity(0.6)),
                      SizedBox(width: paneWidth, child: const NowPlayingPane()),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(RetroPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Icon(Icons.album, color: p.accent, size: 28),
          const SizedBox(width: 8),
          const Text(
            'RetroWave',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_hasPermission)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan library',
              onPressed: _loading ? null : _load,
            ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Appearance',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceSwitch(RetroPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('On This Device'),
            selected: true,
            onSelected: (_) {},
            selectedColor: p.accent.withOpacity(0.35),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Amazon Music'),
            selected: false,
            onSelected: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Streaming sign-in is part of the design concept only — this build plays the music on your phone.'),
                ),
              );
            },
          ),
          const Spacer(),
          if (!_loading)
            Text(
              '${_songs.length} songs',
              style: TextStyle(color: p.textDim, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _searchField(RetroPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search songs, artists, albums',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          fillColor: p.card.withOpacity(0.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  Widget _chips(RetroPalette p) {
    final tabs = SettingsStore.instance.enabledTabs.value;
    final current = _tab.clamp(0, tabs.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              ChoiceChip(
                label: Text(tabLabels[tabs[i]] ?? tabs[i]),
                selected: current == i,
                onSelected: (_) => setState(() => _tab = i),
                selectedColor: p.accent.withOpacity(0.35),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(RetroPalette p) {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasPermission) {
      return _permissionScreen(p);
    }
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Scanning your music…', style: TextStyle(color: p.textDim)),
          ],
        ),
      );
    }
    final tabs = SettingsStore.instance.enabledTabs.value;
    final id = tabs[_tab.clamp(0, tabs.length - 1)];
    switch (id) {
      case 'albums':
        return _albumsList(p);
      case 'artists':
        return _artistsList(p);
      case 'folders':
        return _foldersList(p);
      case 'playlists':
        return PlaylistsTab(onPlay: _playFrom);
      case 'favourites':
        return FavouritesTab(onPlay: _playFrom);
      default:
        if (_songs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No music files found on this device yet.\nAdd songs to the phone and tap rescan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textDim),
              ),
            ),
          );
        }
        return _songsList(_filteredSongs);
    }
  }

  Widget _permissionScreen(RetroPalette p) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 72, color: p.accent),
            const SizedBox(height: 20),
            const Text(
              'Play Device Files',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'RetroWave plays the music already stored on this phone — no sign-in needed. Allow access so it can scan your library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textDim, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _requestPermission,
              style: FilledButton.styleFrom(backgroundColor: p.accent),
              child: const Text('Allow access & scan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _songsList(List<SongModel> songs) {
    if (songs.isEmpty) {
      return const Center(child: Text('No matches'));
    }
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final s = songs[i];
        return ListTile(
          leading: QueryArtworkWidget(
            id: s.id,
            type: ArtworkType.AUDIO,
            artworkWidth: 48,
            artworkHeight: 48,
            artworkBorder: BorderRadius.circular(8),
            nullArtworkWidget: _artPlaceholder(),
          ),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${s.artist ?? 'Unknown artist'} • ${fmtDuration(s.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showSongActions(
              context,
              s,
              onPlay: () => _playFrom(songs, i),
            ),
          ),
          onTap: () => _playFrom(songs, i),
        );
      },
    );
  }

  Widget _albumsList(RetroPalette p) {
    return ListView.builder(
      itemCount: _albums.length,
      itemBuilder: (context, i) {
        final a = _albums[i];
        return ListTile(
          leading: QueryArtworkWidget(
            id: a.id,
            type: ArtworkType.ALBUM,
            artworkWidth: 48,
            artworkHeight: 48,
            artworkBorder: BorderRadius.circular(8),
            nullArtworkWidget: _artPlaceholder(),
          ),
          title: Text(a.album, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${a.artist ?? 'Unknown artist'} • ${a.numOfSongs} songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () async {
            final songs = await _audioQuery.queryAudiosFrom(
              AudiosFromType.ALBUM_ID,
              a.id,
            );
            if (!mounted || songs.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: a.album,
                  songs: songs,
                  onPlay: _playFrom,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _artistsList(RetroPalette p) {
    return ListView.builder(
      itemCount: _artists.length,
      itemBuilder: (context, i) {
        final a = _artists[i];
        return ListTile(
          leading: QueryArtworkWidget(
            id: a.id,
            type: ArtworkType.ARTIST,
            artworkWidth: 48,
            artworkHeight: 48,
            artworkBorder: BorderRadius.circular(24),
            nullArtworkWidget: CircleAvatar(
              backgroundColor: p.card,
              child: Icon(Icons.person, color: p.accent2),
            ),
          ),
          title: Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${a.numberOfTracks ?? 0} tracks • ${a.numberOfAlbums ?? 0} albums',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () async {
            final songs = await _audioQuery.queryAudiosFrom(
              AudiosFromType.ARTIST_ID,
              a.id,
            );
            if (!mounted || songs.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SongListScreen(
                  title: a.artist,
                  songs: songs,
                  onPlay: _playFrom,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _foldersList(RetroPalette p) {
    final folders = _folders;
    final keys = folders.keys.toList()..sort();
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final path = keys[i];
        final name = path.split('/').last.isEmpty ? path : path.split('/').last;
        final songs = folders[path]!;
        return ListTile(
          leading: Icon(Icons.folder, color: p.accent2, size: 40),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${songs.length} songs'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SongListScreen(
                title: name,
                songs: songs,
                onPlay: _playFrom,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _artPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note, color: palette.accent2),
    );
  }
}

/// A simple song list screen (used for albums and folders).
class SongListScreen extends StatelessWidget {
  final String title;
  final List<SongModel> songs;
  final Future<void> Function(List<SongModel>, int) onPlay;

  const SongListScreen({
    super.key,
    required this.title,
    required this.songs,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, i) {
          final s = songs[i];
          return ListTile(
            leading: QueryArtworkWidget(
              id: s.id,
              type: ArtworkType.AUDIO,
              artworkWidth: 48,
              artworkHeight: 48,
              artworkBorder: BorderRadius.circular(8),
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note, color: palette.accent2),
              ),
            ),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${s.artist ?? 'Unknown artist'} • ${fmtDuration(s.duration)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => showSongActions(
                context,
                s,
                onPlay: () => onPlay(songs, i),
              ),
            ),
            onTap: () => onPlay(songs, i),
          );
        },
      ),
    );
  }
}

/// Bottom mini-player shown on the library screens.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;
    return StreamBuilder<int?>(
      stream: svc.player.currentIndexStream,
      builder: (context, snap) {
        final song = svc.currentSong;
        if (song == null) return const SizedBox.shrink();
        final p = palette;
        return Material(
          color: p.card.withOpacity(0.92),
          child: ListTile(
            leading: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkWidth: 44,
              artworkHeight: 44,
              artworkBorder: BorderRadius.circular(6),
              nullArtworkWidget: Icon(Icons.music_note, color: p.accent2),
            ),
            title:
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              song.artist ?? 'Unknown artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: StreamBuilder<PlayerState>(
              stream: svc.player.playerStateStream,
              builder: (context, s2) {
                final playing = s2.data?.playing ?? false;
                return IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () =>
                      playing ? svc.player.pause() : svc.userPlay(),
                );
              },
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
            ),
          ),
        );
      },
    );
  }
}
