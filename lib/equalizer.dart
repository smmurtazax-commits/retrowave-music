import 'package:flutter/material.dart';

import 'audiofx.dart';
import 'player.dart';
import 'themes.dart';

String _fmtFreq(int millihertz) {
  final hz = millihertz / 1000;
  if (hz >= 1000) {
    final khz = hz / 1000;
    return '${khz.toStringAsFixed(khz >= 10 ? 0 : 1)} kHz';
  }
  return '${hz.round()} Hz';
}

/// Equalizer + sound effects screen.
///
/// Uses the phone's own audio effects engine (the same one system music
/// players use): a multi-band equalizer with presets, bass boost and a
/// virtualizer — plus a shortcut to the phone's own effects page
/// (Dolby Atmos / UHQ Upscaler / SoundAlive), which the phone controls.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _info;
  List<int> _levels = <int>[];
  int _preset = -1; // -1 = custom
  double _bass = 0; // 0–100
  double _virt = 0; // 0–100

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final svc = PlayerService.instance;
    final sessionId = await svc.player.androidAudioSessionId;
    if (!mounted) return;
    if (sessionId == null) {
      setState(() {
        _loading = false;
        _error = 'Play a song first, then open the equalizer.';
      });
      return;
    }
    final ok = await AudioFx.init(sessionId);
    final info = ok ? await AudioFx.info() : null;
    if (!mounted) return;
    if (info == null || info['available'] != true) {
      setState(() {
        _loading = false;
        _error = 'Audio effects are not available for this session yet.';
      });
      return;
    }
    setState(() {
      _info = info;
      _levels = List<int>.from(info['levels'] as List);
      _preset = (info['currentPreset'] as int?) ?? -1;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer & Effects'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [p.bgTop, p.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textDim, fontSize: 15),
                      ),
                    ),
                  )
                : _content(p),
      ),
    );
  }

  Widget _content(RetroPalette p) {
    final info = _info!;
    final bands = info['bands'] as int;
    final low = (info['low'] as int).toDouble();
    final high = (info['high'] as int).toDouble();
    final freqs = List<int>.from(info['freqs'] as List);
    final presets = List<String>.from(info['presets'] as List);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Presets
        Text('Presets',
            style: TextStyle(color: p.textDim, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < presets.length; i++)
              ChoiceChip(
                label: Text(presets[i]),
                selected: _preset == i,
                selectedColor: p.accent.withOpacity(0.35),
                onSelected: (_) async {
                  await AudioFx.usePreset(i);
                  final fresh = await AudioFx.info();
                  if (!mounted) return;
                  setState(() {
                    _preset = i;
                    if (fresh != null && fresh['levels'] is List) {
                      _levels = List<int>.from(fresh['levels'] as List);
                    }
                  });
                },
              ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: _preset == -1,
              selectedColor: p.accent.withOpacity(0.35),
              onSelected: (_) => setState(() => _preset = -1),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Bands
        Text('Bands',
            style: TextStyle(color: p.textDim, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (var b = 0; b < bands; b++)
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  _fmtFreq(freqs[b]),
                  style: TextStyle(color: p.textDim, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _levels[b].toDouble().clamp(low, high),
                  min: low,
                  max: high,
                  activeColor: p.accent,
                  inactiveColor: p.card,
                  onChanged: (v) {
                    setState(() {
                      _levels[b] = v.round();
                      _preset = -1;
                    });
                    AudioFx.setBandLevel(b, v.round());
                  },
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${(_levels[b] / 100).toStringAsFixed(1)} dB',
                  style: TextStyle(color: p.textDim, fontSize: 12),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        // Bass boost
        _strengthRow(
          p,
          icon: Icons.speaker,
          label: 'Bass boost',
          value: _bass,
          onChanged: (v) {
            setState(() => _bass = v);
            AudioFx.setBassBoost((v * 10).round());
          },
        ),
        // Virtualizer
        _strengthRow(
          p,
          icon: Icons.surround_sound,
          label: 'Virtualizer (surround feel)',
          value: _virt,
          onChanged: (v) {
            setState(() => _virt = v);
            AudioFx.setVirtualizer((v * 10).round());
          },
        ),
        const SizedBox(height: 20),
        // Phone's own effects
        Card(
          color: p.card.withOpacity(0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, color: p.accent2),
                    const SizedBox(width: 8),
                    const Text(
                      'Phone sound effects',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Dolby Atmos, UHQ Upscaler and other phone effects are controlled by your phone, not by apps. If they are ON in your phone settings, RetroWave uses them automatically.',
                  style: TextStyle(color: p.textDim, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => AudioFx.openSystemEffects(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open phone sound effects'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _strengthRow(
    RetroPalette p, {
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: p.accent2, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 100,
            activeColor: p.accent,
            inactiveColor: p.card,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${value.round()}%',
            style: TextStyle(color: p.textDim, fontSize: 12),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
