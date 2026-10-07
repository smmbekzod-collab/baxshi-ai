import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../shared/report_view.dart';
import '../../../shared/quality_panel.dart';
import '../../../l10n/strings.dart';
import '../domain/report.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => ReportView(
    builder: (report, lang) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(lang, 'analytics'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${report.school.name} · ${report.createdAt.toLocal().toString().split('.').first}',
              ),
              Text(
                '${tr(lang, 'reference')}: ${report.referenceLabel.isEmpty ? report.referenceId : report.referenceLabel} · ${report.modelVersion}',
              ),
              if (report.technicalReference)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'TEXNIK SINOV: bu sun’iy signal bilan taqqoslash. Baxshichilik maktabi yoki badiiy mahorat bahosi emas.',
                    ),
                  ),
                ),
              QualityPanel(quality: report.quality),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, size) {
                  final columns = size.maxWidth >= 900
                      ? 3
                      : size.maxWidth >= 600
                      ? 2
                      : 1;
                  final width = (size.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: report.metrics
                        .map(
                          (m) => SizedBox(
                            width: width,
                            child: _MetricCard(metric: m, lang: lang),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                tr(lang, 'trend'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                children: [
                  Text(
                    '● ${tr(lang, 'you')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    '● ${tr(lang, 'reference')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (report.samples.length < 2)
                Text(tr(lang, 'unavailable'))
              else
                SizedBox(
                  height: 260,
                  child: Semantics(
                    label: tr(lang, 'trend'),
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 100,
                        minX: report.samples.first.seconds,
                        maxX: report.samples.last.seconds,
                        lineTouchData: const LineTouchData(enabled: true),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: report.samples
                                .map((s) => FlSpot(s.seconds, s.user))
                                .toList(),
                            color: Theme.of(context).colorScheme.primary,
                            isCurved: false,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: report.samples
                                .map((s) => FlSpot(s.seconds, s.reference))
                                .toList(),
                            color: Theme.of(context).colorScheme.tertiary,
                            dashArray: [6, 4],
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Center(child: Text(tr(lang, 'seconds'))),
              const SizedBox(height: 20),
              // Exact values supplement touch charts and support screen-reader users.
              if (report.samples.isNotEmpty)
                ExpansionTile(
                  title: Text('${tr(lang, 'you')} / ${tr(lang, 'reference')}'),
                  children: report.samples
                      .map(
                        (s) => ListTile(
                          title: Text('${s.seconds.toStringAsFixed(1)} s'),
                          trailing: Text(
                            '${s.user.toStringAsFixed(0)} / ${s.reference.toStringAsFixed(0)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.lang});
  final Metric metric;
  final String lang;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(lang, metric.kind.name),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          Text(
            metric.score == null
                ? tr(lang, 'unavailable')
                : '${metric.score!.toStringAsFixed(0)} / 100',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (metric.score != null) ...[
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: metric.score! / 100),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 650),
              builder: (_, value, _) =>
                  LinearProgressIndicator(value: value, minHeight: 6),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${tr(lang, 'confidence')}: ${(metric.confidence * 100).round()}%',
          ),
          if (metric.reason.isNotEmpty) Text(metric.reason),
        ],
      ),
    ),
  );
}
