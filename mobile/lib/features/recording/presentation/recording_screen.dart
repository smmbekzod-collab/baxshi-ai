import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../features/analysis/domain/report.dart';
import '../../../l10n/strings.dart';
import '../../../shared/local_player.dart';
import '../../../shared/api_ui.dart';
import '../../../shared/job_status.dart';
import '../../../shared/reference_player.dart';
import 'recording_controller.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});
  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen>
    with WidgetsBindingObserver {
  bool lossless = true, consent = false, uploading = false;
  double progress = 0;
  String? message, jobId, referenceId;
  School school = School.xorazm;
  CancelToken? cancel;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancel?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground-only policy. Background recording requires a native service.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(ref.read(recordingProvider.notifier).pause());
    }
  }

  Future<void> upload() async {
    final recording = ref.read(recordingProvider).recording;
    if (recording == null || uploading || !consent || demoMode) return;
    setState(() {
      uploading = true;
      message = null;
      progress = 0;
    });
    final token = CancelToken();
    cancel = token;
    final selectedSchool = school;
    final selectedReference = referenceId;
    try {
      final session = await ref.read(tokensProvider).read();
      if (session == null) throw StateError('auth');
      final local = ref.read(localStoreProvider);
      final assetKey = '${session.subject}:asset:${recording.id}';
      var assetId = local.read(assetKey)?['asset_id'] as String?;
      assetId ??= await ref
          .read(uploaderProvider)
          .upload(
            subject: session.subject,
            recordingId: recording.id,
            path: recording.path,
            mime: recording.mime,
            cancel: token,
            progress: (v) {
              if (mounted) setState(() => progress = v);
            },
          );
      await local.write(assetKey, {'asset_id': assetId});
      final locale = ref.read(languageProvider);
      final response = await ref
          .read(apiProvider)
          .dio
          .post<Map<String, dynamic>>(
            '/v1/analyses',
            data: {
              'asset_id': assetId,
              'school': selectedSchool.name,
              'locale': locale,
              'reference_id': selectedReference,
              'consent_version': 'analysis-v1',
            },
            cancelToken: token,
            options: Options(
              headers: {
                'Idempotency-Key':
                    '${recording.id}:${selectedSchool.name}:$locale:${selectedReference ?? 'none'}',
              },
            ),
          );
      final id = response.data!['job_id'] as String;
      await local.write('${session.subject}:job:$id', {
        'job_id': id,
        'recording_id': recording.id,
      });
      if (mounted) {
        setState(() {
          jobId = id;
          message = 'queued';
        });
      }
      ref.invalidate(reportProvider);
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is StateError && e.message == 'auth'
              ? 'auth'
              : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingProvider);
    final controller = ref.read(recordingProvider.notifier);
    final lang = ref.watch(languageProvider);
    final active =
        state.phase == RecordingPhase.recording ||
        state.phase == RecordingPhase.paused;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(lang, 'record'),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(tr(lang, 'privacy')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(lang, lossless ? 'lossless' : 'compressed')),
                  value: lossless,
                  onChanged: active || state.busy || uploading
                      ? null
                      : (v) => setState(() => lossless = v),
                ),
                const SizedBox(height: 20),
                Text(
                  '${state.seconds ~/ 60}:${(state.seconds % 60).toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 20),
                Semantics(
                  label:
                      '${tr(lang, 'quality')} ${state.db.toStringAsFixed(0)} dBFS',
                  child: SizedBox(
                    height: 150,
                    child: CustomPaint(
                      painter: _WavePainter(
                        state.levels,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                Text(tr(lang, 'sample'), textAlign: TextAlign.center),
                if (state.phase == RecordingPhase.recording &&
                    (state.db > -1 || state.db < -55))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr(lang, state.db > -1 ? 'clipping' : 'quiet')),
                  ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!active)
                      FilledButton.icon(
                        onPressed: state.busy || uploading
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  jobId = null;
                                  message = null;
                                  consent = false;
                                });
                                controller.start(lossless);
                              },
                        icon: const Icon(Icons.mic),
                        label: Text(tr(lang, 'start')),
                      ),
                    if (active) ...[
                      OutlinedButton(
                        onPressed: state.busy
                            ? null
                            : () => state.phase == RecordingPhase.paused
                                  ? controller.resume()
                                  : controller.pause(),
                        child: Text(
                          tr(
                            lang,
                            state.phase == RecordingPhase.paused
                                ? 'resume'
                                : 'pause',
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: state.busy ? null : controller.stop,
                        icon: const Icon(Icons.stop),
                        label: Text(tr(lang, 'stop')),
                      ),
                    ],
                  ],
                ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr(lang, state.error!)),
                  ),
                if (state.phase == RecordingPhase.saved &&
                    state.recording != null) ...[
                  const SizedBox(height: 24),
                  Text(tr(lang, 'recordingSaved')),
                  LocalPlayer(
                    key: ValueKey(state.recording!.id),
                    path: state.recording!.path,
                    playLabel: tr(lang, 'play'),
                    errorLabel: tr(lang, 'error'),
                  ),
                  DropdownButton<School>(
                    value: school,
                    isExpanded: true,
                    items: School.values
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.name)),
                        )
                        .toList(),
                    onChanged: uploading
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() {
                                school = v;
                                referenceId = null;
                              });
                            }
                          },
                  ),
                  if (!demoMode)
                    DataView(
                      path: '/v1/references?school=${school.name}',
                      builder: (data) => DropdownButton<String>(
                        value: referenceId ?? '',
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Etalonsiz — sifat tekshiruvi'),
                          ),
                          for (final r in data as List)
                            DropdownMenuItem(
                              value: r['id'] as String,
                              child: Text('${r['master']} • ${r['title']}'),
                            ),
                        ],
                        onChanged: uploading
                            ? null
                            : (v) => setState(
                                () => referenceId = v == '' ? null : v,
                              ),
                      ),
                    ),
                  if (referenceId != null)
                    DataView(
                      path: '/v1/references?school=${school.name}',
                      builder: (data) {
                        final refs = (data as List).where(
                          (r) => r['id'] == referenceId,
                        );
                        return refs.isEmpty
                            ? const SizedBox.shrink()
                            : ReferencePlayer(
                                assetId: refs.first['asset_id'] as String,
                              );
                      },
                    ),
                  CheckboxListTile(
                    value: consent,
                    onChanged: uploading
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: Text(tr(lang, 'consent')),
                  ),
                  FilledButton(
                    onPressed: consent && !uploading && !demoMode
                        ? upload
                        : null,
                    child: Text(tr(lang, 'upload')),
                  ),
                  if (demoMode) Text(tr(lang, 'analysisNeedsBackend')),
                  if (uploading) ...[
                    LinearProgressIndicator(value: progress),
                    TextButton(
                      onPressed: () => cancel?.cancel(),
                      child: const Icon(Icons.close),
                    ),
                  ],
                  if (message != null) Text(tr(lang, message!)),
                  if (jobId != null) JobStatus(id: jobId!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 100; i++) {
      final index = i - (100 - values.length);
      final v = index < 0 ? 0.01 : values[index];
      final height = max(2.0, sqrt(v) * size.height * 0.9);
      final x = (i + .5) * size.width / 100;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.values != values || old.color != color;
}
