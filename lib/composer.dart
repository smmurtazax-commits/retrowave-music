import 'dart:math' as math;
import 'dart:typed_data';

/// RetroWave AI Studio — an on-device composer.
///
/// Generates an original instrumental track (pad chords, pulsing bass,
/// arpeggio, a simple lead, and fully synthesized drums) from a style,
/// a tempo and a seed, and renders it to a 16-bit stereo WAV entirely
/// on the phone. No network, no accounts, no cost. Rendering runs in
/// an isolate via [compute], so the top-level [renderSongWav] entry
/// point takes a plain [ComposerParams].

class ComposerParams {
  final int style; // 0 Synthwave, 1 Chill, 2 Pop, 3 Dark
  final int tempo; // beats per minute
  final int seconds; // target length
  final int seed;
  const ComposerParams({
    required this.style,
    required this.tempo,
    required this.seconds,
    required this.seed,
  });
}

class _Style {
  final bool minor;
  final List<int> progDegrees;
  final List<bool> progMinor;
  final int addTone; // extra chord tone in semitones (14 = add9), 0 = none
  final int bassSteps; // bass notes per bar
  final bool bassOctave; // bounce bass between root and root+12
  final bool arp16; // 16th-note arpeggio (else 8ths)
  final double arpDensity; // 0..1 chance each arp step plays
  final bool halfTime; // half-time drums
  final bool lead;
  const _Style({
    required this.minor,
    required this.progDegrees,
    required this.progMinor,
    required this.addTone,
    required this.bassSteps,
    required this.bassOctave,
    required this.arp16,
    required this.arpDensity,
    required this.halfTime,
    required this.lead,
  });
}

const List<_Style> _styles = <_Style>[
  // Synthwave Drive — Am F C G, driving 8th bass, 16th arp.
  _Style(
    minor: true,
    progDegrees: [0, 5, 2, 6],
    progMinor: [true, false, false, false],
    addTone: 0,
    bassSteps: 8,
    bassOctave: false,
    arp16: true,
    arpDensity: 0.9,
    halfTime: false,
    lead: true,
  ),
  // Midnight Chill — Am G F G with add9 sparkle, half-time, sparse.
  _Style(
    minor: true,
    progDegrees: [0, 6, 5, 6],
    progMinor: [true, false, false, false],
    addTone: 14,
    bassSteps: 4,
    bassOctave: false,
    arp16: false,
    arpDensity: 0.5,
    halfTime: true,
    lead: true,
  ),
  // 80s Pop Glow — C G Am F, octave-bounce bass, bright arp.
  _Style(
    minor: false,
    progDegrees: [0, 4, 5, 3],
    progMinor: [false, false, true, false],
    addTone: 0,
    bassSteps: 8,
    bassOctave: true,
    arp16: true,
    arpDensity: 0.8,
    halfTime: false,
    lead: true,
  ),
  // Dark Synth — Am Am F Dm, 16th bass pulse, dense arp, no lead.
  _Style(
    minor: true,
    progDegrees: [0, 0, 5, 3],
    progMinor: [true, true, false, true],
    addTone: 0,
    bassSteps: 16,
    bassOctave: false,
    arp16: true,
    arpDensity: 0.95,
    halfTime: false,
    lead: false,
  ),
];

const List<int> _minorScale = <int>[0, 2, 3, 5, 7, 8, 10];
const List<int> _majorScale = <int>[0, 2, 4, 5, 7, 9, 11];

