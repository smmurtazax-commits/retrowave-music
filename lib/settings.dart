import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audiofx.dart';
import 'bg.dart';
import 'feedback.dart';
import 'glass.dart';
import 'player.dart';
import 'playlists.dart';
import 'settings_store.dart';
import 'themes.dart';

/// The full settings screen, modelled on Samsung Music's settings
/// (the user's reference) — every row is wired to a real behaviour.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  SettingsStore get _store => SettingsStore.instance;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ThemedBackground(
        palette: p,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _header(p, 'Playback'),
            _sleepTimer(context, p),
            _playSpeed(context, p),
            _crossfade(context, p),
            _switchRow(
              p,
              title: 'Skip silence between tracks',
              notifier: _store.skipSilence,
              onChanged: (v) {
                PlayerService.instance.player.setSkipSilenceEnabled(v);
                _store.save();
              },
            ),
            _switchRow(
              p,
              title: 'Control music from Lock screen',
              subtitle: 'Applies when the app restarts',
              notifier: _store.lockScreenControls,
              onChanged: (v) {
                AudioFx.setLockScreenControls(v);
                _store.save();
              },
            ),
            _header(p, 'Playlists'),
            _queueSettings(context, p),
            _switchRow(
              p,
              title: "Don't allow duplicate songs",
              subtitle: "Don't allow duplicates in queue",
              notifier: _store.noDuplicates,
              onChanged: (_) => _store.save(),
            ),
            ListTile(
              title: const Text('Manage playlists'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManagePlaylistsScreen(),
                ),
              ),
            ),
            _header(p, 'General'),
            _manageTabs(context, p),
            _darkMode(context, p),
            _switchRow(
              p,
              title: 'Allow external devices to start playback',
              notifier: _store.externalStart,
              onChanged: (_) => _store.save(),
            ),
            _header(p, 'Privacy'),
            ListTile(
              title: const Text('Permissions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AudioFx.openAppSettings(),
            ),
            _header(p, 'About'),
            ListTile(
              title: const Text('Background player'),
              subtitle: Text(
                bgReady
                    ? 'Ready — lock-screen and notification controls are on'
                    : 'Not started on this phone — music still plays '
                        'in the app. Reason: ${bgError ?? 'unknown'}',
              ),
              leading: Icon(
                bgReady ? Icons.lock_clock : Icons.lock_clock_outlined,
                color: bgReady ? p.accent : null,
              ),
            ),
            ListTile(
              title: const Text('About RetroWave Music'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
            ListTile(
              title: const Text('Send feedback'),
              subtitle:
                  const Text('Star rating and a note — arrives by email'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              ),
            ),
            ListTile(
              title: const Text('Contact us'),
              subtitle: const Text('sm.murtazax@gmail.com'),
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: 'sm.murtazax@gmail.com'),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email address copied')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(RetroPalette p, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: p.textDim,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _switchRow(
    RetroPalette p, {
    required String title,
    String? subtitle,
    required ValueNotifier<bool> notifier,
    required ValueChanged<bool> onChanged,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) => SwitchListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        value: value,
        activeColor: p.accent,
        onChanged: (v) {
          notifier.value = v;
          onChanged(v);
        },
      ),
    );
  }

  Future<T?> _radioDialog<T>(
    BuildContext context, {
    required String title,
    required List<(T, String)> options,
    required T current,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in options)
              RadioListTile<T>(
                title: Text(label),
                value: value,
                groupValue: current,
                onChanged: (v) => Navigator.of(context).pop(v),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sleepTimer(BuildContext context, RetroPalette p) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: PlayerService.instance.sleepEndsAt,
      builder: (context, endsAt, _) {
        final minutes = _store.sleepMinutes.value;
        final String sub;
        if (minutes == 0) {
          sub = 'Off';
        } else if (endsAt != null) {
          final h = endsAt.hour % 12 == 0 ? 12 : endsAt.hour % 12;
          final mm = endsAt.minute.toString().padLeft(2, '0');
          final ap = endsAt.hour >= 12 ? 'PM' : 'AM';
          sub = '$minutes min • stops at $h:$mm $ap';
        } else {
          sub = '$minutes min';
        }
        return ListTile(
          title: const Text('Sleep timer'),
          subtitle: Text(sub, style: TextStyle(color: p.accent2)),
          onTap: () async {
            final picked = await _radioDialog<int>(
              context,
              title: 'Sleep timer',
              current: minutes,
              options: const [
                (0, 'Off'),
                (5, '5 minutes'),
                (10, '10 minutes'),
                (15, '15 minutes'),
                (30, '30 minutes'),
                (45, '45 minutes'),
                (60, '60 minutes'),
              ],
            );
            if (picked != null) {
              PlayerService.instance.setSleepTimer(picked);
            }
          },
        );
      },
    );
  }

  Widget _playSpeed(BuildContext context, RetroPalette p) {
    return ValueListenableBuilder<double>(
      valueListenable: _store.playSpeed,
      builder: (context, speed, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: const Text('Play speed'),
            subtitle: Text(
              '${speed.toStringAsFixed(1)}x',
              style: TextStyle(color: p.accent2),
            ),
          ),
          Slider(
            value: speed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            activeColor: p.accent,
            inactiveColor: p.card,
            onChanged: (v) {
              _store.playSpeed.value = v;
              PlayerService.instance.player.setSpeed(v);
            },
            onChangeEnd: (_) => _store.save(),
          ),
        ],
      ),
    );
  }

  Widget _crossfade(BuildContext context, RetroPalette p) {
    return ValueListenableBuilder<int>(
      valueListenable: _store.crossfadeSeconds,
      builder: (context, seconds, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: const Text('Crossfade between tracks'),
            subtitle: Text(
              seconds == 0 ? 'Off' : '$seconds sec',
              style: TextStyle(color: p.accent2),
            ),
          ),
          Slider(
            value: seconds.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            activeColor: p.accent,
            inactiveColor: p.card,
            onChanged: (v) => _store.crossfadeSeconds.value = v.round(),
            onChangeEnd: (_) => _store.save(),
          ),
        ],
      ),
    );
  }

  Widget _queueSettings(BuildContext context, RetroPalette p) {
    return ValueListenableBuilder<String>(
      valueListenable: _store.queueMode,
      builder: (context, mode, _) => ListTile(
        title: const Text('Queue settings'),
        subtitle: Text(
          mode == 'all' ? 'Play all tracks' : 'Play only the tapped track',
          style: TextStyle(color: p.accent2),
        ),
        onTap: () async {
          final picked = await _radioDialog<String>(
            context,
            title: 'Queue settings',
            current: mode,
            options: const [
              ('all', 'Play all tracks'),
              ('single', 'Play only the tapped track'),
            ],
          );
          if (picked != null) {
            _store.queueMode.value = picked;
            _store.save();
          }
        },
      ),
    );
  }

  Widget _manageTabs(BuildContext context, RetroPalette p) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _store.enabledTabs,
      builder: (context, tabs, _) => ListTile(
        title: const Text('Manage tabs'),
        subtitle: Text(
          tabs.map((t) => tabLabels[t] ?? t).join(', '),
          style: TextStyle(color: p.accent2),
        ),
        onTap: () async {
          final selected = Set<String>.of(tabs);
          final result = await showDialog<Set<String>>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('Manage tabs'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in SettingsStore.allTabs)
                      CheckboxListTile(
                        title: Text(tabLabels[id] ?? id),
                        value: selected.contains(id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(selected),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          );
          if (result == null) return;
          if (result.isEmpty) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Keep at least one tab — no change made')),
            );
            return;
          }
          _store.enabledTabs.value =
              SettingsStore.allTabs.where(result.contains).toList();
          _store.save();
        },
      ),
    );
  }

  Widget _darkMode(BuildContext context, RetroPalette p) {
    const labels = <String, String>{
      'system': 'Match phone setting',
      'dark': 'Always dark',
      'light': 'Always light',
    };
    return ValueListenableBuilder<String>(
      valueListenable: _store.darkMode,
      builder: (context, mode, _) => ListTile(
        title: const Text('Dark mode'),
        subtitle: Text(
          labels[mode] ?? mode,
          style: TextStyle(color: p.accent2),
        ),
        onTap: () async {
          final picked = await _radioDialog<String>(
            context,
            title: 'Dark mode',
            current: mode,
            options: const [
              ('system', 'Match phone setting'),
              ('dark', 'Always dark'),
              ('light', 'Always light'),
            ],
          );
          if (picked != null) applyDarkMode(picked);
        },
      ),
    );
  }
}

/// About page: what the app is, its features, and the developer contact.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
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
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.album, size: 72, color: p.accent),
            const SizedBox(height: 12),
            const Text(
              'RetroWave Music',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textDim),
            ),
            const SizedBox(height: 20),
            Text(
              'A retro-styled music player for the music stored on your phone. It scans your library automatically — no account, no sign-in, no ads — and dresses it in four retro themes.',
              style: TextStyle(color: p.textDim, fontSize: 15),
            ),
            const SizedBox(height: 20),
            const Text(
              'Features',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '• Automatic library scan (tracks, albums, artists, folders)\n'
              '• Playlists and Favourites\n'
              '• Equalizer, bass boost and virtualizer\n'
              '• Sleep timer, play speed, crossfade, skip silence\n'
              '• Lock screen, notification panel and Samsung Now Bar controls\n'
              '• Google Cast to TVs and speakers\n'
              '• Split-screen and pop-up view friendly\n'
              '• Five themes including Smokey Glass, custom colors and selectable fonts',
              style: TextStyle(color: p.textDim, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Developer: Syed M. Murtaza Rizvi\nContact: sm.murtazax@gmail.com',
              style: TextStyle(color: p.textDim, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
