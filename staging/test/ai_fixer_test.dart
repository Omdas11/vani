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
      final result =
          AiFixer.parseFilenameFix('{"filename":"Asha - Song.mp3"}');
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
      expect(result,
          {'title': 'Tere Bina Zindagi', 'artist': 'Kishore Kumar'});
    });

    test('strips markdown fences', () {
      final result = AiFixer.parseMetadataFix(
          '```json\n{"title":"Tere Bina Zindagi","artist":"Kishore Kumar"}\n```');
      expect(result,
          {'title': 'Tere Bina Zindagi', 'artist': 'Kishore Kumar'});
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
}