double _hz(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// One oscillator voice mixed into a stereo buffer pair.
/// wave: 0 sine, 1 triangle, 2 saw, 3 soft square.
/// tau > 0 gives a pluck (exponential decay); tau = 0 sustains with
/// attack/release ramps.
void _addOsc(
  Float32List outL,
  Float32List outR,
  int start,
  int dur,
  double freq,
  double gain, {
  int wave = 0,
  double pan = 0,
  double attack = 0.005,
  double release = 0.03,
  double tau = 0,
  int sr = 22050,
}) {
  if (start >= outL.length) return;
  final end = math.min(outL.length, start + dur);
  final atk = math.max(1, (attack * sr).round());
  final rel = math.max(1, (release * sr).round());
  final gl = gain * (pan > 0 ? 1 - pan * 0.7 : 1);
  final gr = gain * (pan < 0 ? 1 + pan * 0.7 : 1);
  var phase = 0.0;
  final step = freq / sr;
  for (var i = start; i < end; i++) {
    final t = i - start;
    phase += step;
    final p = phase - phase.floorToDouble();
    double v;
    switch (wave) {
      case 1:
        v = p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
        break;
      case 2:
        v = 2 * p - 1;
        break;
      case 3:
        v = _tanh(2.4 * math.sin(2 * math.pi * p));
        break;
      default:
        v = math.sin(2 * math.pi * p);
    }
    double env;
    if (t < atk) {
      env = t / atk;
    } else if (tau > 0) {
      env = math.exp(-(t - atk) / (tau * sr));
    } else if (t > dur - rel) {
      env = math.max(0.0, (dur - t) / rel);
    } else {
      env = 1.0;
    }
    outL[i] += v * env * gl;
    outR[i] += v * env * gr;
  }
}

/// A synthesized kick drum: a sine that dives in pitch as it decays.
void _addKick(Float32List outL, Float32List outR, int start, double gain,
    {int sr = 22050}) {
  final dur = (0.26 * sr).round();
  final end = math.min(outL.length, start + dur);
  var phase = 0.0;
  for (var i = start; i < end; i++) {
    final t = (i - start) / sr;
    final f = 43 + 95 * math.exp(-t * 26);
    phase += f / sr;
    final env = math.exp(-t * 13);
    final v = math.sin(2 * math.pi * phase) * env * gain;
    outL[i] += v;
    outR[i] += v;
  }
}

/// A noise burst (snare body / hi-hat), optionally high-passed by a
/// simple difference filter so hats stay crisp.
void _addNoise(
  Float32List outL,
  Float32List outR,
  int start,
  double durSec,
  double gain,
  math.Random rng, {
  bool hp = false,
  int sr = 22050,
}) {
  final dur = (durSec * sr).round();
  final end = math.min(outL.length, start + dur);
  var prev = 0.0;
  for (var i = start; i < end; i++) {
    final t = (i - start) / sr;
    var v = rng.nextDouble() * 2 - 1;
    if (hp) {
      final d = v - prev;
      prev = v;
      v = d;
    }
    final env = math.exp(-t * (hp ? 90 : 30));
    final s = v * env * gain;
    outL[i] += s;
    outR[i] += s;
  }
}

/// Renders a complete song to WAV bytes. Top-level so it can run in
/// an isolate through Flutter's compute().
/// Renders the song; returns the WAV bytes AND the true duration
/// (whole bars rarely equal the requested seconds exactly, and the
/// player must show the real length, not the request).
({Uint8List bytes, int durationMs}) renderSongWav(ComposerParams params) {
  const sr = 22050;
  final st = _styles[params.style.clamp(0, _styles.length - 1)];
  final rng = math.Random(params.seed);
  final noise = math.Random(params.seed ^ 0x5f3759df);

  final scale = st.minor ? _minorScale : _majorScale;
  final keyRoot = st.minor
      ? const <int>[45, 43, 41, 40][rng.nextInt(4)]
      : const <int>[48, 45, 43, 41][rng.nextInt(4)];

  final beat = 60.0 / params.tempo;
  final barDur = beat * 4;
  final barSamples = (barDur * sr).round();
  var bars = (params.seconds / barDur).round();
  if (bars < 8) bars = 8;
  // The old 40-bar ceiling silently shortened high-tempo picks
  // (90 s at 130 BPM needs ~49 bars and came out ≈74 s).
  if (bars > 120) bars = 120;
  // Tail for the echo: at least half a second AND at least two
  // beats, so the final notes' echo is never cut off.
  final tail = math.max(sr ~/ 2, (beat * 2 * sr).round());
  final total = bars * barSamples + tail;

  final mixL = Float32List(total);
  final mixR = Float32List(total);
  final busL = Float32List(total); // arp + lead, gets the echo
  final busR = Float32List(total);

  int at(double sec) => (sec * sr).round();

  // A short lead motif for the whole song (scale degrees).
  final motif = List<int>.generate(5, (_) => rng.nextInt(7));

  for (var b = 0; b < bars; b++) {
    final step = b % st.progDegrees.length;
    final chordRoot = keyRoot + scale[st.progDegrees[step]];
    final isMinorChord = st.progMinor[step];
    final tones = <int>[
      chordRoot,
      chordRoot + (isMinorChord ? 3 : 4),
      chordRoot + 7,
      if (st.addTone != 0) chordRoot + st.addTone,
    ];
    final barStart = b * barSamples;
    final intro = b < 2;
    final outro = b >= bars - 2;
    final main = !intro && !outro;

    // ---- Pad: the chord, held for the whole bar ----
    const pans = <double>[-0.3, 0.3, 0.0, 0.15];
    for (var i = 0; i < tones.length; i++) {
      _addOsc(mixL, mixR, barStart, barSamples + barSamples ~/ 8,
          _hz(tones[i] + 12), 0.055,
          wave: 1, pan: pans[i % pans.length],
          attack: barDur * 0.22, release: barDur * 0.25, sr: sr);
    }
    _addOsc(mixL, mixR, barStart, barSamples, _hz(chordRoot), 0.045,
        wave: 0, attack: barDur * 0.2, release: barDur * 0.2, sr: sr);

    // ---- Bass ----
    final stepDur = barDur / st.bassSteps;
    for (var s = 0; s < st.bassSteps; s++) {
      if (outro && s % 2 == 1) continue;
      if (intro && st.bassSteps > 4 && s % 2 == 1) continue;
      final oct = st.bassOctave && s % 2 == 1 ? 12 : 0;
      final start = barStart + at(s * stepDur);
      _addOsc(mixL, mixR, start, at(stepDur * 0.92), _hz(chordRoot + oct),
          0.20,
          wave: 1, attack: 0.004, release: 0.02, sr: sr);
      _addOsc(mixL, mixR, start, at(stepDur * 0.92), _hz(chordRoot + oct),
          0.10,
          wave: 0, attack: 0.004, release: 0.02, sr: sr);
    }

    // ---- Drums ----
    if (!outro && !(intro && b == 0)) {
      if (st.halfTime) {
        _addKick(mixL, mixR, barStart, 0.85, sr: sr);
        _addKick(mixL, mixR, barStart + at(beat * 3.5), 0.6, sr: sr);
        _addNoise(mixL, mixR, barStart + at(beat * 2), 0.16, 0.32, noise,
            sr: sr);
        _addOsc(mixL, mixR, barStart + at(beat * 2), at(0.07), 190, 0.10,
            wave: 0, tau: 0.03, sr: sr);
        for (var h = 0; h < 8; h++) {
          _addNoise(mixL, mixR, barStart + at(h * beat / 2), 0.04,
              h % 2 == 0 ? 0.10 : 0.07, noise,
              hp: true, sr: sr);
        }
      } else {
        for (var k = 0; k < 4; k++) {
          _addKick(mixL, mixR, barStart + at(k * beat), 0.9, sr: sr);
        }
        for (final sb in <int>[1, 3]) {
          _addNoise(mixL, mixR, barStart + at(sb * beat), 0.16, 0.34, noise,
              sr: sr);
          _addOsc(mixL, mixR, barStart + at(sb * beat), at(0.07), 190, 0.11,
              wave: 0, tau: 0.03, sr: sr);
        }
        for (var h = 0; h < 4; h++) {
          _addNoise(mixL, mixR, barStart + at(h * beat + beat / 2), 0.04,
              0.11, noise,
              hp: true, sr: sr);
        }
      }
    }

    // ---- Arpeggio (into the echo bus) ----
    if (!outro) {
      final stepsPerBar = st.arp16 ? 16 : 8;
      final aStep = barDur / stepsPerBar;
      final arpNotes = <int>[
        tones[0] + 24,
        tones[1] + 24,
        tones[2] + 24,
        if (tones.length > 3) tones[3] + 24 else tones[1] + 36,
        tones[2] + 24,
        tones[1] + 24,
      ];
      for (var s = 0; s < stepsPerBar; s++) {
        if (intro && s % 2 == 1) continue;
        if (rng.nextDouble() > st.arpDensity) continue;
        final note = arpNotes[s % arpNotes.length] +
            (s >= stepsPerBar * 0.75 && st.arp16 ? 12 : 0);
        _addOsc(busL, busR, barStart + at(s * aStep), at(aStep * 1.6),
            _hz(note), 0.105,
            wave: params.style == 1 ? 1 : 0,
            pan: s % 2 == 0 ? -0.18 : 0.18,
            attack: 0.002, tau: 0.06, sr: sr);
      }
    }

    // ---- Lead: the motif, answering in the back half of each
    // 4-bar group during the main section ----
    if (st.lead && main && b % 4 >= 2) {
      const slots = <int>[0, 4, 6, 10, 12];
      for (var i = 0; i < slots.length; i++) {
        if (params.style == 1 && i % 2 == 1) continue; // chill: sparser
        final deg = motif[i % motif.length];
        final note = chordRoot + 24 + scale[deg % 7] + (deg >= 7 ? 12 : 0);
        _addOsc(busL, busR, barStart + at(slots[i] * barDur / 16),
            at(beat * 0.9), _hz(note), 0.085,
            wave: 1, attack: 0.01, tau: 0.22, sr: sr);
      }
    }
  }

  // ---- Echo: two taps of the arp/lead bus folded into the mix ----
  final d1 = at(beat * 0.75);
  final d2 = at(beat * 1.5);
  for (var i = 0; i < total; i++) {
    var l = busL[i];
    var r = busR[i];
    if (i + d1 < total) {
      mixL[i + d1] += l * 0.30;
      mixR[i + d1] += r * 0.30;
    }
    if (i + d2 < total) {
      mixL[i + d2] += l * 0.17;
      mixR[i + d2] += r * 0.17;
    }
    mixL[i] += l;
    mixR[i] += r;
  }

  // ---- Master: normalize, gentle fades, encode 16-bit WAV ----
  var peak = 0.0;
  for (var i = 0; i < total; i++) {
    final a = math.max(mixL[i].abs(), mixR[i].abs());
    if (a > peak) peak = a;
  }
  final norm = peak > 0 ? 0.89 / peak : 1.0;
  final fadeIn = (0.02 * sr).round();
  final fadeOut = (0.6 * sr).round();
  final data = ByteData(44 + total * 4);
  void wStr(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  wStr(0, 'RIFF');
  data.setUint32(4, 36 + total * 4, Endian.little);
  wStr(8, 'WAVE');
  wStr(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 2, Endian.little); // stereo
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  wStr(36, 'data');
  data.setUint32(40, total * 4, Endian.little);
  var off = 44;
  for (var i = 0; i < total; i++) {
    var g = norm;
    if (i < fadeIn) g *= i / fadeIn;
    if (i > total - fadeOut) g *= (total - i) / fadeOut;
    final l = (mixL[i] * g).clamp(-1.0, 1.0);
    final r = (mixR[i] * g).clamp(-1.0, 1.0);
    data.setInt16(off, (l * 32767).round(), Endian.little);
    data.setInt16(off + 2, (r * 32767).round(), Endian.little);
    off += 4;
  }
  return (
    bytes: data.buffer.asUint8List(),
    durationMs: (total / sr * 1000).round(),
  );
}
