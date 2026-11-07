import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass.dart';
import 'media_query.dart';
import 'player.dart';
import 'scratch.dart';
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
  DateTime? _lastPanAt;
  double _omega = 0; // smoothed disc angular velocity, rad/s
  bool _scrubbing = false; // backspin mode: paused, seeking by hand
  double _appliedSpeed = 1.0;

  // --- Real-time scratch session (native engine) ---
  // The normal player cannot play backwards, so on the first grab
  // the song is decoded into the scratch engine's memory; from then
  // on the engine renders the sound with a playhead the finger
  // drags in ANY direction — true scratching. Leaving the screen,
  // skipping, or the song ending hands control back to the player
  // at exactly the position the scratching reached.
  bool _scratchPreparing = false;
  bool _scratchActive = false;
  bool _scratchFailed = false;
  bool _resumeAfterScratch = false;
  double _discRate = 1.0; // the engine's current signed speed
  double _lastRatioSent = 999;
  Timer? _scratchPoll;

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
    _scratchPoll?.cancel();
    if (_scratchActive) {
      // Hand the song back to the normal player at the position
      // the scratching reached, resuming if it was playing.
      final resume = _resumeAfterScratch;
      _scratchActive = false;
      Scratch.stop().then((ms) async {
        await Scratch.release();
        await _svc.player.seek(Duration(milliseconds: ms));
        if (resume) _svc.userPlay();
      });
    }
    // Leave the player exactly as the settings say.
    _svc.player.setPitch(1.0);
    _svc.applyStoredSettings();
    super.dispose();
  }

  // ---- scratch session lifecycle ----

  Future<void> _prepareScratch(SongModel song) async {
    if (_scratchPreparing || _scratchActive || _scratchFailed) return;
    _scratchPreparing = true;
    final ok = await Scratch.prepare(song);
    _scratchPreparing = false;
    if (!mounted) {
      Scratch.release();
      return;
    }
    if (!ok) {
      // This file cannot be decoded for scratching — the disc stays
      // in speed/pitch mode for it, which still works fine.
      setState(() => _scratchFailed = true);
      return;
    }
    if (_svc.currentSong?.id != song.id) return; // song moved on
    final pos = _svc.player.position.inMilliseconds;
    _resumeAfterScratch = _svc.player.playing;
    await _svc.player.pause();
    final started = await Scratch.start(pos);
    if (!started) {
      setState(() => _scratchFailed = true);
      if (_resumeAfterScratch) _svc.userPlay();
      return;
    }
    final base = SettingsStore.instance.playSpeed.value;
    setState(() {
      _scratchActive = true;
      _discRate = base;
    });
    _lastRatioSent = base;
    Scratch.setRatio(base);
    // Watch for the song reaching its end inside the engine.
    _scratchPoll?.cancel();
    _scratchPoll = Timer.periodic(const Duration(milliseconds: 500),
        (_) async {
      if (!_scratchActive) return;
      final dur = song.duration ?? 0;
      if (dur <= 0 || _discRate <= 0.05) return;
      final posMs = await Scratch.playheadMs();
      if (posMs >= dur - 300) _endScratch(autoNext: true);
    });
  }

  Future<void> _endScratch({bool autoNext = false}) async {
    if (!_scratchActive) return;
    _scratchActive = false;
    _scratchPoll?.cancel();
    final ms = await Scratch.stop();
    await Scratch.release();
    if (!mounted) return;
    await _svc.player.seek(Duration(milliseconds: ms));
    if (autoNext && _svc.player.hasNext) {
      await _svc.player.seekToNext();
      _svc.userPlay();
    } else if (!autoNext && _resumeAfterScratch) {
      _svc.userPlay();
    }
    if (mounted) setState(() {});
  }

  void _sendRatio(double r) {
    _discRate = r;
    if ((r - _lastRatioSent).abs() > 0.01) {
      _lastRatioSent = r;
      Scratch.setRatio(r);
    }
  }

  Future<void> _skipPrev() async {
    if (_scratchActive) await _endScratch();
    await _svc.player.seekToPrevious();
  }

  Future<void> _skipNext() async {
    if (_scratchActive) await _endScratch();
    await _svc.player.seekToNext();
  }

  String get _statusText {
    if (_scratchPreparing) return 'LOADING THE RECORD…';
    if (_scratchActive) {
      if (_touching) {
        final pct = (_discRate * 100).round();
        return _discRate < -0.03
            ? 'SCRATCHING BACK • $pct%'
            : 'SCRATCHING • $pct%';
      }
      return 'SCRATCH LIVE — grab the record';
    }
    if (_touching) {
      return _scrubbing
          ? 'SCRATCHING BACK…'
          : 'SPEED ${(_appliedSpeed * 100).round()}%';
    }
    return _scratchFailed
        ? 'Drag the disc — speed mode (no scratch for this file)'
        : 'Drag the disc — slow it, spin it, scratch it';
  }

  // ---- rotation + ease-back, driven by the frame ticker ----
  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;
    setState(() {
      if (_touching) {
        // Holding the record: if the finger has stopped moving,
        // the sound stops too — a hand resting on vinyl. (Pan
        // events stop arriving when the finger stops, so the hold
        // is detected here, on the frame clock.)
        if (_scratchActive &&
            _lastPanAt != null &&
            DateTime.now().difference(_lastPanAt!).inMilliseconds >
                90 &&
            _discRate != 0.0) {
          _sendRatio(0.0);
        }
        return; // the finger drives the angle
      }
      if (_easeFrom != null) {
        _easeT += dt / 0.7;
        final t = _easeT.clamp(0.0, 1.0);
        final e = 1 - math.pow(1 - t, 3);
        final target = SettingsStore.instance.playSpeed.value;
        final v = _easeFrom! + (target - _easeFrom!) * e;
        if (_scratchActive) {
          _sendRatio(v);
          if (t >= 1) {
            _easeFrom = null;
            _sendRatio(target);
          }
        } else {
          _applySpeed(v, force: true);
          if (t >= 1) {
            _easeFrom = null;
            _svc.player.setPitch(1.0);
            _appliedSpeed = target;
          }
        }
      }
      final rate = _scratchActive
          ? _discRate
          : (_svc.player.playing ? _svc.player.speed : 0.0);
      if (rate != 0) {
        _angle += _naturalOmega * rate * dt;
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
    _lastPanAt = DateTime.now();
    // First grab of the record: load the song into the real-time
    // scratch engine (it takes over when it's ready).
    final song = _svc.currentSong;
    if (song != null) _prepareScratch(song);
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
    _lastPanAt = DateTime.now();
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
    if (_scratchActive) {
      // The engine takes the finger's speed as a signed ratio —
      // forward, held, or backwards, the SOUND follows, in real
      // time. No pause, no scrubbing: the playhead itself moves.
      _sendRatio((_omega / _naturalOmega).clamp(-3.0, 3.0));
      return;
    }
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
    if (_scratchActive) {
      // Let go: the engine glides back to normal speed (the tick's
      // ease branch drives the ratio from here).
      _easeFrom = _discRate;
      _easeT = 0;
      return;
    }
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
                  _statusText,
                  style: TextStyle(
                    color: _touching || _scratchActive
                        ? p.accent
                        : p.textDim,
                    fontSize: 13,
                    fontWeight: _touching || _scratchActive
                        ? FontWeight.bold
                        : FontWeight.normal,
                    letterSpacing: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 34),
                      onPressed: song == null ? null : _skipPrev,
                    ),
                    StreamBuilder<dynamic>(
                      stream: _svc.player.playerStateStream,
                      builder: (context, s) {
                        // During a scratch session the ENGINE is the
                        // sound (the player is paused underneath) —
                        // the button then ends the session and hands
                        // the song back, instead of starting the
                        // player under the engine (double audio).
                        final playing = _svc.player.playing ||
                            (_scratchActive && _resumeAfterScratch);
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
                                : () {
                                    if (_scratchActive) {
                                      _endScratch();
                                    } else if (playing) {
                                      _svc.player.pause();
                                    } else {
                                      _svc.userPlay();
                                    }
                                  },
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 34),
                      onPressed: song == null ? null : _skipNext,
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
