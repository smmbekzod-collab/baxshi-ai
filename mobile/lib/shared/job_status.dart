import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import 'api_ui.dart';

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
                Text('Tahlil: ${j['status']}'),
                if (j['error_code'] != null) Text('${j['error_code']}'),
                if (j['status'] == 'completed')
                  TextButton(
                    onPressed: () {
                      ref
                          .read(selectedReportProvider.notifier)
                          .select(j['report_id'] as String?);
                      ref.invalidate(reportProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Natija tayyor. Tahlil bo‘limini oching.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Tahlilni yangilash'),
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
