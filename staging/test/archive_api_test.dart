import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/models/track.dart';
import 'package:opentune/services/archive_api.dart';

void main() {
  final api = ArchiveApi();

  group('docToTrack', () {
    test('parses a CC0 doc', () {
      final t = api.docToTrack({
        'identifier': 'Ondrosik-Free-music-catalog',
        'title': 'Enchanted Valley',
        'creator': 'Ondrosik',
        'licenseurl':
            'https://creativecommons.org/publicdomain/zero/1.0/',
      })!;
      expect(t.id, 'Ondrosik-Free-music-catalog');
      expect(t.title, 'Enchanted Valley');
      expect(t.artist, 'Ondrosik');
      expect(t.license, 'CC0');
      expect(t.needsAttribution, isFalse);
      expect(t.artworkUrl,
          'https://archive.org/services/img/Ondrosik-Free-music-catalog');
    });

    test('parses a CC-BY 4.0 doc and flags attribution', () {
      final t = api.docToTrack({
        'identifier': 'monster-in-the-closet-main',
        'title': 'A Long Path',
        'creator': 'Frank Schlimbach',
        'licenseurl': 'https://creativecommons.org/licenses/by/4.0/',
      })!;
      expect(t.license, 'CC BY 4.0');
      expect(t.needsAttribution, isTrue);
    });

    test('parses a CC-BY 3.0 doc', () {
      final t = api.docToTrack({
        'identifier': 'some-id',
        'title': 'Some Song',
        'creator': 'Someone',
        'licenseurl': 'https://creativecommons.org/licenses/by/3.0/',
      })!;
      expect(t.license, 'CC BY 3.0');
    });

    test('falls back to identifier when title is missing', () {
      final t = api.docToTrack({
        'identifier': 'no-title-id',
        'licenseurl':
            'https://creativecommons.org/publicdomain/zero/1.0/',
      })!;
      expect(t.title, 'no-title-id');
      expect(t.artist, 'Unknown artist');
    });

    test('rejects docs without an identifier', () {
      expect(api.docToTrack({'title': 'x'}), isNull);
    });
  });

  group('blocklist', () {
    test('blocks mislabeled commercial uploads', () {
      expect(api.isBlocked('some-id', 'Childish Gambino - Album'), isTrue);
      expect(api.isBlocked('fantasia-2000-remaster', 'Fantasia'), isTrue);
      expect(
          api.isBlocked('movie-x', 'Movie X Deluxe Soundtrack'), isTrue);
    });

    test('docToTrack drops blocked items', () {
      expect(
          api.docToTrack({
            'identifier': 'childish-gambino-discog',
            'title': 'Childish Gambino Collection',
            'licenseurl':
                'https://creativecommons.org/publicdomain/zero/1.0/',
          }),
          isNull);
    });

    test('does not block ordinary open music', () {
      expect(api.isBlocked('koraii-full-discography', 'Amalgam'), isFalse);
      expect(
          api.isBlocked('netlabel-release-42', 'Ambient Dreams'), isFalse);
    });
  });

  group('Track serialization', () {
    test('toJson/fromJson round-trip', () {
      final t = Track(
        id: 'abc',
        title: 'Song',
        artist: 'Artist',
        license: 'CC BY 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
        artworkUrl: 'https://archive.org/services/img/abc',
        localPath: '/tmp/abc.mp3',
      );
      final back = Track.fromJson(t.toJson());
      expect(back.id, t.id);
      expect(back.title, t.title);
      expect(back.artist, t.artist);
      expect(back.license, t.license);
      expect(back.localPath, t.localPath);
      expect(back.isDownloaded, isTrue);
    });
  });

  group('playable file picking', () {
    // Shape mirrors the real Ondrosik-Free-music-catalog metadata:
    // originals are FLAC, MP3s are Archive-generated derivatives.
    final files = [
      {'name': 'A Bedtime Confession.flac', 'source': 'original'},
      {'name': 'A Bedtime Confession.mp3', 'source': 'derivative'},
      {'name': 'cover.jpg', 'source': 'original'},
    ];

    test('prefers derivative mp3 over original flac', () {
      final pick = ArchiveApi.pickPlayableFile(files)!;
      expect(pick['name'], 'A Bedtime Confession.mp3');
    });

    test('returns null when nothing playable exists', () {
      expect(
          ArchiveApi.pickPlayableFile([
            {'name': 'cover.jpg', 'source': 'original'}
          ]),
          isNull);
    });

    test('downloadUrl matches the verified playable URL shape', () {
      // Verified live 2026-10-07 (MUSIC_SOURCES.md):
      // https://archive.org/download/koraii-full-discography/
      //   Koraii%20-%20Full%20Discography%20(2016-2023)/
      //   Birth%20of%20Paul%20(2023)/1%20-%20Amalgam.mp3
      expect(
        ArchiveApi.downloadUrl('koraii-full-discography',
            'Koraii - Full Discography (2016-2023)/Birth of Paul (2023)/1 - Amalgam.mp3'),
        'https://archive.org/download/koraii-full-discography/'
        'Koraii%20-%20Full%20Discography%20(2016-2023)/'
        'Birth%20of%20Paul%20(2023)/1%20-%20Amalgam.mp3',
      );
    });
  });
}
