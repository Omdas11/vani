import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 5-band system equalizer (BETA) built on Android's native AudioEffect
/// Equalizer via just_audio's [AndroidEqualizer].
///
/// The effect is attached to the player's [AudioPipeline] in
/// PlayerController; this controller owns the UI-facing state: enable
/// toggle, named presets, per-band gains, and persistence. Band gains
/// are in decibels within the device-reported [minDb]..[maxDb] range
/// (usually -15..+15).
///
/// Presets are expressed as target gains at reference frequencies and
/// mapped onto whatever bands the device reports, so the same preset
/// names work on 5-band and 7-band devices.
class EqualizerController extends ChangeNotifier {
  static const _kEnabled = 'eq_enabled';
  static const _kPreset = 'eq_preset';
  static const _kGains = 'eq_gains';

  static const List<String> presets = [
    'Normal',
    'Bass Boost',
    'Treble',
    'Vocal',
    'Custom',
  ];

  final AndroidEqualizer _eq;

  bool ready = false;

  /// Whether the platform actually implements the equalizer method
  /// channel. Set to false when the platform throws (notably
  /// UnimplementedError from androidEqualizerGetParameters on devices
  /// where the background player's channel doesn't implement it). When
  /// false, the player is built WITHOUT the equalizer in its
  /// AudioPipeline, so playback can never touch it.
  bool supported = true;
  List<AndroidEqualizerBand> bands = const [];
  double minDb = -15;
  double maxDb = 15;

  bool enabled = false;
  String preset = 'Normal';
  final List<double> gains = [];

  EqualizerController(this._eq);

  /// Marks the equalizer as unsupported by this device's platform.
  /// After this, [init] is a no-op and playback must be built without
  /// the equalizer in the audio pipeline.
  void markUnsupported() {
    supported = false;
    ready = false;
    notifyListeners();
  }

  /// Connects to the platform effect, restores saved settings and
  /// applies them. Retries while the player platform is still
  /// connecting; gives up gracefully (stays !ready) on devices where
  /// the effect is unavailable. Returns immediately if the platform was
  /// already proven unsupported (see [markUnsupported]).
  Future<void> init() async {
    if (!supported) return;
    for (var attempt = 0; attempt < 15 && !ready && supported; attempt++) {
      try {
        final p = await _eq.parameters.timeout(
          const Duration(seconds: 2),
        );
        if (p.bands.isNotEmpty) {
          bands = p.bands;
          minDb = p.minDecibels;
          maxDb = p.maxDecibels;
          ready = true;
        }
      } catch (e) {
        // The platform explicitly declining to implement the equalizer
        // is permanent, not transient: stop retrying and mark it.
        if (e is UnimplementedError &&
            e.toString().contains('Equalizer')) {
          markUnsupported();
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (ready) {
      gains.addAll(List.filled(bands.length, 0.0));
      await _restore();
      await _applyAll();
    }
    notifyListeners();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_kEnabled) ?? false;
      preset = prefs.getString(_kPreset) ?? 'Normal';
      if (!presets.contains(preset)) preset = 'Normal';
      final saved = prefs.getStringList(_kGains);
      if (saved != null && saved.length == bands.length) {
        for (var i = 0; i < bands.length; i++) {
          gains[i] = (double.tryParse(saved[i]) ?? 0.0)
              .clamp(minDb, maxDb);
        }
        if (preset != 'Custom') {
          // Preset gains are recomputed from the curve each launch so
          // they track the device's actual bands.
          _gainsFromPreset(preset);
        }
      } else {
        _gainsFromPreset(preset);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, enabled);
      await prefs.setString(_kPreset, preset);
      await prefs.setStringList(
          _kGains, gains.map((g) => g.toStringAsFixed(1)).toList());
    } catch (_) {}
  }

  /// Target gain curve per preset: list of (frequency Hz, gain dB).
  static List<(double, double)> _presetCurve(String name) {
    switch (name) {
      case 'Bass Boost':
        return const [(60, 8), (150, 6), (400, 2), (1000, 0), (4000, -1), (10000, -2)];
      case 'Treble':
        return const [(60, -3), (150, -2), (1000, 0), (4000, 4), (10000, 7)];
      case 'Vocal':
        return const [(60, -4), (300, -1), (1000, 4), (3000, 5), (8000, 1)];
      case 'Normal':
      default:
        return const [(60, 0)];
    }
  }

  /// Maps a preset curve onto the device's bands by nearest center
  /// frequency (log distance), interpolating the curve.
  void _gainsFromPreset(String name) {
    final curve = _presetCurve(name);
    for (var i = 0; i < bands.length; i++) {
      final f = bands[i].centerFrequency;
      gains[i] = _interp(curve, f).clamp(minDb, maxDb);
    }
  }

  /// Public for testing: interpolates a (freq, gain) curve at [f].
  static double interpForTest(List<(double, double)> curve, double f) =>
      _interp(curve, f);

  static double _interp(List<(double, double)> curve, double f) {
    if (curve.length == 1) return curve.first.$2;
    final pts = List.of(curve)..sort((a, b) => a.$1.compareTo(b.$1));
    if (f <= pts.first.$1) return pts.first.$2;
    if (f >= pts.last.$1) return pts.last.$2;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      if (f >= a.$1 && f <= b.$1) {
        final t = (log(f) - log(a.$1)) / (log(b.$1) - log(a.$1));
        return a.$2 + t * (b.$2 - a.$2);
      }
    }
    return 0;
  }

  Future<void> _applyAll() async {
    if (!ready) return;
    try {
      await _eq.setEnabled(enabled);
      for (var i = 0; i < bands.length; i++) {
        await bands[i].setGain(gains[i]);
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    notifyListeners();
    await _persist();
    if (ready) {
      try {
        await _eq.setEnabled(v);
      } catch (_) {}
    }
  }

  Future<void> applyPreset(String name) async {
    if (!presets.contains(name)) return;
    preset = name;
    if (name != 'Custom') _gainsFromPreset(name);
    notifyListeners();
    await _persist();
    await _applyAll();
  }

  Future<void> setBandGain(int index, double db) async {
    if (index < 0 || index >= gains.length) return;
    gains[index] = db.clamp(minDb, maxDb);
    preset = 'Custom';
    notifyListeners();
    await _persist();
    if (ready) {
      try {
        await bands[index].setGain(gains[index]);
      } catch (_) {}
    }
  }

  /// Human label for a band, e.g. "60 Hz" / "3.6 kHz".
  static String bandLabel(double centerHz) {
    if (centerHz >= 1000) {
      final k = centerHz / 1000;
      final s = k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '$s kHz';
    }
    return '${centerHz.toStringAsFixed(0)} Hz';
  }
}
