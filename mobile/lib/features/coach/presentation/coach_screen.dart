import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../shared/api_ui.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../l10n/strings.dart';
import '../../../shared/report_view.dart';
import '../../analysis/domain/report.dart';

class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ReportView(
    builder: (report, lang) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(lang, 'coach'),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      report.coachText,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                _OptionalAiCoach(report: report),
                SpeechButton(text: report.coachText, lang: lang),
                const SizedBox(height: 24),
                Text(
                  tr(lang, 'minutePlan'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ...report.feedback.map(
                  (item) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Chip(
                            label: Text(
                              '${item.start.toStringAsFixed(1)}–${item.end.toStringAsFixed(1)} s',
                            ),
                          ),
                          Text(
                            item.message,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          Text('${tr(lang, 'practice')}: ${item.exercise}'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


class _OptionalAiCoach extends ConsumerStatefulWidget {
  const _OptionalAiCoach({required this.report});

  final Report report;

  @override
  ConsumerState<_OptionalAiCoach> createState() => _OptionalAiCoachState();
}

class _OptionalAiCoachState extends ConsumerState<_OptionalAiCoach> {
  bool loading = false;
  String? text;
  String? notice;

  Future<void> generate() async {
    if (loading) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI tavsiyasi'),
        content: const Text(
          'Faqat ovoz ko‘rsatkichlari tanlangan tashqi AI xizmatiga yuboriladi. Ovoz yozuvi, ism va profil yuborilmaydi. Xizmat provayderining maxfiylik shartlari amal qiladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bir marta yuborish'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => loading = true);
    try {
      final response = await ref.read(apiProvider).dio.post<Map<String, dynamic>>(
        '/v1/reports/${widget.report.id}/coach-ai',
      );
      if (!mounted) return;
      setState(() {
        text = response.data?['text'] as String? ?? widget.report.coachText;
        notice = response.data?['notice'] as String? ?? '';
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ovoz fayli yuborilmaydi; faqat metrikalar AI xizmatiga uzatilishi mumkin.'),
          FilledButton.tonalIcon(
            onPressed: loading ? null : generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(loading ? 'Tayyorlanmoqda…' : 'AI bilan qo‘shimcha tavsiya'),
          ),
          if (text != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(text!)),
          if (notice != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(notice!, style: Theme.of(context).textTheme.bodySmall)),
          const Text('Bu tavsiya avtomatik. Ustoz fikri bilan solishtiring.'),
        ],
      ),
    ),
  );
}

class SpeechButton extends StatefulWidget {
  const SpeechButton({super.key, required this.text, required this.lang});
  final String text, lang;
  @override
  State<SpeechButton> createState() => _Speech();
}

class _Speech extends State<SpeechButton> {
  final tts = FlutterTts();
  bool speaking = false;
  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  Future<void> speak() async {
    try {
      if (speaking) {
        await tts.stop();
        if (mounted) setState(() => speaking = false);
        return;
      }
      final lang = widget.lang == 'en'
          ? 'en-US'
          : widget.lang == 'kaa'
          ? 'kaa'
          : 'uz-UZ';
      if (!await tts.isLanguageAvailable(lang)) throw StateError('voice');
      await tts.setLanguage(lang);
      await tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => speaking = true);
      await tts.speak(widget.text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu til uchun qurilmada TTS ovozi o‘rnatilmagan. Matnli tavsiya mavjud.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: speak,
    icon: Icon(speaking ? Icons.stop : Icons.volume_up),
    label: Text(speaking ? 'To‘xtatish' : 'Qurilma ovozida tinglash'),
  );
}
