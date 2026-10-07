import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'api_ui.dart';
import '../features/analysis/domain/report.dart';
import '../l10n/strings.dart';

class ReportView extends ConsumerWidget {
  const ReportView({super.key, required this.builder});
  final Widget Function(Report report, String lang) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return ref
        .watch(reportProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    lang,
                    error is StateError && error.message == 'auth'
                        ? 'auth'
                        : errorMessage(error),
                  ),
                ),
                FilledButton(
                  onPressed: () => ref.invalidate(reportProvider),
                  child: Text(tr(lang, 'retry')),
                ),
              ],
            ),
          ),
          data: (result) => Column(
            children: [
              if (result.report.demo || result.fromCache)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Text(
                    tr(lang, result.report.demo ? 'demo' : 'offline'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              Expanded(child: builder(result.report, lang)),
            ],
          ),
        );
  }
}
