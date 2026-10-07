import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/services/drive_source.dart';

void main() {
  group('parseDriveFileId', () {
    test('file/d view link', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/file/d/1AbC2dEfGhIjKlMnOpQrStUv/view?usp=sharing'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('file/d link without /view', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/file/d/1AbC2dEfGhIjKlMnOpQrStUv'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('open?id= link', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/open?id=1AbC2dEfGhIjKlMnOpQrStUv'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('uc?id= link with extra params', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/uc?id=1AbC2dEfGhIjKlMnOpQrStUv&export=download'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('file/d link with /u/0/ account segment', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/u/0/file/d/1AbC2dEfGhIjKlMnOpQrStUv/view'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('uc link with /u/1/ account segment', () {
      expect(
        DriveSource.parseDriveFileId(
            'https://drive.google.com/u/1/uc?export=download&id=1AbC2dEfGhIjKlMnOpQrStUv'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('bare file id', () {
      expect(
        DriveSource.parseDriveFileId('1AbC2dEfGhIjKlMnOpQrStUvWxYz0123'),
        '1AbC2dEfGhIjKlMnOpQrStUvWxYz0123',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        DriveSource.parseDriveFileId(
            '  https://drive.google.com/open?id=1AbC2dEfGhIjKlMnOpQrStUv\n'),
        '1AbC2dEfGhIjKlMnOpQrStUv',
      );
    });

    test('rejects garbage', () {
      expect(DriveSource.parseDriveFileId(''), isNull);
      expect(DriveSource.parseDriveFileId('hello world'), isNull);
      expect(
          DriveSource.parseDriveFileId('https://example.com/song.mp3'),
          isNull);
      expect(DriveSource.parseDriveFileId('short'), isNull);
    });
  });

  group('stream urls', () {
    test('driveStreamUrl format', () {
      expect(
        DriveSource.driveStreamUrl('ABC123'),
        'https://drive.google.com/uc?export=download&id=ABC123',
      );
    });

    test('toStreamUrl converts share links, passes others through', () {
      expect(
        DriveSource.toStreamUrl(
            'https://drive.google.com/file/d/ABC123def456GHI789jkl/view'),
        'https://drive.google.com/uc?export=download&id=ABC123def456GHI789jkl',
      );
      expect(
        DriveSource.toStreamUrl('https://example.com/song.mp3'),
        'https://example.com/song.mp3',
      );
    });

    test('stableUrlId is deterministic and hex', () {
      final a = DriveSource.stableUrlId('https://example.com/a.mp3');
      final b = DriveSource.stableUrlId('https://example.com/a.mp3');
      final c = DriveSource.stableUrlId('https://example.com/b.mp3');
      expect(a, b);
      expect(a, isNot(c));
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(a), isTrue);
    });
  });

  group('deriveTitle', () {
    test('strips extension and decodes', () {
      expect(
        DriveSource.deriveTitle(
            'https://example.com/music/My%20Song%20Title.mp3'),
        'My Song Title',
      );
    });

    test('falls back for drive links without filenames', () {
      expect(
        DriveSource.deriveTitle(
            'https://drive.google.com/uc?export=download&id=ABC123'),
        'Drive track',
      );
    });
  });

  group('DriveIndex.parse', () {
    test('parses a plain array', () {
      final entries = DriveIndex.parse('''
        [
          {"title": "Song A", "artist": "Singer A",
           "url": "https://drive.google.com/file/d/FILEID123456789012345/view"},
          {"title": "Song B",
           "url": "https://example.com/song-b.mp3"}
        ]
      ''');
      expect(entries.length, 2);
      expect(entries[0].title, 'Song A');
      expect(entries[0].artist, 'Singer A');
      expect(entries[0].url,
          'https://drive.google.com/uc?export=download&id=FILEID123456789012345');
      expect(entries[1].artist, 'Unknown artist');
      expect(entries[1].url, 'https://example.com/song-b.mp3');
    });

    test('accepts {"tracks": [...]} and {"songs": [...]} wrappers', () {
      final a = DriveIndex.parse(
          '{"tracks": [{"title": "T", "url": "https://example.com/t.mp3"}]}');
      final b = DriveIndex.parse(
          '{"songs": [{"title": "S", "url": "https://example.com/s.mp3"}]}');
      expect(a.length, 1);
      expect(a.first.title, 'T');
      expect(b.length, 1);
      expect(b.first.title, 'S');
    });

    test('skips entries without url, derives missing titles', () {
      final entries = DriveIndex.parse('''
        [
          {"title": "No URL here"},
          {"url": "https://example.com/My_Cool_Song.mp3"},
          "not an object",
          {"title": "", "url": "https://drive.google.com/open?id=FILEID123456789012345"}
        ]
      ''');
      expect(entries.length, 2);
      expect(entries[0].title, 'My Cool Song');
      expect(entries[1].title, 'Drive track');
      expect(entries[1].url,
          'https://drive.google.com/uc?export=download&id=FILEID123456789012345');
    });

    test('rejects invalid JSON and wrong shapes', () {
      expect(DriveIndex.parse('not json'), isEmpty);
      expect(DriveIndex.parse('{"tracks": "nope"}'), isEmpty);
      expect(DriveIndex.parse('42'), isEmpty);
      expect(DriveIndex.parse(''), isEmpty);
    });
  });
}
