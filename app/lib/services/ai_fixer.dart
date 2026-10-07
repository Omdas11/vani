import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Error thrown by [AiFixer] for key, network, and response problems.
/// The [message] is safe to show directly to the user.
class AiFixerException implements Exception {
  final String message;
  const AiFixerException(this.message);

  @override
  String toString() => 'AiFixerException: $message';
}

/// One AI backend the fixer can talk to. Each provider keeps its own API
/// key in secure storage under a distinct key name; keys are never logged
/// or printed.
class AiProvider {
  final String id;
  final String name;
  final String keyName;
  final String keyHint;

  const AiProvider({
    required this.id,
    required this.name,
    required this.keyName,
    required this.keyHint,
  });

  static const gemini = AiProvider(
    id: 'gemini',
    name: 'Gemini',
    keyName: 'ai_key_gemini',
    keyHint: 'Free key at Google AI Studio (aistudio.google.com).',
  );
  static const openrouter = AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    keyName: 'ai_key_openrouter',
    keyHint: 'Key at openrouter.ai/keys — many models have a free tier.',
  );
  static const custom = AiProvider(
    id: 'custom',
    name: 'Custom (OpenAI-compatible)',
    keyName: 'ai_key_custom',
    keyHint: 'Your own endpoint, e.g. a local Ollama or LM Studio server.',
  );

  static const List<AiProvider> all = [gemini, openrouter, custom];

  static AiProvider byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => gemini);
}

/// "AI Fixer (beta)": cleans up messy local/Drive track filenames and
/// metadata using the user's own API key, called directly from the phone.
///
/// Supported providers: Gemini, OpenRouter, or any custom
/// OpenAI-compatible endpoint. Keys live in platform secure storage and
/// are sent only to the selected provider; nothing is uploaded anywhere
/// else. Cover art comes from free keyless sources (iTunes Search API,
/// then MusicBrainz + Cover Art Archive) — never image scraping.
///
/// The prompt builders, parsers, [sanitizeFilename], and the CoverArt
/// URL/parse helpers are static and side-effect free so they can be
/// unit tested without network.
class AiFixer {
  /// v1 key name; migrated to [AiProvider.gemini].keyName on first read.
  static const String _legacyGeminiKey = 'gemini_api_key';

  static const String providerPrefsKey = 'ai_fix_provider';
  static const String customBaseUrlPrefsKey = 'ai_fix_custom_base_url';
  static const String customModelPrefsKey = 'ai_fix_custom_model';

  /// Default model for the OpenRouter provider.
  static const String openRouterModel = 'openai/gpt-4o-mini';

  /// Default model for a custom endpoint (user-editable in the UI).
  static const String defaultCustomModel = 'gpt-4o-mini';

  static const String _geminiModelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  final FlutterSecureStorage _storage;

  AiFixer({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // ---------- provider selection ----------

  /// The currently selected provider (defaults to Gemini).
  Future<AiProvider> selectedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return AiProvider.byId(prefs.getString(providerPrefsKey));
  }

  Future<void> setProvider(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(providerPrefsKey, AiProvider.byId(id).id);
  }

  Future<String> customBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(customBaseUrlPrefsKey) ?? '';
  }

