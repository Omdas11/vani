import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/lyrics_api.dart';

void main() {
  group('parseLrc', () {
    test('parses basic timestamps', () {
      final lines = LyricsApi.parseLrc(
        '[00:12.34] First line\n'
        '[01:02.50] Second line\n',
      );
      expect(lines.length, 2);
      expect(lines[0].time,
          const Duration(minutes: 0, seconds: 12, milliseconds: 340));
      expect(lines[0].text, 'First line');
      expect(lines[1].time,
          const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    });

    test('handles [mm:ss] and [mm:ss:xx] variants', () {
      final lines = LyricsApi.parseLrc(
        '[00:05] No fraction\n'
        '[00:07:25] Colon fraction\n',
      );
      expect(lines[0].time, const Duration(seconds: 5));
      expect(lines[1].time,
          const Duration(seconds: 7, milliseconds: 250));
    });

    test('expands multiple timestamps on one line', () {
      final lines = LyricsApi.parseLrc(
        '[00:10.00][00:20.00] Chorus\n',
      );
      expect(lines.length, 2);
      expect(lines[0].time, const Duration(seconds: 10));
      expect(lines[1].time, const Duration(seconds: 20));
      expect(lines[0].text, 'Chorus');
    });

    test('skips metadata tags and empty lines', () {
      final lines = LyricsApi.parseLrc(
        '[ti:Song Title]\n'
        '[ar:Some Artist]\n'
        '[al:Some Album]\n'
        '[by:Someone]\n'
        '[offset:500]\n'
        '[00:01.00] Real line\n'
        '[00:02.00]\n'
        '[00:03.00]   \n',
      );
      expect(lines.length, 1);
      expect(lines.first.text, 'Real line');
    });

    test('sorts out-of-order lines by time', () {
      final lines = LyricsApi.parseLrc(
        '[00:30.00] Later\n'
        '[00:10.00] Earlier\n',
      );
      expect(lines.first.text, 'Earlier');
      expect(lines.last.text, 'Later');
    });

    test('ignores malformed lines', () {
      final lines = LyricsApi.parseLrc(
        'no timestamps here\n'
        '[99] broken\n'
        '[ab:cd.ef] broken too\n',
      );
      expect(lines, isEmpty);
    });

    test('empty input gives empty output', () {
      expect(LyricsApi.parseLrc(''), isEmpty);
    });
  });

  group('buildUrl', () {
    test('includes artist, title and duration', () {
      final url = LyricsApi.buildUrl(
          artist: 'Coldplay', title: 'Yellow', durationSeconds: 266);
      expect(url, contains('artist_name=Coldplay'));
      expect(url, contains('track_name=Yellow'));
      expect(url, contains('duration=266'));
      expect(url, startsWith('https://lrclib.net/api/get?'));
    });

    test('omits empty params and placeholder artist', () {
      final url = LyricsApi.buildUrl(
          artist: 'Unknown artist', title: 'Some Song');
      expect(url, isNot(contains('artist_name')));
      expect(url, contains('track_name=Some%20Song'));
      expect(url, isNot(contains('duration')));
    });

    test('URL-encodes special characters', () {
      final url = LyricsApi.buildUrl(
          artist: 'A&B', title: 'Café "Song"');
      expect(url, contains('artist_name=A%26B'));
      expect(url, contains('track_name=Caf%C3%A9%20%22Song%22'));
    });
  });

  group('parseResponse', () {
    test('parses a synced response', () {
      final r = LyricsApi.parseResponse(200, '''
        {"id": 1, "trackName": "Yellow", "artistName": "Coldplay",
         "instrumental": false,
         "plainLyrics": "Look at the stars",
         "syncedLyrics": "[00:12.34] Look at the stars\\n[00:15.00] Shine for you\\n"}
      ''');
      expect(r.found, isTrue);
      expect(r.synced.length, 2);
      expect(r.synced.first.text, 'Look at the stars');
      expect(r.plain, contains('Look at the stars'));
    });

    test('plain-only response has no synced lines but is found', () {
      final r = LyricsApi.parseResponse(200, '''
        {"trackName": "X", "plainLyrics": "la la la", "syncedLyrics": ""}
      ''');
      expect(r.found, isTrue);
      expect(r.synced, isEmpty);
      expect(r.plain, 'la la la');
    });

    test('TrackNotFound body is not found', () {
      final r = LyricsApi.parseResponse(200,
          '{"statusCode":404,"name":"TrackNotFound","message":"nope"}');
      expect(r.found, isFalse);
    });

    test('non-200 status is not found', () {
      expect(LyricsApi.parseResponse(503, 'busy').found, isFalse);
      expect(LyricsApi.parseResponse(429, 'slow down').found, isFalse);
    });

    test('garbage body is not found', () {
      expect(LyricsApi.parseResponse(200, 'not json').found, isFalse);
      expect(LyricsApi.parseResponse(200, '').found, isFalse);
      expect(LyricsApi.parseResponse(200, '[]').found, isFalse);
    });

    test('empty lyrics are not found', () {
      final r = LyricsApi.parseResponse(
          200, '{"plainLyrics": "  ", "syncedLyrics": ""}');
      expect(r.found, isFalse);
    });

    test('flags instrumental tracks', () {
      final r = LyricsApi.parseResponse(200, '''
        {"instrumental": true, "plainLyrics": "",
         "syncedLyrics": "[00:00.00] \\u266a \\u266a \\u266a"}
      ''');
      expect(r.found, isTrue);
      expect(r.instrumental, isTrue);
    });
  });

  group('Track source field', () {
    test('defaults to archive when absent (backwards compatible)', () {
      final t = Track.fromJson({
        'id': 'some-id',
        'title': 'T',
        'artist': 'A',
        'license': 'CC0',
        'licenseUrl': '',
        'artworkUrl': '',
      });
      expect(t.source, 'archive');
      expect(t.isDriveTrack, isFalse);
      expect(t.needsAttribution, isFalse);
    });

    test('drive track round-trips and skips archive attribution', () {
      final t = Track(
        id: 'drive:ABC123',
        title: 'My Song',
        artist: 'Me',
        license: 'Drive',
        licenseUrl: '',
        artworkUrl: '',
        source: 'drive',
        streamUrl: 'https://drive.google.com/uc?export=download&id=ABC123',
      );
      final back = Track.fromJson(t.toJson());
      expect(back.source, 'drive');
      expect(back.isDriveTrack, isTrue);
      expect(back.streamUrl, contains('ABC123'));
      expect(back.needsAttribution, isFalse);
    });

    test('copyWith updates title/artist only', () {
      final t = Track(
        id: 'drive:ABC',
        title: 'Old',
        artist: 'Old A',
        license: 'Drive',
        licenseUrl: '',
        artworkUrl: '',
        source: 'drive',
      );
      final c = t.copyWith(title: 'New', artist: 'New A');
      expect(c.title, 'New');
      expect(c.artist, 'New A');
      expect(c.id, 'drive:ABC');
      expect(c.source, 'drive');
    });
  });

  group('lrclib free-text search', () {
    test('builds a q= URL from title + artist', () {
      final url = LyricsApi.lrclibSearchUrl(
          artist: 'Lagnajita Chakraborty', title: 'Eto J Nithur Bondhu');
      expect(url, startsWith('https://lrclib.net/api/search?q='));
      expect(url, contains('Eto%20J%20Nithur%20Bondhu'));
    });

    test('returns empty when nothing to query', () {
      expect(LyricsApi.lrclibSearchUrl(title: 'Unknown title'), isEmpty);
      expect(LyricsApi.lrclibSearchUrl(), isEmpty);
    });
  });

  group('Google fallback (Namida approach)', () {
    test('query variants are tried in Namida order', () {
      final qs = LyricsApi.googleQueryVariants(
          artist: 'Mekhla Dasgupta', title: 'Tomar Ghore - Live');
      expect(qs.length, 3);
      expect(qs[0], '"Tomar Ghore - Live by Mekhla Dasgupta lyrics"');
      expect(qs[1], '"Tomar Ghore by Mekhla Dasgupta lyrics"');
      expect(qs[2], '"Tomar Ghore - Live by Mekhla Dasgupta song lyrics"');
    });

    test('no artist still yields queries', () {
      final qs = LyricsApi.googleQueryVariants(
          artist: 'Unknown artist', title: 'Amar Bhitor');
      expect(qs.first, '"Amar Bhitor lyrics"');
    });

    test('empty title yields no queries', () {
      expect(LyricsApi.googleQueryVariants(title: ''), isEmpty);
    });

    test('search URL carries the safari client params', () {
      final url = LyricsApi.googleSearchUrl('"x by y lyrics"');
      expect(url, startsWith('https://www.google.com/search?'));
      expect(url, contains('client=safari'));
      expect(url, contains(Uri.encodeComponent('"x by y lyrics"')));
    });

    test('extracts lyrics between the knowledge-panel markers', () {
      const html = '<div class="hwc"><span>Line one<br>Line two</span>'
          '</div><div class="BNeawe tAd8D AP7Wnd">footer</div>';
      final text = LyricsApi.extractGoogleLyrics(html);
      expect(text, isNotNull);
      expect(text, contains('Line one'));
      expect(text, contains('Line two'));
    });

    test('returns null when markers are absent', () {
      expect(
          LyricsApi.extractGoogleLyrics('<html><body>nope</body></html>'),
          isNull);
    });

    test('detects block / CAPTCHA pages', () {
      expect(
          LyricsApi.extractGoogleLyrics(
              '<html>unusual traffic from your computer network</html>'),
          isNull);
      expect(
          LyricsApi.extractGoogleLyrics(
              '<div class="hwc">x</div>please enable javascript'),
          isNull);
    });

    test('decodes HTML entities', () {
      const html = '<div class="hwc"><span>It&apos;s &quot;quoted&quot; &amp; '
          'done<br>second line</span></div>'
          '<div class="BNeawe tAd8D AP7Wnd">x</div>';
      final text = LyricsApi.extractGoogleLyrics(html)!;
      expect(text, contains('It\'s "quoted" & done'));
    });
  });

  group('LyricsResult.source', () {
    test('defaults to lrclib and notFound carries no source claim', () {
      expect(const LyricsResult(found: true).source, 'lrclib');
      expect(LyricsResult.notFound.found, isFalse);
    });
  });

  group('Track.audioFormat', () {
    Track t(String? localPath, String? streamUrl) => Track(
          id: 'x',
          title: 't',
          artist: 'a',
          license: 'Drive',
          licenseUrl: '',
          artworkUrl: '',
          source: 'local',
          localPath: localPath,
          streamUrl: streamUrl,
        );

    test('detects FLAC and OPUS from local path', () {
      expect(t('/music/song.flac', null).audioFormat, 'FLAC');
      expect(t('/music/song.opus', null).audioFormat, 'OPUS');
      expect(t('/music/song.FLAC', null).audioFormat, 'FLAC');
    });

    test('falls back to stream URL', () {
      expect(t(null, 'https://x/y.ogg?dl=1').audioFormat, 'OGG');
    });

    test('beta flag only for FLAC/OPUS', () {
      expect(t('/m/a.flac', null).isBetaFormat, isTrue);
      expect(t('/m/a.opus', null).isBetaFormat, isTrue);
      expect(t('/m/a.mp3', null).isBetaFormat, isFalse);
      expect(t(null, null).isBetaFormat, isFalse);
    });

    test('unknown extension yields null', () {
      expect(t('/m/a.xyz', null).audioFormat, isNull);
    });
  });
}
