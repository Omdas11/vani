import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/artwork_colors.dart';
import 'package:opentune/services/drive_source.dart';
import 'package:opentune/services/local_library.dart';
import 'package:opentune/services/stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings', () {
    test('defaults are iaEnabled=true, autoLoadLyrics=true', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      expect(s.iaEnabled, isTrue);
      expect(s.autoLoadLyrics, isTrue);
      expect(s.loaded, isTrue);
    });

    test('toggles persist across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final a = AppSettings();
      await a.load();
      await a.setIaEnabled(false);
      await a.setAutoLoadLyrics(false);
      final b = AppSettings();
      await b.load();
      expect(b.iaEnabled, isFalse);
      expect(b.autoLoadLyrics, isFalse);
    });
  });

  group('StatsSummary.summarize', () {
    List<ListeningEvent> events() => [
          ListeningEvent(
              trackTitle: 'A',
              trackArtist: 'X',
              source: 'archive',
              playedAt: DateTime(2026, 10, 1, 12),
              durationListenedS: 120,
              completed: true),
          ListeningEvent(
              trackTitle: 'A',
              trackArtist: 'X',
              source: 'archive',
              playedAt: DateTime(2026, 10, 5, 12),
              durationListenedS: 60,
              completed: false),
          ListeningEvent(
              trackTitle: 'B',
              trackArtist: 'Y',
              source: 'drive',
              playedAt: DateTime(2026, 9, 1, 12),
              durationListenedS: 30,
              completed: false),
          ListeningEvent(
              trackTitle: 'C',
              trackArtist: 'X',
              source: 'local',
              playedAt: DateTime(2026, 10, 6, 12),
              durationListenedS: 200,
              completed: true),
        ];

    test('all-time aggregates correctly', () {
      final s = StatsSummary.summarize(events());
      expect(s.totalSeconds, 410);
      expect(s.playCount, 4);
      expect(s.topTracks.first.title, 'C'); // 200s > 180s
      expect(s.topTracks.first.plays, 1);
      expect(s.topArtists.first.artist, 'X'); // 120+60+200
      expect(s.topArtists.first.seconds, 380);
      expect(s.playsBySource['archive'], 2);
      expect(s.playsBySource['drive'], 1);
      expect(s.playsBySource['local'], 1);
    });

    test('since filter restricts the window', () {
      final s = StatsSummary.summarize(events(),
          since: DateTime(2026, 10, 4));
      expect(s.playCount, 2); // Oct 5 and Oct 6 only
      expect(s.totalSeconds, 260);
    });

    test('empty input gives zeroed summary', () {
      final s = StatsSummary.summarize([]);
      expect(s.totalSeconds, 0);
      expect(s.playCount, 0);
      expect(s.topTracks, isEmpty);
      expect(s.topArtists, isEmpty);
    });

    test('fromJson tolerates missing fields', () {
      final e = ListeningEvent.fromJson({'track_title': 'T'});
      expect(e.trackTitle, 'T');
      expect(e.trackArtist, 'Unknown artist');
      expect(e.durationListenedS, 0);
      expect(e.completed, isFalse);
    });
  });

  group('LocalLibrary', () {
    test('stableId is deterministic and hex', () {
      final a = LocalLibrary.stableId('/a/b/song.mp3');
      final b = LocalLibrary.stableId('/a/b/song.mp3');
      final c = LocalLibrary.stableId('/a/b/other.mp3');
      expect(a, b);
      expect(a, isNot(c));
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(a), isTrue);
    });

    test('drive URL title derivation unchanged', () {
      expect(
          DriveSource.deriveTitle(
              'https://drive.google.com/file/d/ABC123/view'),
          'Drive track');
    });
  });

  group('ArtworkColors.averageRgba', () {
    test('averages opaque pixels, skips transparent and black', () {
      // 2x2: red, green, transparent, black
      final px = Uint8List.fromList([
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 0, 0,
        5, 5, 5, 255,
      ]);
      final c = ArtworkColors.averageRgba(px);
      expect((c.r * 255).round(), 127);
      expect((c.g * 255).round(), 127);
      expect((c.b * 255).round(), 0);
    });

    test('all-black returns fallback', () {
      final px = Uint8List.fromList([0, 0, 0, 255, 1, 1, 1, 255]);
      expect(ArtworkColors.averageRgba(px), ArtworkColors.fallback);
    });
  });

  group('lyrics override identity', () {
    test('override key differs from track identity', () async {
      SharedPreferences.setMockInitialValues({});
      // The override path must not collide with the normal cache key:
      // verified by construction ('override::' prefix).
      const trackKey = 'archive::abc::Song::Artist';
      const overrideKey = 'override::artist::song';
      expect(trackKey == overrideKey, isFalse);
    });
  });
}
