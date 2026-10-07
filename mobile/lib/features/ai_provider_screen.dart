import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../shared/api_ui.dart';

class AiProviderScreen extends ConsumerStatefulWidget {
  const AiProviderScreen({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  ConsumerState<AiProviderScreen> createState() => _AiProviderState();
}

class _AiProviderState extends ConsumerState<AiProviderScreen> {
  late String provider;
  late bool enabled;
  late bool configured;
  late final TextEditingController model;
  late final TextEditingController key;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    provider = widget.config['provider'] as String? ?? 'local';
    enabled = widget.config['enabled'] == true;
    configured = widget.config['key_configured'] == true;
    model = TextEditingController(text: widget.config['model'] as String? ?? '');
    key = TextEditingController();
  }

  @override
  void dispose() {
    model.dispose();
    key.dispose();
    super.dispose();
  }

  Future<void> save({bool clearKey = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final response = await ref.read(apiProvider).dio.put<Map<String, dynamic>>(
        '/v1/admin/ai-provider',
        data: {
          'provider': provider,
          'model': model.text.trim(),
          'enabled': clearKey ? false : enabled,
          'api_key': key.text,
          'clear_api_key': clearKey,
        },
      );
      if (!mounted) return;
      model.text = model.text.trim();
      setState(() {
        provider = response.data?['provider'] as String? ?? provider;
        enabled = response.data?['enabled'] == true;
        configured = response.data?['key_configured'] == true;
      });
      key.clear();
      ref.invalidate(dataProvider('/v1/admin/ai-provider'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI sozlamalari saqlandi. Kalit serverda shifrlanadi.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> testConnection() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final response = await ref
          .read(apiProvider)
          .dio
          .post<Map<String, dynamic>>('/v1/admin/ai-provider/test');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ulanish ishladi: ${response.data?['provider']}')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('AI provayderi (ixtiyoriy)', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'Ovoz fayli tashqi AI ga yuborilmaydi. AI Coach faqat anonim akustik metrikalarni yuboradi. Kalit faqat serverda saqlanadi.',
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        initialValue: provider,
        decoration: const InputDecoration(labelText: 'Provayder'),
        items: const [
          DropdownMenuItem(value: 'local', child: Text('Lokal (API ishlatilmaydi)')),
          DropdownMenuItem(value: 'xai', child: Text('xAI / Grok')),
          DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
          DropdownMenuItem(value: 'openai', child: Text('OpenAI / ChatGPT')),
        ],
        onChanged: busy
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  provider = value;
                  if (value == 'local') enabled = false;
                });
              },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: model,
        enabled: !busy,
        decoration: const InputDecoration(
          labelText: 'Model ID',
          hintText: 'Provayderdagi model identifikatori',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: key,
        enabled: !busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: configured ? 'Yangi kalit (bo‘sh qoldirilsa eskisi qoladi)' : 'API kaliti',
          helperText: 'Kalit GET javobida qaytmaydi.',
        ),
      ),
      if (configured)
        TextButton.icon(
          onPressed: busy ? null : () => save(clearKey: true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Saqlangan kalitni o‘chirish'),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('AI Coach uchun yoqish'),
        subtitle: const Text('O‘chirilsa lokal tavsiya ishlaydi.'),
        value: enabled,
        onChanged: busy || provider == 'local'
            ? null
            : (value) => setState(() => enabled = value),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => save(),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Saqlash'),
          ),
          OutlinedButton.icon(
            onPressed: busy || !configured ? null : testConnection,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Ulanishni sinash'),
          ),
        ],
      ),
      if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      const SizedBox(height: 18),
      const Text(
        'API limit tugasa, yangi kalitni kiriting va saqlang. Ulanishni sinash provayderga bitta kichik so‘rov yuboradi.',
      ),
    ],
  );
}
