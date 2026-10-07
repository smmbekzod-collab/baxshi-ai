import 'package:flutter/material.dart';

class QualityPanel extends StatelessWidget {
  const QualityPanel({super.key, required this.quality});
  final Map<String, dynamic> quality;
  @override
  Widget build(BuildContext context) {
    if (quality.isEmpty) return const SizedBox.shrink();
    String number(String k, {String suffix = ''}) =>
        quality[k] == null ? 'Aniqlanmadi' : '${quality[k]}$suffix';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O‘lchangan ovoz xususiyatlari',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('Etalonsiz ham hisoblanadi. Bu mahorat foizi emas.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                Chip(
                  label: Text(
                    'Davomiylik: ${number('duration_seconds', suffix: ' s')}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Ovoz darajasi: ${number('rms_dbfs', suffix: ' dBFS')}',
                  ),
                ),
                Chip(
                  label: Text(
                    'O‘rta chastota: ${number('median_pitch_hz', suffix: ' Hz')}',
                  ),
                ),
                if (quality['voiced_coverage'] is num)
                  Chip(
                    label: Text(
                      'Ovozli kadrlar: ${((quality['voiced_coverage'] as num) * 100).round()}%',
                    ),
                  ),
                if (quality['clipping_ratio'] is num)
                  Chip(
                    label: Text(
                      'Clipping: ${((quality['clipping_ratio'] as num) * 100).toStringAsFixed(2)}%',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
