
import 'dart:convert';

import 'package:flutter/material.dart';
import 'media_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';
import 'themes.dart';

String _fmtDuration(int? ms) {
  if (ms == null) return '';
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// A user playlist: a name plus an ordered list of song ids.
class Playlist {
  final String id;
  String name;
  List<int> songIds;

  Playlist({required this.id, required this.name, required this.songIds});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'songIds': songIds,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        // Tolerant: one odd value (a double from another format)
        // must not throw and cost every other playlist.
        songIds: (j['songIds'] as List)
            .map((e) => e is num ? e.toInt() : int.tryParse('$e'))
            .whereType<int>()
            .toList(),
      );
}

/// The most recently scanned library, so playlists and favourites can
/// resolve song ids to songs from anywhere in the app.
class LibraryData {
  static List<SongModel> songs = <SongModel>[];

  static Map<int, SongModel> get byId => <int, SongModel>{
        for (final s in songs) s.id: s,
      };

  static List<SongModel> resolve(List<int> ids) =>
      ids.map((id) => byId[id]).whereType<SongModel>().toList();
}

/// Playlists + favourites, persisted locally on the phone.
class PlaylistStore {
  PlaylistStore._();
  static final PlaylistStore instance = PlaylistStore._();

  final ValueNotifier<List<Playlist>> playlists =
      ValueNotifier<List<Playlist>>(<Playlist>[]);
  final ValueNotifier<Set<int>> favourites = ValueNotifier<Set<int>>(<int>{});

  Future<void> load(SharedPreferences prefs) async {
    final raw = prefs.getString('playlists');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        // Decode entry by entry: one malformed record used to fail
        // the whole list and make every playlist look deleted.
        final decoded = <Playlist>[];
        for (final e in list) {
          try {
            decoded.add(Playlist.fromJson(e as Map<String, dynamic>));
          } catch (_) {
            // Skip only the bad record.
          }
        }
        playlists.value = decoded;
      } catch (_) {
        // Corrupt storage should never block the app.
      }
    }
    final favs = prefs.getStringList('favourites');
    if (favs != null) {
      favourites.value = favs.map(int.tryParse).whereType<int>().toSet();
    }
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'playlists',
      jsonEncode(playlists.value.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'favourites',
      favourites.value.map((e) => e.toString()).toList(),
    );
  }

  Playlist create(String name) {
    final pl = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      songIds: <int>[],
    );
    playlists.value = <Playlist>[...playlists.value, pl];
    _savePlaylists();
    return pl;
  }

  void rename(String id, String name) {
    final pl = playlists.value.firstWhere((p) => p.id == id);
    pl.name = name;
    playlists.value = <Playlist>[...playlists.value];
    _savePlaylists();
  }

  void delete(String id) {
    playlists.value = playlists.value.where((p) => p.id != id).toList();
    _savePlaylists();
  }

  /// Returns false when the song was already in the playlist and the
  /// "no duplicates" setting kept it out.
  bool addSong(String playlistId, int songId) {
    final pl = playlists.value.firstWhere((p) => p.id == playlistId);
    if (SettingsStore.instance.noDuplicates.value &&
        pl.songIds.contains(songId)) {
      return false;
    }
    pl.songIds = <int>[...pl.songIds, songId];
    playlists.value = <Playlist>[...playlists.value];
    _savePlaylists();
    return true;
  }

  void removeSong(String playlistId, int songId) {
    final pl = playlists.value.firstWhere((p) => p.id == playlistId);
    pl.songIds = pl.songIds.where((s) => s != songId).toList();
    playlists.value = <Playlist>[...playlists.value];
    _savePlaylists();
  }

  bool isFavourite(int songId) => favourites.value.contains(songId);

  void toggleFavourite(int songId) {
    final next = Set<int>.of(favourites.value);
    if (next.contains(songId)) {
      next.remove(songId);
    } else {
      next.add(songId);
    }
    favourites.value = next;
    _saveFavourites();
  }
}

// ---------------------------------------------------------------------
// Shared UI helpers
// ---------------------------------------------------------------------

Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // The dialog is gone; its text controller goes with it (it used to
  // leak one per dialog).
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}

