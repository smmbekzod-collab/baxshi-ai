import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

final dataProvider = FutureProvider.autoDispose.family<dynamic, String>((
  ref,
  path,
) async {
  ref.watch(accountProvider);
  return (await ref.watch(apiProvider).dio.get<dynamic>(path)).data;
});
String errorMessage(Object e) {
  if (e is StateError) {
    return e.message;
  }
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      final label = analysisError(data['detail'] as String);
      if (label != null) return label;
    }
    return switch (e.response?.statusCode) {
      401 => 'Qayta kirish kerak.',
      403 => 'Bu amal uchun ruxsat yo‘q.',
      409 => 'Ma’lumot o‘zgargan yoki takrorlangan. Yangilang.',
      422 => 'Maydonlar qiymatini tekshiring.',
      429 => 'Limitga yetdingiz. Keyinroq urinib ko‘ring.',
      _ => 'Ulanish yoki server xatosi. Qayta urinib ko‘ring.',
    };
  }
  return 'Amal bajarilmadi.';
}

Future<bool> act(BuildContext context, Future<void> Function() task) async {
  try {
    await task();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
    return false;
  }
}

class DataView extends ConsumerWidget {
  const DataView({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(dynamic) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(dataProvider(path))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorMessage(e)),
              TextButton(
                onPressed: () => ref.invalidate(dataProvider(path)),
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
        data: builder,
      );
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Tasdiqlash'),
          ),
        ],
      ),
    ) ??
    false;

/// A schema-driven form: all writes pass through strict backend validation.
Future<Map<String, dynamic>?> editForm(
  BuildContext context,
  String title,
  Map<String, dynamic> initial, {
  Map<String, List<String>> choices = const {},
}) async {
  final values = Map<String, dynamic>.from(initial);
  final controllers = {
    for (final e in initial.entries)
      if (e.value is! bool)
        e.key: TextEditingController(text: e.value?.toString() ?? ''),
  };
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in initial.entries)
                  if (e.value is bool)
                    SwitchListTile(
                      title: Text(e.key),
                      value: values[e.key] as bool,
                      onChanged: (v) => set(() => values[e.key] = v),
                    )
                  else if (choices.containsKey(e.key))
                    DropdownButtonFormField<String>(
                      initialValue: values[e.key] as String,
                      decoration: InputDecoration(labelText: e.key),
                      items: choices[e.key]!
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => values[e.key] = v,
                    )
                  else
                    TextField(
                      controller: controllers[e.key],
                      obscureText: e.key.contains('password'),
                      keyboardType: e.value is num
                          ? TextInputType.number
                          : TextInputType.text,
                      maxLines: e.key.contains('password')
                          ? 1
                          : (e.key == 'body' ||
                                    e.key == 'note' ||
                                    e.key == 'instructions'
                                ? 4
                                : 1),
                      decoration: InputDecoration(labelText: e.key),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () {
              for (final e in initial.entries) {
                if (e.value is bool || choices.containsKey(e.key)) continue;
                final t = controllers[e.key]!.text;
                values[e.key] = e.value is int
                    ? int.tryParse(t)
                    : e.value is num
                    ? num.tryParse(t)
                    : t.isEmpty && e.value == null
                    ? null
                    : t;
              }
              Navigator.pop(c, values);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    ),
  );
  // Dialog's closing animation may still hold controllers; dispose next frame later.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in controllers.values) {
    c.dispose();
  }
  return result;
}

Future<void> showData(BuildContext context, String title, dynamic data) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              data is String
                  ? data
                  : const JsonEncoder.withIndent('  ').convert(data),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );

String? analysisError(String code) => const <String, String>{
  'worker_unavailable':
      'Tahlil worker’i ishlamayapti. Administrator serverni tekshirsin; yozuvingiz saqlangan.',
  'decoder_unavailable':
      'Serverda FFmpeg audio dekoderi yo‘q. Administrator Docker buildni tekshirsin.',
  'audio_too_short': 'Yozuv juda qisqa. Kamida 5 soniya yozing.',
  'audio_too_long': 'Yozuv 20 daqiqadan oshmasin.',
  'audio_too_quiet':
      'Ovoz juda past. Sokin joyda yaqinroq masofada qayta yozing.',
  'audio_clipping':
      'Ovoz buzilgan: mikrofon haddan tashqari kuchli signal olgan. Uzoqroq masofada qayta yozing.',
  'invalid_audio': 'Audio fayl ochilmadi. Yangi yozuv tayyorlang.',
  'unsupported_container': 'WAV yoki M4A formatdagi audio kerak.',
  'reference_unavailable':
      'Etalon o‘chirilgan yoki litsenziyasi tugagan. Boshqa etalon tanlang.',
  'invalid_reference': 'Etalon tanlangan maktabga mos emas yoki faol emas.',
  'media_expired':
      'Serverdagi audio saqlash muddati tugagan. Mahalliy yozuvni qayta yuboring.',
  'processing_failed':
      'Server tahlilni yakunlay olmadi. Qayta urining yoki administratorga yozing.',
  'attempt_limit': 'Qayta urinish chegarasiga yetildi. Administratorga yozing.',
  'no_report': 'Hali hisobot yo‘q. Avval ovoz yozib tahlilga yuboring.',
  'avatar_too_large': 'Rasm 3 MB dan kichik bo‘lsin.',
  'invalid_avatar': 'JPG, PNG yoki WEBP rasm tanlang.',
  'daily_quota': 'Bugungi tahlil limiti tugadi. Keyinroq urinib ko‘ring.',
  'contact_unavailable':
      'Bu kontaktga yozish ruxsati yo‘q. Administrator biriktirishni tekshirsin.',
  'upgrade_required': 'Ilovani yangi versiyaga yangilang.',
}[code];