  Future<void> setCustomBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(customBaseUrlPrefsKey, url.trim());
  }

  Future<String> customModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(customModelPrefsKey) ?? defaultCustomModel;
  }

  Future<void> setCustomModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(customModelPrefsKey, model.trim());
  }

  // ---------- API keys ----------

  /// Reads the stored key for [p], migrating the v1 Gemini key name.
  /// Returns null when no key is stored. Never logs the value.
  Future<String?> _readKey(AiProvider p) async {
    var key = await _storage.read(key: p.keyName);
    if ((key == null || key.trim().isEmpty) && p.id == AiProvider.gemini.id) {
      final legacy = await _storage.read(key: _legacyGeminiKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _storage.write(key: p.keyName, value: legacy.trim());
        await _storage.delete(key: _legacyGeminiKey);
        key = legacy;
      }
    }
    final trimmed = key?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// True when the selected provider has a (non-empty) API key stored.
  Future<bool> hasKey() async => hasKeyFor(await selectedProvider());

  /// True when [p] has a (non-empty) API key stored.
  Future<bool> hasKeyFor(AiProvider p) async => await _readKey(p) != null;

  /// Stores a key for the selected provider, replacing any existing one.
  Future<void> setKey(String key) async =>
      setKeyFor(await selectedProvider(), key);

  /// Stores a key for [p], replacing any existing one.
  Future<void> setKeyFor(AiProvider p, String key) {
    if (key.trim().isEmpty) {
      throw const AiFixerException('Paste your key first, then tap Save.');
    }
    return _storage.write(key: p.keyName, value: key.trim());
  }

  /// Deletes the selected provider's stored key.
  Future<void> clearKey() async => clearKeyFor(await selectedProvider());

  /// Deletes [p]'s stored key.
  Future<void> clearKeyFor(AiProvider p) => _storage.delete(key: p.keyName);

  // ---------- unified completion ----------

  /// Sends [prompt] to the selected provider and returns the raw
  /// response text. Throws [AiFixerException] on missing key, HTTP
  /// errors, network failures, or an unparsable response. The key is
  /// never included in any error message.
  Future<String> complete(String prompt) async {
    final provider = await selectedProvider();
    final apiKey = await _readKey(provider);
    if (apiKey == null || apiKey.isEmpty) {
      throw AiFixerException(
          'No ${provider.name} API key saved. Save your key first.');
    }
    // NOTE: case labels use literals because AiProvider.id is not a
    // constant expression, even on const instances.
    switch (provider.id) {
      case 'openrouter':
        return _completeOpenAi(
          url: openAiCompletionsUrl('https://openrouter.ai/api/v1'),
          apiKey: apiKey,
          prompt: prompt,
          model: openRouterModel,
          extraHeaders: const {
            'HTTP-Referer': 'https://github.com/Omdas11/vani',
            'X-Title': 'Vani',
          },
        );
      case 'custom':
        final base = await customBaseUrl();
        if (base.isEmpty) {
          throw const AiFixerException(
              'Set your custom provider base URL first.');
        }
        return _completeOpenAi(
          url: openAiCompletionsUrl(base),
          apiKey: apiKey,
          prompt: prompt,
          model: await customModel(),
        );
      case 'gemini':
      default:
        return _completeGemini(prompt, apiKey);
    }
  }

  /// Builds "<baseUrl>/chat/completions", tolerating a trailing slash
  /// on the base URL. Public for testing.
  static String openAiCompletionsUrl(String baseUrl) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/chat/completions';
  }

  /// OpenAI-style auth headers. Public for testing; the key value is
  /// only ever placed in the header, never in logs or errors.
  static Map<String, String> openAiHeaders(String apiKey,
      {Map<String, String>? extra}) {
    return {
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json',
      ...?extra,
    };
  }

  /// OpenAI-style chat body. Public for testing.
  static String openAiBody({required String prompt, required String model}) {
    return jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.2,
    });
  }

  /// Pulls choices[0].message.content out of an OpenAI-style chat
  /// response body. Returns null when the shape is unexpected.
  /// Public for testing.
  static String? extractOpenAiText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices[0] as Map<String, dynamic>)['message'];
      if (message is! Map<String, dynamic>) return null;
      final content = message['content'];
      if (content is String && content.isNotEmpty) return content;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _completeOpenAi({
    required String url,
    required String apiKey,
    required String prompt,
    required String model,
    Map<String, String>? extraHeaders,
  }) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: openAiHeaders(apiKey, extra: extraHeaders),
            body: openAiBody(prompt: prompt, model: model),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const AiFixerException(
          'Could not reach the AI provider. Check your connection and '
          'try again.');
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw const AiFixerException(
            'Invalid API key. Double-check the key you saved.');
      }
      if (response.statusCode == 429) {
        throw const AiFixerException('Quota exceeded — try again later.');
      }
      throw AiFixerException(
          'AI request failed (HTTP ${response.statusCode}).');
    }

    final text = extractOpenAiText(response.body);
    if (text == null || text.isEmpty) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return text;
  }

  Future<String> _completeGemini(String prompt, String apiKey) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_geminiModelUrl),
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.2,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const AiFixerException(
          'Could not reach Gemini. Check your connection and try again.');
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 400) {
        throw const AiFixerException(
            'Invalid API key. Double-check the key you saved.');
      }
      if (response.statusCode == 429) {
        throw const AiFixerException('Quota exceeded — try again later.');
      }
      throw AiFixerException(
          'Gemini request failed (HTTP ${response.statusCode}).');
    }

    final text = _extractResponseText(response.body);
    if (text == null || text.isEmpty) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return text;
  }

  /// Pulls candidates[0].content.parts[0].text out of a generateContent
  /// response body. Returns null when the shape is unexpected.
  static String? _extractResponseText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = (candidates[0] as Map<String, dynamic>)['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = (parts[0] as Map<String, dynamic>)['text'];
      return text is String ? text : null;
    } catch (_) {
      return null;
    }
  }

  // ---------- filename sanitation ----------

  /// Sanitizes [filename] (basename with extension) for the
  /// "Artist - Title.ext" convention:
  /// - strips `<>:"/\|?*` and control chars from the stem,
  /// - trims trailing dots/spaces (Windows-hostile),
  /// - caps the total length at ~120 chars (extension preserved),
  /// - falls back to "track" when nothing usable remains.
  /// Public for testing.
  static String sanitizeFilename(String filename) {
    var name = filename.trim();
    final sep = name.lastIndexOf(RegExp(r'[/\\]'));
    final dot = name.lastIndexOf('.');
    String stem;
    String ext;
    if (dot > sep) {
      stem = name.substring(0, dot);
      ext = name.substring(dot);
    } else {
      stem = name;
      ext = '';
    }
    stem = stem.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '');
    stem = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
    stem = stem.replaceAll(RegExp(r'[. ]+$'), '');
    ext = ext.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f\s]'), '');
    if (stem.isEmpty) stem = 'track';
    const maxTotal = 120;
    if (stem.length + ext.length > maxTotal) {
      stem = stem.substring(0, maxTotal - ext.length).trimRight();
      stem = stem.replaceAll(RegExp(r'[. ]+$'), '');
      if (stem.isEmpty) stem = 'track';
    }
    return '$stem$ext';
  }

  // ---------- prompts (unchanged v1 contracts) ----------

  /// Builds the prompt that cleans a messy song filename.
  static String filenamePrompt(String filename) {
    return '''
You are a music file organizer. Clean up this messy song filename.

Rules:
- Strip junk tokens: lyrical/video tags like "(Official Video)" or "[Lyrics]", bitrates like "320kbps", uploader names, site watermarks, and duplicate numbers.
- Keep the "Artist - Title" format when the filename already has one. Separate artist and title with " - ".
- Fix obvious capitalization mistakes, but never invent words the filename does not hint at.
- Preserve the file extension exactly as-is (including its case).

Respond with ONLY valid JSON, no markdown fences, no explanation:
{"filename":"<cleaned filename>"}

Filename: "$filename"
''';
  }

  /// Builds the prompt that fixes messy title/artist metadata.
  static String metadataPrompt(String title, String artist) {
    return '''
You are a music metadata cleaner. Fix the title and artist below.

Rules:
- If the title looks like "Artist - Title", split it into the two fields correctly.
- Fix capitalization (natural title case for songs, proper case for artist names).
- Drop junk: "(Official Video)", "[Lyrics]", bitrates, uploader tags, extra punctuation.
- If the artist is "Unknown artist" (or missing) but a real artist is identifiable from the title, use it; otherwise keep "Unknown artist".

Respond with ONLY valid JSON, no markdown fences, no explanation:
{"title":"<cleaned title>","artist":"<cleaned artist>"}

Title: "$title"
Artist: "$artist"
''';
  }

  /// Extracts a JSON object from [text], tolerating ```json fences and
  /// surrounding prose. Never throws; returns {} when nothing usable
  /// is found.
  static Map<String, dynamic> _decodeJsonObject(String text) {
    var cleaned = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final match = fence.firstMatch(cleaned);
    if (match != null) cleaned = match.group(1)!.trim();
    final direct = _tryDecode(cleaned);
    if (direct != null) return direct;
    // Fallback: slice out the outermost {...} span in case of prose.
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final sliced = _tryDecode(cleaned.substring(start, end + 1));
      if (sliced != null) return sliced;
    }
    return {};
  }

  static Map<String, dynamic>? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Parses the AI response for a filename fix into {'filename': ...}.
  /// Never throws; returns {} when the response has no usable filename.
  static Map<String, String> parseFilenameFix(String jsonText) {
    final value = _decodeJsonObject(jsonText)['filename'];
    if (value is String && value.trim().isNotEmpty) {
      return {'filename': value.trim()};
    }
    return {};
  }

  /// Parses the AI response for a metadata fix into {'title': ..., 'artist': ...}.
  /// Never throws; returns {} (or a partial map) when values are missing.
  static Map<String, String> parseMetadataFix(String jsonText) {
    final obj = _decodeJsonObject(jsonText);
    final out = <String, String>{};
    for (final key in ['title', 'artist']) {
      final value = obj[key];
      if (value is String && value.trim().isNotEmpty) {
        out[key] = value.trim();
      }
    }
    return out;
  }

  /// Asks the AI to clean [filename] (basename with extension).
  /// Returns {'filename': cleanedName} with the name sanitized for the
  /// filesystem. Throws [AiFixerException] on failure.
  Future<Map<String, String>> fixFilename(String filename) async {
    final text = await complete(filenamePrompt(filename));
    final parsed = parseFilenameFix(text);
    final name = parsed['filename'];
    if (name == null || name.isEmpty) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return {'filename': sanitizeFilename(name)};
  }

  /// Asks the AI to fix messy [title]/[artist] metadata.
  /// Returns a map with any of 'title'/'artist' that have fixes.
  /// Throws [AiFixerException] on failure.
  Future<Map<String, String>> fixMetadata(
      {required String title, required String artist}) async {
    final text = await complete(metadataPrompt(title, artist));
    final parsed = parseMetadataFix(text);
    if (parsed.isEmpty) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return parsed;
  }
}

