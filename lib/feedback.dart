import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'themes.dart';

/// Feedback: a star rating plus a note. Sending opens the user's own
/// email app with the message pre-filled to the developer — the
/// feedback lands in the developer's inbox as an email, and nothing
/// leaves the phone until the user presses send there.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const String _developerEmail = 'sm.murtazax@gmail.com';

  int _stars = 0;
  bool _sending = false;
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = Uri.encodeComponent(
        'RetroWave Music — feedback ($_stars star${_stars == 1 ? '' : 's'})');
    final body = Uri.encodeComponent('Rating: $_stars / 5\n\n'
        '${_text.text.trim()}\n\n'
        '— Sent from RetroWave Music');
    final uri =
        Uri.parse('mailto:$_developerEmail?subject=$subject&body=$body');
    setState(() => _sending = true);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Opening your email app — just press Send there.'
            : 'No email app found. You can write to $_developerEmail directly.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback'),
        backgroundColor: Colors.transparent,
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'How is RetroWave treating you?',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: p.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the stars, write a line or two, and your feedback '
              'arrives straight in the developer\'s email inbox.',
              style: TextStyle(color: p.textDim, fontSize: 14),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 42,
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars ? Icons.star : Icons.star_border,
                      color: i <= _stars ? p.accent : p.textDim,
                    ),
                  ),
              ],
            ),
            Center(
              child: Text(
                _stars == 0
                    ? 'Tap a star'
                    : const <String>[
                        '',
                        'Poor',
                        'Fair',
                        'Good',
                        'Great',
                        'Excellent',
                      ][_stars],
                style: TextStyle(color: p.textDim),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _text,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'What do you love? What should be better?',
                filled: true,
                fillColor: p.card.withOpacity(0.55),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: (_stars == 0 || _sending) ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Send by email'),
            ),
            const SizedBox(height: 12),
            Text(
              'The email opens in your own email app, addressed to the '
              'developer — nothing is sent until you press Send there.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
