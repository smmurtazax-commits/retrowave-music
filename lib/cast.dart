import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'player.dart';

/// Google Cast support.
///
/// How it works: Cast devices (Chromecast, Google TV, Android TV, Cast
/// speakers) cannot read the phone's storage, so when a session starts
/// this service runs a tiny local web server on the phone and hands the
/// receiver the songs as URLs on the home WiFi. The native side
/// (MainActivity) owns the Cast session itself.
///
/// Bluetooth needs no code here: Android routes the app's audio to any
/// connected Bluetooth speaker or earbuds automatically, and the user
/// picks the output from the notification panel's media card.
class CastService {
  CastService._() {
    _ch.setMethodCallHandler(_onNativeCall);
  }
  static final CastService instance = CastService._();

  static const MethodChannel _ch = MethodChannel('retrowave/cast');

  /// True while a Cast session is connected.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  HttpServer? _server;
  int _port = 0;
  String _host = '';
  Map<int, String> _paths = <int, String>{};
  List<SongModel> _pendingQueue = <SongModel>[];
  int _pendingStart = 0;

  /// The cast button: opens the device picker, or stops casting.
  Future<void> onCastButton(List<SongModel> queue, int startIndex) async {
    if (connected.value) {
      await stop();
      return;
    }
    if (queue.isEmpty) return;
    _pendingQueue = queue;
    _pendingStart = startIndex;
    try {
      await _ch.invokeMethod('showRoutePicker');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod('stopCasting');
    } catch (_) {}
    connected.value = false;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'sessionStarted':
        connected.value = true;
        await PlayerService.instance.player.pause();
        await _startServerAndLoad();
        break;
      case 'sessionEnded':
        connected.value = false;
        break;
    }
    return null;
  }

  Future<void> _startServerAndLoad() async {
    if (_pendingQueue.isEmpty) return;
    await _ensureServer();
    _paths = <int, String>{for (final s in _pendingQueue) s.id: s.data};
    final items = _pendingQueue
        .map((s) => <String, dynamic>{
              'url': 'http://$_host:$_port/song/${s.id}',
              'title': s.title,
              'artist': s.artist ?? 'Unknown artist',
              'album': s.album ?? '',
              'durationMs': s.duration ?? 0,
              'mime': mimeFor(s.data),
            })
        .toList();
    try {
      await _ch.invokeMethod('loadQueue', <String, dynamic>{
        'items': items,
        'startIndex': _pendingStart,
      });
    } catch (_) {}
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    _host = await _localIp();
    _server!.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final seg = req.uri.pathSegments;
      if (seg.length == 2 && seg[0] == 'song') {
        final id = int.tryParse(seg[1]);
        final path = id != null ? _paths[id] : null;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final len = await file.length();
            req.response.headers.contentType = ContentType.parse(mimeFor(path));
            req.response.headers
                .set(HttpHeaders.acceptRangesHeader, 'bytes');
            final range = req.headers.value(HttpHeaders.rangeHeader);
            if (range != null && range.startsWith('bytes=')) {
              final parts = range.substring(6).split('-');
              final start = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
              var end = len - 1;
              if (parts.length > 1 && parts[1].isNotEmpty) {
                end = int.tryParse(parts[1]) ?? end;
              }
              if (end >= len) end = len - 1;
              req.response.statusCode = HttpStatus.partialContent;
              req.response.headers
                  .set('Content-Range', 'bytes $start-$end/$len');
              req.response.contentLength = end - start + 1;
              await req.response.addStream(file.openRead(start, end + 1));
              await req.response.close();
              return;
            }
            req.response.contentLength = len;
            await req.response.addStream(file.openRead());
            await req.response.close();
            return;
          }
        }
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<String> _localIp() async {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    var fallback = '127.0.0.1';
    for (final ni in ifs) {
      for (final addr in ni.addresses) {
        if (!addr.isLoopback) {
          fallback = addr.address;
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.')) {
            return addr.address;
          }
        }
      }
    }
    return fallback;
  }

  static String mimeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'audio/mpeg';
    }
  }
}