/// Cover art lookup from free, keyless sources ONLY: the iTunes Search
/// API first, then MusicBrainz + the Cover Art Archive. Never image
/// scraping. All URL builders and response parsers are static and
/// side-effect free so they can be unit tested without network.
class CoverArt {
  static const userAgent = 'Vani/1.5';
  static const _lookupTimeout = Duration(seconds: 15);

  /// iTunes Search API URL for a song query. Public for testing.
  static String itunesSearchUrl({
    required String artist,
    required String title,
  }) {
    final parts = [artist.trim(), title.trim()].where(
        (s) => s.isNotEmpty && s != 'Unknown artist' && s != 'Unknown title');
    return Uri.https('itunes.apple.com', '/search', {
      'term': parts.join(' '),
      'media': 'music',
      'entity': 'song',
      'limit': '5',
    }).toString();
  }

  /// Picks the best artwork URL from an iTunes search response,
  /// upscaled from 100x100 to 600x600. Returns null when nothing usable
  /// is found. Never throws. Public for testing.
  static String? parseItunesArtwork(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final results = decoded['results'];
      if (results is! List) return null;
      for (final r in results.whereType<Map<String, dynamic>>()) {
        final url = r['artworkUrl100'];
        if (url is String && url.trim().isNotEmpty) {
          return upscaleItunes(url.trim());
        }
      }
    } catch (_) {}
    return null;
  }

  /// iTunes artwork URLs embed their size ("…/100x100bb.jpg"); swap it
  /// for the 600px variant. Public for testing.
  static String upscaleItunes(String url) =>
      url.replaceFirst('100x100', '600x600');

  /// MusicBrainz recording search URL (JSON). Public for testing.
  static String musicBrainzUrl({
    required String artist,
    required String title,
  }) {
    return Uri.https('musicbrainz.org', '/ws/2/recording/', {
      'query': 'recording:"${title.trim()}" AND artist:"${artist.trim()}"',
      'fmt': 'json',
      'limit': '5',
    }).toString();
  }

  /// First release MBID of the first recording hit, or null.
  /// Never throws. Public for testing.
  static String? parseMusicBrainzReleaseId(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final recordings = decoded['recordings'];
      if (recordings is! List || recordings.isEmpty) return null;
      final releases = (recordings.first as Map<String, dynamic>)['releases'];
      if (releases is! List || releases.isEmpty) return null;
      final id = (releases.first as Map<String, dynamic>)['id'];
      return (id is String && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Cover Art Archive front-cover URL for a release MBID.
  /// Public for testing.
  static String coverArtArchiveUrl(String releaseMbid) =>
      'https://coverartarchive.org/release/$releaseMbid/front-500';

  /// Filesystem-safe artwork filename for a track id.
  /// Public for testing.
  static String fileNameForId(String trackId) {
    final safe = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${safe.isEmpty ? 'artwork' : safe}.jpg';
  }

  /// App documents subdir where downloaded covers live.
  static Future<Directory> artworkDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/opentune/artwork');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns a direct image URL for the track, or null when neither
  /// source has one. Call only from a user tap — never in a blind loop.
  static Future<String?> findArtworkUrl({
    required String artist,
    required String title,
  }) async {
    // iTunes first.
    try {
      final res = await http.get(
        Uri.parse(itunesSearchUrl(artist: artist, title: title)),
        headers: {'User-Agent': userAgent},
      ).timeout(_lookupTimeout);
      if (res.statusCode == 200) {
        final url = parseItunesArtwork(res.body);
        if (url != null) return url;
      }
    } catch (_) {}
    // MusicBrainz + Cover Art Archive fallback.
    try {
      final mb = await http.get(
        Uri.parse(musicBrainzUrl(artist: artist, title: title)),
        headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
      ).timeout(_lookupTimeout);
      if (mb.statusCode != 200) return null;
      final mbid = parseMusicBrainzReleaseId(mb.body);
      if (mbid == null) return null;
      final caaUrl = coverArtArchiveUrl(mbid);
      final art = await http.get(Uri.parse(caaUrl),
          headers: {'User-Agent': userAgent}).timeout(_lookupTimeout);
      if (art.statusCode == 200 &&
          (art.headers['content-type'] ?? '').startsWith('image/')) {
        return caaUrl;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads [imageUrl] to [destPath], verifying the response is an
  /// image. Returns true on success, false on any failure.
  static Future<bool> download(String imageUrl, String destPath) async {
    try {
      final res = await http.get(Uri.parse(imageUrl), headers: {
        'User-Agent': userAgent
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      if (!(res.headers['content-type'] ?? '').startsWith('image/')) {
        return false;
      }
      if (res.bodyBytes.isEmpty) return false;
      final file = File(destPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(res.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
