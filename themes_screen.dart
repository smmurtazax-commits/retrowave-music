import 'package:flutter/material.dart';

import 'fonts.dart';
import 'glass.dart';
import 'themes.dart';

/// Appearance screen: the themes gallery from the design, plus the
/// font picker. Both apply across the whole app immediately.
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appearanceVersion,
      builder: (context, current, _) {
        final p = palette;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Appearance'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ThemedBackground(
            palette: p,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Theme',
                  style: TextStyle(
                    color: p.textDim,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: palettes.length,
                  itemBuilder: (context, i) {
                    final t = palettes[i];
                    final selected =
                        i == themeIndex.value && customColor.value == null;
                    return InkWell(
                      onTap: () => applyTheme(i),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [t.bgTop, t.bgBottom],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: selected ? t.accent : Colors.white12,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                    radius: 10, backgroundColor: t.accent),
                                const SizedBox(width: 6),
                                CircleAvatar(
                                    radius: 10, backgroundColor: t.accent2),
                                const Spacer(),
                                if (selected)
                                  Icon(Icons.check_circle, color: t.accent),
                              ],
                            ),
                            const Spacer(),
                            Icon(Icons.album, color: t.accent, size: 40),
                            const SizedBox(height: 10),
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              t.era,
                              style:
                                  TextStyle(color: t.textDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 26),
                Text(
                  'Custom color',
                  style: TextStyle(
                    color: p.textDim,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Pick any color — RetroWave builds a full theme around it in the app's retro style.",
                  style: TextStyle(color: p.textDim, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<Color?>(
                  valueListenable: customColor,
                  builder: (context, active, _) {
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in swatchColors)
                          GestureDetector(
                            onTap: () => applyCustomColor(c),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c,
                                border: Border.all(
                                  color: active == c
                                      ? Colors.white
                                      : Colors.white24,
                                  width: active == c ? 3 : 1,
                                ),
                              ),
                              child: active == c
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 20)
                                  : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 26),
                Text(
                  'Font',
                  style: TextStyle(
                    color: p.textDim,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<int>(
                  valueListenable: fontIndex,
                  builder: (context, fCurrent, _) {
                    return Column(
                      children: [
                        for (var i = 0; i < fontOptions.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              i == fCurrent
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: i == fCurrent ? p.accent : p.textDim,
                            ),
                            title: Text(
                              'RetroWave Music',
                              style: TextStyle(
                                fontFamily: fontFamilyFor(i),
                                fontSize: 17,
                              ),
                            ),
                            subtitle: Text(
                              '${fontOptions[i].name} • ${fontOptions[i].feel}',
                              style: TextStyle(color: p.textDim),
                            ),
                            onTap: () => applyFont(i),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
