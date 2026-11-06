import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// RetroWave's own media-store layer.
///
/// This replaces the unmaintained `on_audio_query` plugin (its Android
/// module declares no `namespace`, so current Android Gradle Plugin
/// versions refuse to build it). The public surface used by the app —
/// [OnAudioQuery], the model classes, the sort/artwork enums and
/// [QueryArtworkWidget] — is kept identical; underneath, everything is
/// served by the native side over the `retrowave/media` channel
/// (MediaStore queries in MainActivity.kt).

const MethodChannel _channel = MethodChannel('retrowave/media');

enum SongSortType { TITLE }

enum AlbumSortType { ALBUM }

enum ArtistSortType { ARTIST }

enum OrderType { ASC_OR_SMALLER }

enum UriType { EXTERNAL }

enum AudiosFromType { ALBUM_ID, ARTIST_ID }

enum ArtworkType { AUDIO, ALBUM, ARTIST }

class SongModel {
  final int id;
  final String data;
  final String? uri;
  final String title;
  final String? artist;
  final String? album;
  final int? albumId;
  final int? duration;
  final String? fileExtension;

  const SongModel({
    required this.id,
    required this.data,
    this.uri,
    required this.title,
    this.artist,
    this.album,
    this.albumId,
    this.duration,
    this.fileExtension,
  });

  factory SongModel.fromMap(Map<dynamic, dynamic> m) => SongModel(
        id: (m['id'] as num).toInt(),
        data: m['data'] as String? ?? '',
        uri: m['uri'] as String?,
        title: m['title'] as String? ?? 'Unknown title',
        artist: m['artist'] as String?,
        album: m['album'] as String?,
        albumId: (m['albumId'] as num?)?.toInt(),
        duration: (m['duration'] as num?)?.toInt(),
        fileExtension: m['fileExtension'] as String?,
      );
}

class AlbumModel {
  final int id;
  final String album;
  final String? artist;
  final int numOfSongs;

  const AlbumModel({
    required this.id,
    required this.album,
    this.artist,
    required this.numOfSongs,
  });

  factory AlbumModel.fromMap(Map<dynamic, dynamic> m) => AlbumModel(
        id: (m['id'] as num).toInt(),
        album: m['album'] as String? ?? 'Unknown album',
        artist: m['artist'] as String?,
        numOfSongs: (m['numOfSongs'] as num?)?.toInt() ?? 0,
      );
}

class ArtistModel {
  final int id;
  final String artist;
  final int? numberOfTracks;
  final int? numberOfAlbums;

  const ArtistModel({
    required this.id,
    required this.artist,
    this.numberOfTracks,
    this.numberOfAlbums,
  });

  factory ArtistModel.fromMap(Map<dynamic, dynamic> m) => ArtistModel(
        id: (m['id'] as num).toInt(),
        artist: m['artist'] as String? ?? 'Unknown artist',
        numberOfTracks: (m['numberOfTracks'] as num?)?.toInt(),
        numberOfAlbums: (m['numberOfAlbums'] as num?)?.toInt(),
      );
}

/// Drop-in replacement for the plugin's query class. Sort parameters are
/// accepted for compatibility; the native side always returns title /
/// album / artist ascending, which is the only order the app requests.
class OnAudioQuery {
  Future<bool> permissionsStatus() async {
    final ok = await _channel.invokeMethod<bool>('permissionsStatus');
    return ok ?? false;
  }

  Future<bool> permissionsRequest() async {
    final ok = await _channel.invokeMethod<bool>('permissionsRequest');
    return ok ?? false;
  }

  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool ignoreCase = true,
  }) async {
    final rows = await _channel.invokeMethod<List<dynamic>>('querySongs');
    return _toSongs(rows);
  }

  Future<List<AlbumModel>> queryAlbums({
    AlbumSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool ignoreCase = true,
  }) async {
    final rows = await _channel.invokeMethod<List<dynamic>>('queryAlbums');
    if (rows == null) return <AlbumModel>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map(AlbumModel.fromMap)
        .toList();
  }

  Future<List<ArtistModel>> queryArtists({
    ArtistSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool ignoreCase = true,
  }) async {
    final rows = await _channel.invokeMethod<List<dynamic>>('queryArtists');
    if (rows == null) return <ArtistModel>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map(ArtistModel.fromMap)
        .toList();
  }

  Future<List<SongModel>> queryAudiosFrom(
    AudiosFromType type,
    dynamic id, {
    OrderType? orderType,
    SongSortType? sortType,
  }) async {
    final rows = await _channel.invokeMethod<List<dynamic>>(
      'queryAudiosFrom',
      <String, dynamic>{
        'type': type == AudiosFromType.ALBUM_ID ? 'album' : 'artist',
        'id': id,
      },
    );
    return _toSongs(rows);
  }

  List<SongModel> _toSongs(List<dynamic>? rows) {
    if (rows == null) return <SongModel>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map(SongModel.fromMap)
        .toList();
  }

  /// Saves a WAV file into the device Music library
  /// (Music/RetroWave AI) through MediaStore, so it appears in the
  /// library right away. Returns {id, uri, path} on success.
  Future<Map<String, dynamic>?> saveAudioFile(
      String name, Uint8List bytes) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'saveAudioFile',
      <String, dynamic>{'name': name, 'bytes': bytes},
    );
    if (res == null) return null;
    return res.map((k, v) => MapEntry<String, dynamic>(k.toString(), v));
  }
}

/// Album-art image backed by the media store, with the same constructor
/// shape the app used from the plugin. Shows [nullArtworkWidget] while
/// loading and whenever the song/album has no artwork.
class QueryArtworkWidget extends StatelessWidget {
  final int id;
  final ArtworkType type;
  final double artworkWidth;
  final double artworkHeight;
  final BorderRadius? artworkBorder;
  final Widget? nullArtworkWidget;

  const QueryArtworkWidget({
    super.key,
    required this.id,
    required this.type,
    this.artworkWidth = 50,
    this.artworkHeight = 50,
    this.artworkBorder,
    this.nullArtworkWidget,
  });

  static final Map<String, Future<Uint8List?>> _cache =
      <String, Future<Uint8List?>>{};

  /// Raw artwork bytes for (type, id), cached — shared by the widget
  /// and by features that need the pixels themselves (artwork hue).
  static Future<Uint8List?> artworkBytes(ArtworkType type, int id) {
    final key = '${type.name}:$id';
    return _cache.putIfAbsent(
      key,
      () => _channel.invokeMethod<Uint8List>(
        'queryArtwork',
        <String, dynamic>{'id': id, 'type': type.name},
      ),
    );
  }

  Future<Uint8List?> _load() => artworkBytes(type, id);

  @override
  Widget build(BuildContext context) {
    final placeholder = nullArtworkWidget ??
        SizedBox(width: artworkWidth, height: artworkHeight);
    return FutureBuilder<Uint8List?>(
      future: _load(),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return placeholder;
        return ClipRRect(
          borderRadius: artworkBorder ?? BorderRadius.zero,
          child: Image.memory(
            bytes,
            width: artworkWidth,
            height: artworkHeight,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}
