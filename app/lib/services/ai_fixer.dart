import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Error thrown by [AiFixer] for key, network, and response problems.
/// The [message] is safe to show directly to the user.
class AiFixerException implements Exception {
  final String message;
  const AiFixerException(this.message);

  @override
  String toString() => 'AiFixerException: $message';
}

/// "AI Fixer (beta)": cleans up messy local/Drive track filenames and
/// metadata using the user's own free Gemini API key.
///
/// The key is stored in platform secure storage and sent only to Google's
/// Gemini API; nothing is uploaded anywhere else. The [filenamePrompt],
/// [metadataPrompt], [parseFilenameFix], and [parseMetadataFix] helpers are
/// static and side-effect free so they can be unit tested without network.
class AiFixer {
  static const String keyName = 'gemini_api_key';
  static const String _modelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  final FlutterSecureStorage _storage;

  AiFixer({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// True when a (non-empty) API key is stored.
  Future<bool> hasKey() async {
    final key = await _storage.read(key: keyName);
    return key != null && key.trim().isNotEmpty;
  }

  /// Stores a new API key, replacing any existing one.
  Future<void> setKey(String key) =>
      _storage.write(key: keyName, value: key.trim());

  /// Deletes the stored API key.
  Future<void> clearKey() => _storage.delete(key: keyName);

  /// Builds the Gemini prompt that cleans a messy song filename.
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

  /// Builds the Gemini prompt that fixes messy title/artist metadata.
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

  /// Sends [prompt] to Gemini and returns the raw response text.
  /// Throws [AiFixerException] on missing key, HTTP errors, network
  /// failures, or an unparsable response.
  Future<String> _postPrompt(String prompt) async {
    final apiKey = await _storage.read(key: keyName);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AiFixerException(
          'No Gemini API key saved. Save your key below first.');
    }

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_modelUrl),
            headers: {
              'x-goog-api-key': apiKey.trim(),
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
    } on AiFixerException {
      rethrow;
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

  /// Asks the AI to clean [filename] (basename with extension).
  /// Returns {'filename': cleanedName}. Throws [AiFixerException] on failure.
  Future<Map<String, String>> fixFilename(String filename) async {
    final text = await _postPrompt(filenamePrompt(filename));
    final parsed = parseFilenameFix(text);
    if (!parsed.containsKey('filename')) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return parsed;
  }

  /// Asks the AI to fix messy [title]/[artist] metadata.
  /// Returns a map with any of 'title'/'artist' that have fixes.
  /// Throws [AiFixerException] on failure.
  Future<Map<String, String>> fixMetadata(
      {required String title, required String artist}) async {
    final text = await _postPrompt(metadataPrompt(title, artist));
    final parsed = parseMetadataFix(text);
    if (parsed.isEmpty) {
      throw const AiFixerException(
          'Could not understand the AI response. Please try again.');
    }
    return parsed;
  }
}