/// The ⋮ actions for a song: play, add to playlist, favourite.
Future<void> showSongActions(
  BuildContext context,
  SongModel song, {
  required Future<void> Function() onPlay,
}) async {
  final store = PlaylistStore.instance;
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkWidth: 44,
              artworkHeight: 44,
              artworkBorder: BorderRadius.circular(6),
              nullArtworkWidget:
                  Icon(Icons.music_note, color: palette.accent2),
            ),
            title: Text(song.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artist ?? 'Unknown artist',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Play now'),
            onTap: () {
              Navigator.of(context).pop();
              onPlay();
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add to playlist…'),
            onTap: () {
              Navigator.of(context).pop();
              showAddToPlaylist(context, song);
            },
          ),
          ListTile(
            leading: Icon(
              store.isFavourite(song.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: store.isFavourite(song.id) ? palette.accent : null,
            ),
            title: Text(store.isFavourite(song.id)
                ? 'Remove from Favourites'
                : 'Add to Favourites'),
            onTap: () {
              store.toggleFavourite(song.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> showAddToPlaylist(BuildContext context, SongModel song) async {
  final store = PlaylistStore.instance;
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ValueListenableBuilder<List<Playlist>>(
        valueListenable: store.playlists,
        builder: (context, lists, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await askName(context, title: 'New playlist');
                if (name == null || !context.mounted) return;
                final pl = store.create(name);
                final added = store.addSong(pl.id, song.id);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(added
                        ? 'Added to $name'
                        : 'Already in $name'),
                  ),
                );
              },
            ),
            const Divider(),
            if (lists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No playlists yet'),
              ),
            for (final pl in lists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(pl.name),
                subtitle: Text('${pl.songIds.length} songs'),
                onTap: () {
                  final added = store.addSong(pl.id, song.id);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(added
                          ? 'Added to ${pl.name}'
                          : 'Already in ${pl.name}'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _songTile(
  SongModel s, {
  Widget? trailing,
  required VoidCallback onTap,
}) {
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
      '${s.artist ?? 'Unknown artist'} • ${_fmtDuration(s.duration)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: trailing,
    onTap: onTap,
  );
}

// ---------------------------------------------------------------------
// Tabs and screens
// ---------------------------------------------------------------------

typedef PlayCallback = Future<void> Function(List<SongModel>, int);

/// Grid (rows & columns) version of a song list, shown when the
/// grid-view option is on: big artwork cards instead of rows.
/// [onRemove], when given, puts a small remove button on each card.
class SongGrid extends StatelessWidget {
  final List<SongModel> songs;
  final void Function(List<SongModel>, int) onPlay;
  final void Function(SongModel)? onRemove;
  final IconData removeIcon;

  const SongGrid({
    super.key,
    required this.songs,
    required this.onPlay,
    this.onRemove,
    this.removeIcon = Icons.remove_circle_outline,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.74,
      ),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final s = songs[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onPlay(songs, i),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) => QueryArtworkWidget(
                        id: s.id,
                        type: ArtworkType.AUDIO,
                        artworkWidth: c.maxWidth,
                        artworkHeight: c.maxWidth,
                        artworkBorder: BorderRadius.circular(12),
                        nullArtworkWidget: Container(
                          width: c.maxWidth,
                          height: c.maxWidth,
                          decoration: BoxDecoration(
                            color: palette.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.music_note,
                              color: palette.accent2, size: 40),
                        ),
                      ),
                    ),
                    if (onRemove != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: Icon(removeIcon,
                              color: Colors.white,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 5),
                              ]),
                          tooltip: 'Remove',
                          onPressed: () => onRemove!(s),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  s.artist ?? 'Unknown artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlaylistsTab extends StatelessWidget {
  final PlayCallback onPlay;
  const PlaylistsTab({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsStore.instance.gridView,
      builder: (context, grid, _) {
        if (grid) {
          return ValueListenableBuilder<List<Playlist>>(
            valueListenable: store.playlists,
            builder: (context, lists, _) => _playlistsGrid(context, lists),
          );
        }
        return ValueListenableBuilder<List<Playlist>>(
      valueListenable: store.playlists,
      builder: (context, lists, _) => ListView(
        children: [
          ListTile(
            leading: Icon(Icons.add_circle, color: palette.accent),
            title: const Text('New playlist'),
            onTap: () async {
              final name = await askName(context, title: 'New playlist');
              if (name != null) store.create(name);
            },
          ),
          const Divider(),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "No playlists yet.\nCreate one, then add songs from any song's ⋮ menu.",
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textDim),
              ),
            ),
          for (final pl in lists)
            ListTile(
              leading: Icon(Icons.queue_music, color: palette.accent2),
              title: Text(pl.name),
              subtitle: Text('${pl.songIds.length} songs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlaylistDetailScreen(playlistId: pl.id, onPlay: onPlay),
                ),
              ),
            ),
        ],
      ),
    );
      },
    );
  }

  Widget _playlistsGrid(BuildContext context, List<Playlist> lists) {
    final store = PlaylistStore.instance;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.02,
      ),
      itemCount: lists.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _gridCard(
            icon: Icons.add_circle,
            title: 'New playlist',
            subtitle: 'Tap to create',
            onTap: () async {
              final name = await askName(context, title: 'New playlist');
              if (name != null) store.create(name);
            },
          );
        }
        final pl = lists[i - 1];
        return _gridCard(
          icon: Icons.queue_music,
          title: pl.name,
          subtitle: '${pl.songIds.length} songs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PlaylistDetailScreen(playlistId: pl.id, onPlay: onPlay),
            ),
          ),
        );
      },
    );
  }

  Widget _gridCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: palette.accent2, size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;
  final PlayCallback onPlay;
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ValueListenableBuilder<List<Playlist>>(
      valueListenable: store.playlists,
      builder: (context, lists, _) {
        final matches = lists.where((p) => p.id == playlistId);
        if (matches.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Playlist deleted')),
          );
        }
        final pl = matches.first;
        final songs = LibraryData.resolve(pl.songIds);
        return Scaffold(
          appBar: AppBar(
            title: Text(pl.name),
            backgroundColor: Colors.transparent,
            actions: [
              if (songs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_circle_fill),
                  tooltip: 'Play all',
                  onPressed: () => onPlay(songs, 0),
                ),
            ],
          ),
          body: songs.isEmpty
              ? Center(
                  child: Text(
                    'No songs in this playlist yet',
                    style: TextStyle(color: palette.textDim),
                  ),
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: SettingsStore.instance.gridView,
                  builder: (context, grid, _) => grid
                      ? SongGrid(
                          songs: songs,
                          onPlay: onPlay,
                          onRemove: (s) => store.removeSong(pl.id, s.id),
                        )
                      : ListView.builder(
                          itemCount: songs.length,
                          itemBuilder: (context, i) {
                            final s = songs[i];
                            return _songTile(
                              s,
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.remove_circle_outline),
                                tooltip: 'Remove from playlist',
                                onPressed: () =>
                                    store.removeSong(pl.id, s.id),
                              ),
                              onTap: () => onPlay(songs, i),
                            );
                          },
                        ),
                ),
        );
      },
    );
  }
}

