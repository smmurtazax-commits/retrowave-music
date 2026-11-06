import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'composer.dart';
import 'media_query.dart';
import 'now_playing.dart';
import 'player.dart';
import 'themes.dart';

/// AI Studio: pick a style, a tempo and a length, and the built-in
/// composer writes an original instrumental song for you — composed
/// and rendered entirely on this phone, then saved into the library.
class AiStudioScreen extends StatefulWidget {
  const AiStudioScreen({super.key});

  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  static const List<String> _styleNames = <String>[
    'Synthwave Drive',
    'Midnight Chill',
    '80s Pop Glow',
    'Dark Synth',
  ];
  static const List<String> _styleDesc = <String>[
    'Neon roads at midnight — driving bass, bright arpeggios',
    'Slow, soft and dreamy — glowing pads, half-time drums',
    'Big bright choruses — bouncy octave bass',
    'Heavy and moody — pulsing bass, dense arpeggios',
  ];
  static const List<double> _styleTempos = <double>[108, 84, 112, 96];

  int _style = 0;
  double _tempo = 108;
  int _seconds = 60;
  bool _working = false;
  String _status = '';
  SongModel? _song;
  String? _error;

  String _titleFor(int seed) {
    const a = <String>[
      'Neon', 'Midnight', 'Chrome', 'Velvet', 'Laser',
      'Crystal', 'Echo', 'Turbo', 'Solar', 'Lunar',
    ];
    const b = <String>[
      'Horizon', 'Mirage', 'Skyline', 'Voyage', 'Pulse',
      'Afterglow', 'Runway', 'Drift', 'Bloom', 'Static',
    ];
    final r = math.Random(seed);
    return '${a[r.nextInt(a.length)]} ${b[r.nextInt(b.length)]} '
        '${seed % 900 + 100}';
  }

  Future<void> _generate() async {
    setState(() {
      _working = true;
      _error = null;
      _status = 'Composing your song…';
    });
    try {
      final seed = math.Random().nextInt(1 << 30);
      final bytes = await compute(
        renderSongWav,
        ComposerParams(
          style: _style,
          tempo: _tempo.round(),
          seconds: _seconds,
          seed: seed,
        ),
      );
      if (!mounted) return;
      setState(() => _status = 'Saving it to your library…');
      final title = _titleFor(seed);
      final saved = await OnAudioQuery().saveAudioFile('$title.wav', bytes);
      if (!mounted) return;
      if (saved == null) {
        setState(() {
          _working = false;
          _error = 'The song was composed but could not be saved. '
              'Check the app\'s permissions and try again.';
        });
        return;
      }
      setState(() {
        _working = false;
        _song = SongModel(
          id: (saved['id'] as num).toInt(),
          data: saved['path'] as String? ?? '',
          uri: saved['uri'] as String?,
          title: title,
          artist: 'RetroWave AI Studio',
          album: 'AI Sessions',
          duration: _seconds * 1000,
          fileExtension: 'WAV',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Something went wrong while composing. Please try again.';
      });
    }
  }

  Future<void> _play() async {
    final song = _song;
    if (song == null) return;
    await PlayerService.instance.playQueue(<SongModel>[song], 0);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Studio'),
        backgroundColor: Colors.transparent,
      ),
      body: ThemedBackgroundList(
        palette: p,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Make a song out of thin air',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: p.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The built-in composer writes an original instrumental '
              'track — chords, bass, drums, melody — right on your '
              'phone. No internet, no account. Every song is unique.',
              style: TextStyle(color: p.textDim, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Text('STYLE',
                style: TextStyle(
                    color: p.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            for (var i = 0; i < _styleNames.length; i++)
              Card(
                color: i == _style
                    ? p.accent.withOpacity(0.18)
                    : p.card.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: i == _style ? p.accent : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: ListTile(
                  title: Text(_styleNames[i],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_styleDesc[i],
                      style: TextStyle(color: p.textDim)),
                  trailing: i == _style
                      ? Icon(Icons.check_circle, color: p.accent)
                      : Icon(Icons.circle_outlined, color: p.textDim),
                  onTap: () => setState(() {
                    _style = i;
                    _tempo = _styleTempos[i];
                  }),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TEMPO',
                    style: TextStyle(
                        color: p.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2)),
                Text('${_tempo.round()} BPM',
                    style: TextStyle(color: p.accent2)),
              ],
            ),
            Slider(
              value: _tempo,
              min: 70,
              max: 130,
              divisions: 60,
              activeColor: p.accent,
              onChanged: (v) => setState(() => _tempo = v),
            ),
            const SizedBox(height: 8),
            Text('LENGTH',
                style: TextStyle(
                    color: p.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in <int>[30, 60, 90])
                  ChoiceChip(
                    label: Text(s == 60 ? '1 minute' : '$s seconds'),
                    selected: _seconds == s,
                    selectedColor: p.accent.withOpacity(0.35),
                    onSelected: (_) => setState(() => _seconds = s),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _working ? null : _generate,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: Text(_song == null ? 'Generate my song' : 'Generate another'),
            ),
            if (_working) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 10),
              Center(
                child: Text(_status, style: TextStyle(color: p.textDim)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_song != null && !_working) ...[
              const SizedBox(height: 22),
              Card(
                color: p.card.withOpacity(0.65),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.music_note, color: p.accent2),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _song!.title,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_styleNames[_style]} • ${_tempo.round()} BPM • '
                        'saved in your library, album "AI Sessions"',
                        style: TextStyle(color: p.textDim, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _play,
                        style: FilledButton.styleFrom(
                            backgroundColor: p.accent2),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play it now'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Tip: if a new song doesn\'t appear in the library list '
              'right away, tap the rescan button at the top of the '
              'library.',
              style: TextStyle(color: p.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrollable-friendly background: the theme gradient (the glass
/// blur layer is reserved for the main screens).
class ThemedBackgroundList extends StatelessWidget {
  final RetroPalette palette;
  final Widget child;
  const ThemedBackgroundList(
      {super.key, required this.palette, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.bgTop, palette.bgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}
