import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'api_ui.dart';
import 'local_player.dart';

final referenceAudioProvider = FutureProvider.autoDispose
    .family<String, String>((ref, id) async {
      final api = ref.watch(apiProvider);
      final r = await api.dio.get<Map<String, dynamic>>('/v1/assets/$id');
      return ref
          .watch(audioCacheProvider)
          .get(
            r.data!['sha256'] as String,
            '/v1/assets/$id/content',
            extension: r.data!['mime'] == 'audio/wav' ? 'wav' : 'm4a',
          );
    });

class ReferencePlayer extends ConsumerWidget {
  const ReferencePlayer({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(referenceAudioProvider(assetId))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => TextButton(
          onPressed: () => ref.invalidate(referenceAudioProvider(assetId)),
          child: Text(errorMessage(e)),
        ),
        data: (path) => LocalPlayer(
          key: ValueKey(path),
          path: path,
          playLabel: 'Etalonni tinglash',
          errorLabel: 'Audio ochilmadi',
        ),
      );
}
