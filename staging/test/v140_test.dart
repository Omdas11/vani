import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/services/app_settings.dart';
import 'package:opentune/services/local_library.dart';
import 'package:opentune/services/lyrics_api.dart';

void main() {
  group('KuGou lyrics source', () {
    test('search URL is well-formed', () {
      final url = LyricsApi.kugouSearchUrl(
          artist: 'Arijit Singh', title: 'Tum Hi Ho', durationSeconds: 262);
      expect(url, startsWith('https://lyrics.kugou.com/search?'));
      expect(url, contains('ver=1'));
      expect(url, contains('client=pc'));
      expect(url, contains(Uri.encodeComponent('Arijit Singh - Tum Hi Ho')));
      expect(url, contains('duration=262000'));
    });

    test('normalizeForMatch strips noise and punctuation', () {
      expect(
        LyricsApi.normalizeForMatch('Tum Hi Ho (Official Video) [HD]'),
        'tum hi ho',
      );
      expect(
        LyricsApi.normalizeForMatch('Nightcall - Official Audio'),
        'nightcall',
      );
    });

    test('exact match scores near 1.0', () {
      final s = LyricsApi.scoreKugouCandidate(
        candTitle: 'Tum Hi Ho',
        candArtist: 'Arijit Singh',
        candDurationMs: 262000,
        wantTitle: 'Tum Hi Ho',
        wantArtist: 'Arijit Singh',
        wantDurationSeconds: 262,
      );
      expect(s, greaterThan(0.9));
    });

    test('wrong song scores below the 0.7 threshold', () {
      final s = LyricsApi.scoreKugouCandidate(
        candTitle: 'Completely Different Song',
        candArtist: 'Someone Else',
        candDurationMs: 180000,
        wantTitle: 'Tum Hi Ho',
        wantArtist: 'Arijit Singh',
        wantDurationSeconds: 262,
      );
      expect(s, lessThan(0.7));
    });

    test('duration mismatch penalizes the score', () {
      final close = LyricsApi.scoreKugouCandidate(
        candTitle: 'Tum Hi Ho',
        candArtist: 'Arijit Singh',
        candDurationMs: 262000,
        wantTitle: 'Tum Hi Ho',
        wantArtist: 'Arijit Singh',
        wantDurationSeconds: 262,
      );
      final far = LyricsApi.scoreKugouCandidate(
        candTitle: 'Tum Hi Ho',
        candArtist: 'Arijit Singh',
        candDurationMs: 120000,
        wantTitle: 'Tum Hi Ho',
        wantArtist: 'Arijit Singh',
        wantDurationSeconds: 262,
      );
      expect(far, lessThan(close));
    });

    test('pickKugouCandidate selects the best and dedupes', () {
      final json = {
        'candidates': [
          {
            'id': '1',
            'accesskey': 'aaa',
            'song': 'Completely Different Song',
            'singer': 'Someone Else',
            'duration': 180000,
          },
          {
            'id': '2',
            'accesskey': 'bbb',
            'song': 'Tum Hi Ho',
            'singer': 'Arijit Singh',
            'duration': 262000,
          },
          // duplicate of the winner under another id
          {
            'id': '3',
            'accesskey': 'ccc',
            'song': 'Tum Hi Ho',
            'singer': 'Arijit Singh',
            'duration': 262000,
          },
        ],
      };
      final pick = LyricsApi.pickKugouCandidate(
        json,
        wantTitle: 'Tum Hi Ho',
        wantArtist: 'Arijit Singh',
        wantDurationSeconds: 262,
      );
      expect(pick, isNotNull);
      expect(pick!['id'], '2');
      expect(pick['accesskey'], 'bbb');
    });

    test('pickKugouCandidate returns null when nothing clears threshold',
        () {
      final json = {
        'candidates': [
          {
            'id': '1',
            'accesskey': 'aaa',
            'song': 'Unrelated',
            'singer': 'Nobody',
            'duration': 99999,
          },
        ],
      };
      expect(
        LyricsApi.pickKugouCandidate(
          json,
          wantTitle: 'Tum Hi Ho',
          wantArtist: 'Arijit Singh',
          wantDurationSeconds: 262,
        ),
        isNull,
      );
    });

    test('decodeKugouContent decodes base64 LRC', () {
      const lrc = '[00:12.34] First line\n[01:02.50] Second line\n';
      final json = {'content': base64Encode(utf8.encode(lrc))};
      expect(LyricsApi.decodeKugouContent(json), lrc);
      expect(LyricsApi.decodeKugouContent({'content': ''}), isNull);
      expect(LyricsApi.decodeKugouContent({}), isNull);
    });
  });

  group('Dock configuration', () {
    test('null raw yields defaults', () {
      expect(AppSettings.sanitizeDockOrder(null),
          NavDestination.defaultOrder);
    });

    test('unknown ids are dropped, missing known ids re-added', () {
      final out = AppSettings.sanitizeDockOrder(['home', 'nope', 'stats']);
      expect(out.contains('nope'), isFalse);
      expect(out.first, 'home');
      // search + library + settings re-added at the end
      expect(out.toSet(), NavDestination.ids.toSet());
    });

    test('duplicates are removed, order preserved', () {
      final out =
          AppSettings.sanitizeDockOrder(['search', 'home', 'search']);
      expect(out.where((e) => e == 'search').length, 1);
      expect(out.first, 'search');
    });

    test('NavDestination.byId falls back for unknown ids', () {
      expect(NavDestination.byId('bogus').id, 'home');
      expect(NavDestination.byId('stats').label, 'Stats');
    });
  });

  group('LocalLibrary folder import helpers', () {
    test('audioExtensions covers common formats', () {
      for (final ext in ['.mp3', '.m4a', '.ogg', '.flac', '.wav', '.opus']) {
        expect(LocalLibrary.audioExtensions, contains(ext));
      }
      expect(LocalLibrary.audioExtensions, isNot(contains('.txt')));
      expect(LocalLibrary.audioExtensions, isNot(contains('.jpg')));
    });

    test('stableId is path-sensitive for dedupe', () {
      final a = LocalLibrary.stableId('/x/opentune/local/song.mp3');
      final b = LocalLibrary.stableId('/x/opentune/local/sub/song.mp3');
      expect(a, isNot(b));
      expect(LocalLibrary.stableId('/x/opentune/local/song.mp3'), a);
    });
  });
}