class FavouritesTab extends StatelessWidget {
  final PlayCallback onPlay;
  const FavouritesTab({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: store.favourites,
      builder: (context, favs, _) {
        final songs =
            LibraryData.songs.where((s) => favs.contains(s.id)).toList();
        if (songs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "No favourites yet.\nOpen any song's ⋮ menu and tap “Add to Favourites”.",
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textDim),
              ),
            ),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsStore.instance.gridView,
          builder: (context, grid, _) => grid
              ? SongGrid(
                  songs: songs,
                  onPlay: onPlay,
                  onRemove: (s) => store.toggleFavourite(s.id),
                  removeIcon: Icons.favorite,
                )
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, i) {
                    final s = songs[i];
                    return _songTile(
                      s,
                      trailing: IconButton(
                        icon: Icon(Icons.favorite, color: palette.accent),
                        tooltip: 'Remove from Favourites',
                        onPressed: () => store.toggleFavourite(s.id),
                      ),
                      onTap: () => onPlay(songs, i),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Manage playlists: create, rename, delete (Settings → Manage playlists).
class ManagePlaylistsScreen extends StatelessWidget {
  const ManagePlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage playlists'),
        backgroundColor: Colors.transparent,
      ),
      body: ValueListenableBuilder<List<Playlist>>(
        valueListenable: store.playlists,
        builder: (context, lists, _) => ListView(
          children: [
            ListTile(
              leading: Icon(Icons.add_circle, color: palette.accent),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await askName(context, title: 'New playlist');
                if (name != null) store.create(name);
              },
            ),
            const Divider(),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No playlists yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textDim),
                ),
              ),
            for (final pl in lists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(pl.name),
                subtitle: Text('${pl.songIds.length} songs'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () async {
                        final name = await askName(
                          context,
                          title: 'Rename playlist',
                          initial: pl.name,
                        );
                        if (name != null) store.rename(pl.id, name);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete playlist?'),
                            content: Text(
                                '“${pl.name}” will be deleted. The songs themselves stay on your phone.'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) store.delete(pl.id);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
