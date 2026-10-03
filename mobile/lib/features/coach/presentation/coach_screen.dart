import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../l10n/strings.dart';
import '../../../shared/report_view.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});
  @override
  Widget build(BuildContext context) => ReportView(
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
