import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'api_ui.dart';
import '../features/analysis/presentation/analytics_screen.dart';
import '../features/coach/presentation/coach_screen.dart';

final jobProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async* {
      var active = true;
      ref.onDispose(() => active = false);
      while (active) {
        final data =
            (await ref
                    .read(apiProvider)
                    .dio
                    .get<Map<String, dynamic>>('/v1/analyses/$id'))
                .data!;
        if (!active) return;
        yield data;
        if (['completed', 'failed', 'cancelled'].contains(data['status'])) {
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    });

class JobStatus extends ConsumerWidget {
  const JobStatus({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(jobProvider(id))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => TextButton(
          onPressed: () => ref.invalidate(jobProvider(id)),
          child: Text(errorMessage(e)),
        ),
        data: (j) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Tahlil: ${const {'queued': 'Navbatda', 'running': 'Hisoblanmoqda', 'completed': 'Tayyor', 'failed': 'Yakunlanmadi', 'cancelled': 'Bekor qilingan'}[j['status']] ?? j['status']}',
                ),
                if (j['error_code'] != null)
                  Text(
                    analysisError('${j['error_code']}') ??
                        'Tahlil yakunlanmadi. Administratorga yozing.',
                  ),
                if (j['status'] == 'queued')
                  const Text(
                    'Agar holat uzoq o‘zgarmasa, Bosh sahifadagi tahlil xizmati holatini tekshiring.',
                  ),
                if (j['status'] == 'failed')
                  TextButton(
                    onPressed: () => act(context, () async {
                      await ref
                          .read(apiProvider)
                          .dio
                          .post<void>('/v1/analyses/$id/retry');
                      ref.invalidate(jobProvider(id));
                    }),
                    child: const Text('Qayta urinish'),
                  ),
                if (j['status'] == 'completed')
                  TextButton(
                    onPressed: () {
                      ref
                          .read(selectedReportProvider.notifier)
                          .select(j['report_id'] as String?);
                      ref.invalidate(reportProvider);
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DefaultTabController(
                            length: 2,
                            child: Scaffold(
                              appBar: AppBar(
                                title: const Text('Tahlil natijasi'),
                                bottom: const TabBar(
                                  tabs: [
                                    Tab(text: 'Tahlil'),
                                    Tab(text: 'Coach'),
                                  ],
                                ),
                              ),
                              body: const TabBarView(
                                children: [AnalyticsScreen(), CoachScreen()],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Natijani ochish'),
                  ),
                if (['queued', 'running'].contains(j['status']))
                  TextButton(
                    onPressed: () => act(context, () async {
                      await ref
                          .read(apiProvider)
                          .dio
                          .post<void>('/v1/analyses/$id/cancel');
                      ref.invalidate(jobProvider(id));
                    }),
                    child: const Text('Bekor qilish'),
                  ),
              ],
            ),
          ),
        ),
      );
}
