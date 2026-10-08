import 'package:flutter/material.dart';

import '../services/ai_fixer.dart';

/// "AI provider" settings card (BETA), self-contained and embeddable
/// anywhere: pick the provider (Gemini / OpenRouter / custom
/// OpenAI-compatible endpoint), save/clear the per-provider API key,
/// configure the custom endpoint, and test the connection.
///
/// Key storage: flutter_secure_storage under `ai_key_gemini`,
/// `ai_key_openrouter`, or `ai_key_custom`. The selected provider id is
/// persisted in SharedPreferences (`ai_fix_provider`). Keys are never
/// logged or printed; error messages are user-safe.
class AiProviderCard extends StatefulWidget {
  const AiProviderCard({super.key});

  @override
  State<AiProviderCard> createState() => _AiProviderCardState();
}

class _AiProviderCardState extends State<AiProviderCard> {
  final AiFixer _fixer = AiFixer();
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _baseCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  AiProvider _provider = AiProvider.gemini;
  bool _hasKey = false;
  bool _busy = false;
  bool _testing = false;
  String? _status;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = await _fixer.selectedProvider();
    final has = await _fixer.hasKeyFor(provider);
    final base = await _fixer.customBaseUrl();
    final model = await _fixer.customModel();
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _hasKey = has;
      if (_baseCtrl.text.isEmpty) _baseCtrl.text = base;
      if (_modelCtrl.text.isEmpty) _modelCtrl.text = model;
    });
  }

  Future<void> _selectProvider(AiProvider? p) async {
    if (p == null || p.id == _provider.id) return;
    setState(() {
      _provider = p;
      _status = null;
      _testResult = null;
      _keyCtrl.clear();
    });
    try {
      await _fixer.setProvider(p.id);
      final has = await _fixer.hasKeyFor(p);
      if (mounted) setState(() => _hasKey = has);
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not save the provider.');
    }
  }

  Future<void> _saveKey() async {
    final value = _keyCtrl.text.trim();
    if (value.isEmpty) {
      setState(() => _status = 'Paste your key first, then tap Save.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _testResult = null;
    });
    try {
      await _fixer.setKeyFor(_provider, value);
      _keyCtrl.clear();
      final has = await _fixer.hasKeyFor(_provider);
      if (mounted) {
        setState(() {
          _hasKey = has;
          _status = 'Key saved on this device.';
        });
      }
    } on AiFixerException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not save the key.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearKey() async {
    setState(() => _busy = true);
    try {
      await _fixer.clearKeyFor(_provider);
      final has = await _fixer.hasKeyFor(_provider);
      if (mounted) {
        setState(() {
          _hasKey = has;
          _status = 'Key removed.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not remove the key.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEndpoint() async {
    setState(() => _busy = true);
    try {
      await _fixer.setCustomBaseUrl(_baseCtrl.text);
      await _fixer.setCustomModel(_modelCtrl.text.isEmpty
          ? AiFixer.defaultCustomModel
          : _modelCtrl.text);
      if (mounted) setState(() => _status = 'Endpoint saved.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not save the endpoint.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends one tiny prompt through the selected provider to verify the
  /// key and connectivity. User-triggered only.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final out = await _fixer.complete('Reply with exactly this word: ok');
      if (!mounted) return;
      setState(() => _testResult = out.toLowerCase().contains('ok')
          ? '✓ Connected — ${_provider.name} answered.'
          : 'Connected, but the reply was unexpected. Try again.');
    } on AiFixerException catch (e) {
      if (mounted) setState(() => _testResult = '✗ ${e.message}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high_outlined,
                    color: scheme.primary),
                const SizedBox(width: 8),
                const Text('AI provider',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('BETA',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The AI Fixer calls the provider directly from your phone. '
              'Each provider keeps its own key, stored securely on this '
              'device and never shown.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AiProvider>(
              initialValue: _provider,
              items: AiProvider.all
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: _busy ? null : _selectProvider,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            Text(
              _provider.keyHint,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Paste your ${_provider.name} API key',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_provider.id == AiProvider.custom.id) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _baseCtrl,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'Base URL, e.g. http://192.168.1.5:11434/v1',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelCtrl,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Model name, e.g. llama3.1',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _saveEndpoint,
                child: const Text('Save endpoint'),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _saveKey,
                  child: const Text('Save key'),
                ),
                OutlinedButton(
                  onPressed: (_busy || !_hasKey) ? null : _clearKey,
                  child: const Text('Clear key'),
                ),
                OutlinedButton(
                  onPressed: (_busy || _testing) ? null : _test,
                  child: Text(_testing ? 'Testing…' : 'Test'),
                ),
                Text(
                  _hasKey
                      ? '✓ Key saved for ${_provider.name}.'
                      : 'No key saved for ${_provider.name}.',
                  style: TextStyle(
                    color: _hasKey ? scheme.primary : scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_status!,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_testResult!,
                    style: TextStyle(
                      color: _testResult!.startsWith('✓')
                          ? scheme.primary
                          : scheme.tertiary,
                      fontSize: 12.5,
                    )),
              ),
          ],
        ),
      ),
    );
  }
}
