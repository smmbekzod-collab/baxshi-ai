import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/api_ui.dart';

final lessonsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(accountProvider);
  try {
    final response = await ref
        .watch(apiProvider)
        .dio
        .get<List<dynamic>>('/v1/lessons');
    return response.data!
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
  } on DioException catch (e) {
    if (e.response != null) rethrow;
    final raw =
        jsonDecode(await rootBundle.loadString('assets/lessons.json')) as List;
    return raw
        .map(
          (x) => {
            ...Map<String, dynamic>.from(x as Map),
            'offline': true,
            'questions': <dynamic>[],
          },
        )
        .toList();
  }
});

class LearningScreen extends ConsumerWidget {
  const LearningScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(lessonsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(lessonsProvider),
            child: Text(errorMessage(e)),
          ),
        ),
        data: (lessons) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(lessonsProvider);
            await ref.read(lessonsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'O‘rganish yo‘li',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text(
                'Tinglang → mashq qiling → yozing → ustoz bilan muhokama qiling.',
              ),
              const SizedBox(height: 16),
              if (lessons.isEmpty)
                const Text(
                  'Darslar hali joylanmagan. Xabarlar orqali administratordan o‘quv materiallarini so‘rang.',
                ),
              for (final lesson in lessons)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      child: Icon(
                        lesson['progress']?['completed'] == true
                            ? Icons.check
                            : Icons.menu_book,
                      ),
                    ),
                    title: Text('${lesson['title']}'),
                    subtitle: Text(
                      '${lesson['level']} • ${lesson['minutes']} daqiqa${lesson['offline'] == true ? ' • offline matn' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LessonPage(lesson: lesson),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Ustoz joylagan materiallar',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DataView(
                path: '/v1/contents',
                builder: (d) => Column(
                  children: [
                    for (final x in d as List)
                      Card(
                        child: ExpansionTile(
                          title: Text('${x['title']}'),
                          subtitle: Text('${x['kind']}'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                '${x['body']}\n${x['url'] ?? ''}',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.lesson});
  final Map<String, dynamic> lesson;
  @override
  ConsumerState<LessonPage> createState() => _Lesson();
}

class _Lesson extends ConsumerState<LessonPage> {
  late final List<int?> answers;
  bool busy = false;
  Map<String, dynamic>? result;
  @override
  void initState() {
    super.initState();
    answers = List<int?>.filled(
      (widget.lesson['questions'] as List).length,
      null,
    );
  }

  Future<void> submit() async {
    if (busy || answers.any((x) => x == null)) return;
    setState(() => busy = true);
    await act(context, () async {
      final r = await ref
          .read(apiProvider)
          .dio
          .post<Map<String, dynamic>>(
            '/v1/lessons/${widget.lesson['id']}/quiz',
            data: {'answers': answers},
          );
      if (!mounted) return;
      setState(() => result = r.data);
      ref.invalidate(lessonsProvider);
      ref.invalidate(dataProvider('/v1/dashboard'));
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    final qs = l['questions'] as List;
    return Scaffold(
      appBar: AppBar(title: Text('${l['title']}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Chip(label: Text('${l['minutes']} daqiqa • namunaviy dars')),
          SelectableText(
            '${l['body']}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 24),
          if (qs.isNotEmpty)
            Text(
              'Bilimingizni tekshiring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          for (var i = 0; i < qs.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ${qs[i]['prompt']}'),
                    const SizedBox(height: 10),
                    for (var j = 0; j < (qs[i]['options'] as List).length; j++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  answers[i] = j;
                                  result = null;
                                }),
                          icon: Icon(
                            answers[i] == j
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          label: Text('${qs[i]['options'][j]}'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (qs.isNotEmpty)
            FilledButton(
              onPressed: busy || answers.any((x) => x == null) ? null : submit,
              child: Text(busy ? 'Tekshirilmoqda…' : 'Javoblarni tekshirish'),
            ),
          if (result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Natija: ${result!['score']}% • ${result!['correct']}/${result!['total']}',
                    ),
                    Text(
                      result!['completed'] == true
                          ? 'Dars yakunlangan deb saqlandi.'
                          : 'Matnni qayta ko‘rib, yana urinib ko‘ring.',
                    ),
                    for (var i = 0; i < (result!['review'] as List).length; i++)
                      Text(
                        '${i + 1}. ${result!['review'][i]['correct'] == true ? '✓' : '↺'} ${result!['review'][i]['correct_option']}',
                      ),
                  ],
                ),
              ),
            ),
          if (l['offline'] == true)
            const Text(
              'Matn offline ochildi. Test natijasini saqlash uchun internet kerak.',
            ),
        ],
      ),
    );
  }
}

class LearningHome extends ConsumerWidget {
  const LearningHome({super.key, required this.navigate});
  final void Function(int) navigate;
  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(dataProvider('/v1/dashboard'));
      ref.invalidate(dataProvider('/v1/system/status'));
    },
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Ovozingiz ustida har kuni ishlang',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('Bugungi maqsad: bitta jumla, bitta aniq yaxshilanish.'),
        const SizedBox(height: 20),
        DataView(
          path: '/v1/dashboard',
          builder: (d) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salom, ${d['name']}!',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stat(
                    context,
                    'Darslar',
                    '${d['completed_lessons']}/${d['total_lessons']}',
                    Icons.menu_book,
                  ),
                  _stat(
                    context,
                    'Mashq',
                    '${d['practice_minutes']} min',
                    Icons.timer_outlined,
                  ),
                  _stat(
                    context,
                    'Tahlillar',
                    '${d['reports']}',
                    Icons.insights,
                  ),
                ],
              ),
              if (d['next_lesson'] != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.play_lesson_outlined),
                    title: Text('Keyingi dars: ${d['next_lesson']['title']}'),
                    subtitle: Text('${d['next_lesson']['minutes']} daqiqa'),
                    onTap: () => navigate(4),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => navigate(1),
          icon: const Icon(Icons.mic),
          label: const Text('Yangi mashq yozish'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => navigate(6),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Ustozga savol berish'),
        ),
        const SizedBox(height: 16),
        DataView(
          path: '/v1/system/status',
          builder: (d) {
            final ok =
                d['worker_online'] == true && d['ffmpeg_available'] == true;
            return Card(
              child: ListTile(
                leading: Icon(
                  ok ? Icons.check_circle_outline : Icons.warning_amber,
                ),
                title: Text(
                  ok
                      ? 'Ovoz tahlili xizmati tayyor'
                      : 'Tahlil xizmati tayyor emas',
                ),
                subtitle: Text(
                  ok
                      ? 'Navbatda: ${d['queued']} ta'
                      : 'Administrator worker va FFmpeg holatini tekshirishi kerak. Yozuvingizni mahalliy saqlashingiz mumkin.',
                ),
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Akustik o‘lchovlar mashq uchun yordamchi. Ustozning badiiy bahosini almashtirmaydi.',
          ),
        ),
      ],
    ),
  );
  Widget _stat(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(title),
          ],
        ),
      ),
    ),
  );
}
