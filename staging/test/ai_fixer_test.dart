import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/services/ai_fixer.dart';

/// Unit tests for the pure, side-effect-free AiFixer helpers.
/// No network or secure storage is touched here.
void main() {
  group('filenamePrompt', () {
    test('embeds the filename and the JSON contract', () {
      final prompt = AiFixer.filenamePrompt('SONG__HD 320kbps [Lyrics].mp3');
      expect(prompt, contains('SONG__HD 320kbps [Lyrics].mp3'));
      expect(prompt, contains('{"filename":"<cleaned filename>"}'));
      expect(prompt, contains('extension'));
    });

    test('mentions stripping junk tokens and Artist - Title format', () {
      final prompt = AiFixer.filenamePrompt('x.mp3');
      expect(prompt.toLowerCase(), contains('bitrate'));
      expect(prompt, contains('Artist - Title'));
    });
  });

  group('metadataPrompt', () {
    test('embeds title and artist and the JSON contract', () {
      final prompt =
          AiFixer.metadataPrompt('kishore kumar - tere bina', 'Unknown artist');
      expect(prompt, contains('kishore kumar - tere bina'));
      expect(prompt, contains('Unknown artist'));
      expect(prompt, contains('{"title":"<cleaned title>"'));
      expect(prompt, contains('"artist":"<cleaned artist>"'));
    });

    test('describes the Unknown artist keep/drop rule', () {
      final prompt = AiFixer.metadataPrompt('t', 'a');
      expect(prompt, contains('Unknown artist'));
    });
  });

  group('parseFilenameFix', () {
    test('parses plain JSON', () {
      final result = AiFixer.parseFilenameFix('{"filename":"Asha - Song.mp3"}');
      expect(result, {'filename': 'Asha - Song.mp3'});
    });

    test('strips markdown fences', () {
      final result = AiFixer.parseFilenameFix(
          '```json\n{"filename":"Asha - Song.mp3"}\n```');
      expect(result, {'filename': 'Asha - Song.mp3'});
    });

    test('strips bare fences without language tag', () {
      final result =
          AiFixer.parseFilenameFix('```{"filename":"Asha - Song.mp3"}```');
      expect(result, {'filename': 'Asha - Song.mp3'});
    });

    test('trims whitespace around the value', () {
      final result =
          AiFixer.parseFilenameFix('{"filename":"  Asha - Song.mp3  "}');
      expect(result, {'filename': 'Asha - Song.mp3'});
    });

    test('returns empty map on garbage', () {
      expect(AiFixer.parseFilenameFix('not json at all'), isEmpty);
    });

    test('returns empty map when filename is missing', () {
      expect(AiFixer.parseFilenameFix('{"other":"x"}'), isEmpty);
    });

    test('returns empty map when filename is not a string', () {
      expect(AiFixer.parseFilenameFix('{"filename":42}'), isEmpty);
    });

    test('ignores surrounding prose', () {
      final result = AiFixer.parseFilenameFix(
          'Here you go:\n{"filename":"Asha - Song.mp3"}\nDone!');
      expect(result, {'filename': 'Asha - Song.mp3'});
    });
  });

  group('parseMetadataFix', () {
    test('parses title and artist', () {
      final result = AiFixer.parseMetadataFix(
          '{"title":"Tere Bina Zindagi","artist":"Kishore Kumar"}');
      expect(result, {'title': 'Tere Bina Zindagi', 'artist': 'Kishore Kumar'});
    });

    test('strips markdown fences', () {
      final result = AiFixer.parseMetadataFix(
          '```json\n{"title":"Tere Bina Zindagi","artist":"Kishore Kumar"}\n```');
      expect(result, {'title': 'Tere Bina Zindagi', 'artist': 'Kishore Kumar'});
    });

    test('drops empty or non-string values, keeps the rest', () {
      final result = AiFixer.parseMetadataFix(
          '{"title":"  ","artist":"Kishore Kumar","extra":7}');
      expect(result, {'artist': 'Kishore Kumar'});
    });

    test('returns empty map on garbage', () {
      expect(AiFixer.parseMetadataFix('nope'), isEmpty);
    });

    test('returns empty map for a JSON array', () {
      expect(AiFixer.parseMetadataFix('["a","b"]'), isEmpty);
    });
  });

  group('AiFixerException', () {
    test('carries a user-safe message', () {
      const e = AiFixerException('Quota exceeded — try again later.');
      expect(e.message, contains('Quota exceeded'));
      expect(e.toString(), contains('AiFixerException'));
    });
  });

  group('AiProvider', () {
    test('byId resolves known ids and defaults to gemini', () {
      expect(AiProvider.byId('gemini'), same(AiProvider.gemini));
      expect(AiProvider.byId('openrouter'), same(AiProvider.openrouter));
      expect(AiProvider.byId('custom'), same(AiProvider.custom));
      expect(AiProvider.byId('nope'), same(AiProvider.gemini));
      expect(AiProvider.byId(null), same(AiProvider.gemini));
    });

    test('each provider has a distinct secure-storage key name', () {
      final keys = AiProvider.all.map((p) => p.keyName).toSet();
      expect(keys.length, AiProvider.all.length);
      expect(keys, contains('ai_key_gemini'));
      expect(keys, contains('ai_key_openrouter'));
      expect(keys, contains('ai_key_custom'));
    });
  });

  group('sanitizeFilename', () {
    test('strips illegal characters', () {
      expect(AiFixer.sanitizeFilename('A<B>C:D"E/F\\G|H?I*J.mp3'),
          'ABCDEFGHIJ.mp3');
    });

    test('strips control chars and trims trailing dots/spaces', () {
      expect(AiFixer.sanitizeFilename('Song.\u0007 .mp3'), 'Song.mp3');
    });

    test('collapses whitespace and keeps the extension', () {
      expect(
          AiFixer.sanitizeFilename('Asha   -   Song.MP3'), 'Asha - Song.MP3');
    });

    test('caps the total length at ~120 chars, extension preserved', () {
      final long = '${'a' * 200}.mp3';
      final out = AiFixer.sanitizeFilename(long);
      expect(out.length, lessThanOrEqualTo(120));
      expect(out, endsWith('.mp3'));
    });

    test('falls back to "track" when nothing usable remains', () {
      expect(AiFixer.sanitizeFilename('<>:"/\\|?*.mp3'), 'track.mp3');
    });

    test('keeps names without an extension intact', () {
      expect(AiFixer.sanitizeFilename('just a song'), 'just a song');
    });
  });

  group('openAiCompletionsUrl', () {
    test('appends /chat/completions', () {
      expect(AiFixer.openAiCompletionsUrl('https://x.test/v1'),
          'https://x.test/v1/chat/completions');
    });

    test('tolerates a trailing slash', () {
      expect(AiFixer.openAiCompletionsUrl('https://x.test/v1/'),
          'https://x.test/v1/chat/completions');
    });
  });

  group('openAiHeaders', () {
    test('uses Bearer auth and JSON content type', () {
      final h = AiFixer.openAiHeaders('  secret-key  ');
      expect(h['Authorization'], 'Bearer secret-key');
      expect(h['Content-Type'], 'application/json');
    });

    test('merges extra headers', () {
      final h = AiFixer.openAiHeaders('k', extra: {'X-Title': 'Vani'});
      expect(h['X-Title'], 'Vani');
      expect(h['Authorization'], 'Bearer k');
    });
  });

  group('openAiBody', () {
    test('builds a chat-completions body', () {
      final body = AiFixer.openAiBody(prompt: 'hi', model: 'm1');
      expect(body, contains('"model":"m1"'));
      expect(body, contains('"role":"user"'));
      expect(body, contains('"content":"hi"'));
      expect(body, contains('"temperature":0.2'));
    });
  });

  group('extractOpenAiText', () {
    test('pulls choices[0].message.content', () {
      const body =
          '{"choices":[{"message":{"role":"assistant","content":"ok"}}]}';
      expect(AiFixer.extractOpenAiText(body), 'ok');
    });

    test('returns null on garbage or unexpected shapes', () {
      expect(AiFixer.extractOpenAiText('nope'), isNull);
      expect(AiFixer.extractOpenAiText('{"choices":[]}'), isNull);
      expect(AiFixer.extractOpenAiText('{"choices":[{"message":{}}]}'), isNull);
    });
  });

  group('CoverArt.itunesSearchUrl', () {
    test('points at the iTunes Search API with song entity', () {
      final url =
          CoverArt.itunesSearchUrl(artist: 'Kishore Kumar', title: 'Tere Bina');
      expect(url, contains('itunes.apple.com/search'));
      expect(url, contains('entity=song'));
      expect(url, contains('media=music'));
    });
  });

  group('CoverArt.upscaleItunes', () {
    test('swaps 100x100 for 600x600', () {
      expect(
          CoverArt.upscaleItunes(
              'https://is1-ssl.mzstatic.com/image/100x100bb.jpg'),
          'https://is1-ssl.mzstatic.com/image/600x600bb.jpg');
    });

    test('leaves urls without the size token alone', () {
      const u = 'https://example.com/art.jpg';
      expect(CoverArt.upscaleItunes(u), u);
    });
  });

  group('CoverArt.parseItunesArtwork', () {
    test('picks the first result and upscales it', () {
      const body = '{"resultCount":2,"results":['
          '{"artworkUrl100":"https://x/100x100bb.jpg"},'
          '{"artworkUrl100":"https://x/other100x100.jpg"}]}';
      expect(CoverArt.parseItunesArtwork(body), 'https://x/600x600bb.jpg');
    });

    test('returns null when nothing usable is present', () {
      expect(CoverArt.parseItunesArtwork('{"results":[]}'), isNull);
      expect(CoverArt.parseItunesArtwork('{"results":[{}]}'), isNull);
      expect(CoverArt.parseItunesArtwork('garbage'), isNull);
    });
  });

  group('CoverArt.musicBrainzUrl', () {
    test('points at the recording endpoint with json format', () {
      final url =
          CoverArt.musicBrainzUrl(artist: 'Kishore Kumar', title: 'Tere Bina');
      expect(url, contains('musicbrainz.org/ws/2/recording/'));
      expect(url, contains('fmt=json'));
    });
  });

  group('CoverArt.parseMusicBrainzReleaseId', () {
    test('returns the first release mbid', () {
      const body = '{"recordings":[{"releases":[{"id":"abc-123"}]}]}';
      expect(CoverArt.parseMusicBrainzReleaseId(body), 'abc-123');
    });

    test('returns null when releases are missing', () {
      expect(CoverArt.parseMusicBrainzReleaseId('{"recordings":[]}'), isNull);
      expect(
          CoverArt.parseMusicBrainzReleaseId(
              '{"recordings":[{"releases":[]}]}'),
          isNull);
      expect(CoverArt.parseMusicBrainzReleaseId('garbage'), isNull);
    });
  });

  group('CoverArt.coverArtArchiveUrl', () {
    test('builds the front-500 url', () {
      expect(CoverArt.coverArtArchiveUrl('abc-123'),
          'https://coverartarchive.org/release/abc-123/front-500');
    });
  });

  group('CoverArt.fileNameForId', () {
    test('sanitizes track ids into safe filenames', () {
      expect(CoverArt.fileNameForId('drive:1a2b3c'), 'drive_1a2b3c.jpg');
      expect(CoverArt.fileNameForId('local:deadbeef'), 'local_deadbeef.jpg');
    });
  });
}
