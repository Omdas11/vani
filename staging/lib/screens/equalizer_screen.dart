import 'package:flutter/material.dart';
import '../services/equalizer.dart';
import '../services/player_controller.dart';

/// System equalizer screen (BETA): enable toggle, preset chips and one
/// vertical slider per device band. Uses Android's native AudioEffect
/// Equalizer through just_audio — the bands shown are whatever the
/// device reports (usually 5). Gains persist across launches.
class EqualizerScreen extends StatelessWidget {
  final PlayerController pc;
  const EqualizerScreen({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: pc.eqc,
      builder: (context, _) {
        final eqc = pc.eqc;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Equalizer'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'BETA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: !eqc.ready
              ? _notReady(context, eqc)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _enableCard(context, eqc),
                    const SizedBox(height: 16),
                    _presetCard(context, eqc),
                    const SizedBox(height: 16),
                    _bandsCard(context, eqc),
                    const SizedBox(height: 12),
                    Text(
                      'Uses your phone\u2019s built-in audio equalizer. '
                      'Bands and range depend on the device; on some '
                      'phones the effect only applies while music is '
                      'playing.',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _notReady(BuildContext context, EqualizerController eqc) {
    // The platform proved it does not implement the equalizer: say so
    // instead of spinning forever.
    if (!eqc.supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.equalizer_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Equalizer not available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your device does not expose a system equalizer to apps. '
                'Music plays normally without it.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Waiting for the audio engine\u2026',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'If this never finishes, your device does not expose a '
              'system equalizer to apps.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _enableCard(BuildContext context, EqualizerController eqc) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: SwitchListTile(
        title: const Text('Equalizer enabled'),
        subtitle: Text(eqc.enabled
            ? 'Shaping: ${eqc.preset}'
            : 'Off — sound plays unmodified'),
        value: eqc.enabled,
        onChanged: eqc.ready ? (v) => eqc.setEnabled(v) : null,
      ),
    );
  }

  Widget _presetCard(BuildContext context, EqualizerController eqc) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            // M3 expressive single-select segmented button row.
            SegmentedButton<String>(
              segments: [
                for (final p in EqualizerController.presets)
                  ButtonSegment(
                    value: p,
                    label: Text(p,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: {eqc.preset},
              onSelectionChanged:
                  eqc.enabled ? (s) => eqc.applyPreset(s.first) : null,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandsCard(BuildContext context, EqualizerController eqc) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < eqc.bands.length; i++)
                    _bandSlider(context, eqc, i),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drag a band to customize (switches to the Custom preset).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandSlider(
      BuildContext context, EqualizerController eqc, int i) {
    final band = eqc.bands[i];
    final gain = eqc.gains[i];
    return Column(
      children: [
        Text(
          '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(0)} dB',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: gain,
              min: eqc.minDb,
              max: eqc.maxDb,
              divisions: ((eqc.maxDb - eqc.minDb) * 2).round(),
              label: '${gain.toStringAsFixed(1)} dB',
              onChanged: eqc.enabled
                  ? (v) => eqc.setBandGain(i, v)
                  : null,
            ),
          ),
        ),
        Text(
          EqualizerController.bandLabel(band.centerFrequency),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
