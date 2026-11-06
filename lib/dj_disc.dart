import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass.dart';
import 'media_query.dart';
import 'player.dart';
import 'settings_store.dart';
import 'themes.dart';

/// DJ Disc — pure fun. A big vinyl that spins while the song plays.
/// Put your finger on it and you ARE the turntable: drag slowly and
/// the music slows down and drops in pitch, spin it fast and it
/// races, hold it and it nearly stops, scratch it backwards and the
/// song scrubs back — then let go and the record spins itself back
/// up to speed, just like the real thing.
class DjDiscScreen extends StatefulWidget {
  const DjDiscScreen({super.key});

  @override
  State<DjDiscScreen> createState() => _DjDiscScreenState();
}

class _DjDiscScreenState extends State<DjDiscScreen>
    with SingleTickerProviderStateMixin {
  /// A 33 rpm record: one revolution every 1.8 seconds.
  static const double _naturalOmega = 2 * math.pi / 1.8;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _angle = 0;

  bool _touching = false;
  double? _lastPointerAngle;
  DateTime? _lastSampleAt;
  DateTime? _lastScrubAt;
  double _omega = 0; // smoothed disc angular velocity, rad/s
  bool _scrubbing = false; // backspin mode: paused, seeking by hand
  double _appliedSpeed = 1.0;

  // Ease-back after release: speed glides to the stored play speed.
  double? _easeFrom;
  double _easeT = 0;

  PlayerService get _svc => PlayerService.instance;

  @override
  void initState() {
    super.initState();
    _appliedSpeed = _svc.player.speed;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    // Leave the player exactly as the settings say.
    _svc.player.setPitch(1.0);
    _svc.applyStoredSettings();
    super.dispose();
  }

  // ---- rotation + ease-back, driven by the frame ticker ----
  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;
    setState(() {
      if (_touching) return; // the finger drives the angle
      if (_easeFrom != null) {
        _easeT += dt / 0.7;
        final t = _easeT.clamp(0.0, 1.0);
        final e = 1 - math.pow(1 - t, 3);
        final target = SettingsStore.instance.playSpeed.value;
        final v = _easeFrom! + (target - _easeFrom!) * e;
        _applySpeed(v, force: true);
        if (t >= 1) {
          _easeFrom = null;
          _svc.player.setPitch(1.0);
          _appliedSpeed = target;
        }
      }
      if (_svc.player.playing) {
        _angle += _naturalOmega * _svc.player.speed * dt;
      }
    });
  }

  // ---- finger on the record ----
  double _pointerAngle(Offset local, double size) =>
      math.atan2(local.dy - size / 2, local.dx - size / 2);

  double _shortestArc(double d) {
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  void _panStart(DragStartDetails d, double size) {
    _touching = true;
    _easeFrom = null;
    _omega = 0;
    _lastPointerAngle = _pointerAngle(d.localPosition, size);
    _lastSampleAt = DateTime.now();
    _lastScrubAt = DateTime.now();
  }

  void _panUpdate(DragUpdateDetails d, double size) {
    final a = _pointerAngle(d.localPosition, size);
    final last = _lastPointerAngle;
    if (last == null) {
      _lastPointerAngle = a;
      return;
    }
    final delta = _shortestArc(a - last);
    _lastPointerAngle = a;
    setState(() => _angle += delta);

    final now = DateTime.now();
    final dtMs = now.difference(_lastSampleAt!).inMilliseconds;
    if (dtMs >= 8) {
      final inst = delta / (dtMs / 1000.0);
      _omega = _omega * 0.55 + inst * 0.45;
      _lastSampleAt = now;
    }
    _applyFromOmega();
  }

  void _applyFromOmega() {
    if (!_svc.player.playing && !_scrubbing) return; // visual only
    final ratio = _omega / _naturalOmega;
    if (ratio >= 0.03) {
      if (_scrubbing) {
        _scrubbing = false;
        _svc.userPlay();
      }
      _applySpeed(ratio.clamp(0.08, 3.0));
    } else if (ratio <= -0.03) {
      // Backspin: the player cannot play in reverse, so scrub the
      // position backwards by hand — the classic back-cue feel.
      if (!_scrubbing) {
        _scrubbing = true;
        _svc.player.pause();
      }
      final now = DateTime.now();
      final dt = now.difference(_lastScrubAt!).inMilliseconds / 1000.0;
      _lastScrubAt = now;
      if (dt > 0 && dt < 0.2) {
        final posMs = _svc.player.position.inMilliseconds;
        final next = posMs + (ratio * dt * 1000).round();
        _svc.player.seek(Duration(milliseconds: next.clamp(0, 1 << 31)));
      }
    } else {
      // Holding the record still: it crawls.
      if (!_scrubbing) _applySpeed(0.06);
    }
  }

  void _panEnd(DragEndDetails d) {
    _touching = false;
    _lastPointerAngle = null;
    if (_scrubbing) {
      _scrubbing = false;
      _svc.player.setPitch(1.0);
      _svc.applyStoredSettings();
      _appliedSpeed = SettingsStore.instance.playSpeed.value;
      _svc.userPlay();
    } else if (_svc.player.playing) {
      _easeFrom = _appliedSpeed;
      _easeT = 0;
    }
  }

  void _applySpeed(double v, {bool force = false}) {
    if (!force && (v - _appliedSpeed).abs() < 0.02) return;
    _appliedSpeed = v;
    _svc.player.setSpeed(v);
    // Vinyl coupling: pitch follows speed, like a real record.
    _svc.player.setPitch(v.clamp(0.5, 2.0));
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final p = palette;
    final size =
        math.min(MediaQuery.of(context).size.width * 0.84, 360.0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Disc'),
        backgroundColor: Colors.transparent,
      ),
      body: ThemedBackground(
        palette: p,
        child: StreamBuilder<int?>(
          stream: _svc.player.currentIndexStream,
          builder: (context, snap) {
            final song = _svc.currentSong;
            return Column(
              children: [
                const Spacer(),
                GestureDetector(
                  onPanStart: (d) => _panStart(d, size),
                  onPanUpdate: (d) => _panUpdate(d, size),
                  onPanEnd: _panEnd,
                  onPanCancel: () => _panEnd(DragEndDetails()),
                  child: _disc(song, p, size),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    song?.title ?? 'Nothing playing',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song?.artist ?? 'Pick a song, then come and spin it',
                  style: TextStyle(color: p.textDim, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Text(
                  _touching
                      ? (_scrubbing
                          ? 'SCRATCHING BACK…'
                          : 'SPEED ${(_appliedSpeed * 100).round()}%')
                      : 'Drag the disc — slow it, spin it, scratch it',
                  style: TextStyle(
                    color: _touching ? p.accent : p.textDim,
                    fontSize: 13,
                    fontWeight:
                        _touching ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 34),
                      onPressed: song == null
                          ? null
                          : () => _svc.player.seekToPrevious(),
                    ),
                    StreamBuilder<dynamic>(
                      stream: _svc.player.playerStateStream,
                      builder: (context, s) {
                        final playing = _svc.player.playing;
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: [p.accent, p.accent2]),
                          ),
                          child: IconButton(
                            iconSize: 38,
                            color: Colors.white,
                            icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow),
                            onPressed: song == null
                                ? null
                                : () => playing
                                    ? _svc.player.pause()
                                    : _svc.userPlay(),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 34),
                      onPressed: song == null
                          ? null
                          : () => _svc.player.seekToNext(),
                    ),
                  ],
                ),
                const Spacer(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _disc(SongModel? song, RetroPalette p, double size) {
    final label = size * 0.52;
    return Transform.rotate(
      angle: _angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0B0B0E),
          boxShadow: [
            BoxShadow(
              color: p.accent.withOpacity(0.35),
              blurRadius: 42,
              spreadRadius: 2,
            ),
            const BoxShadow(color: Colors.black87, blurRadius: 18),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GroovesPainter(p.accent)),
            ),
            if (song == null)
              Container(
                width: label,
                height: label,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient:
                      LinearGradient(colors: [p.accent, p.accent2]),
                ),
                child: Icon(Icons.music_note,
                    size: label * 0.42, color: Colors.white70),
              )
            else
              QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkWidth: label,
                artworkHeight: label,
                artworkBorder: BorderRadius.circular(label),
                nullArtworkWidget: Container(
                  width: label,
                  height: label,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient:
                        LinearGradient(colors: [p.accent, p.accent2]),
                  ),
                  child: Icon(Icons.music_note,
                      size: label * 0.42, color: Colors.white70),
                ),
              ),
            Container(
              width: 13,
              height: 13,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vinyl grooves: fine concentric rings plus one soft light arc,
/// so the disc reads as a real record while it turns.
class _GroovesPainter extends CustomPainter {
  final Color accent;
  const _GroovesPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = maxR * 0.30; r < maxR * 0.985; r += 3.1) {
      ring.color =
          Colors.white.withOpacity(0.028 + 0.02 * ((r * 7) % 3) / 2);
      canvas.drawCircle(center, r, ring);
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = maxR * 0.16
      ..color = accent.withOpacity(0.10);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.82),
      -0.6,
      0.9,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_GroovesPainter old) => old.accent != accent;
}
