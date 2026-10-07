import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/audio_session.dart';
import '../domain/recorder.dart';

enum RecordingPhase { idle, recording, paused, saved }

class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.idle,
    this.busy = false,
    this.levels = const [],
    this.db = -80,
    this.seconds = 0,
    this.recording,
    this.error,
  });
  final RecordingPhase phase;
  final bool busy;
  final List<double> levels;
  final double db;
  final int seconds;
  final Recording? recording;
  final String? error;
  RecordingState copy({
    RecordingPhase? phase,
    bool? busy,
    List<double>? levels,
    double? db,
    int? seconds,
    Recording? recording,
    String? error,
  }) => RecordingState(
    phase: phase ?? this.phase,
    busy: busy ?? this.busy,
    levels: levels ?? this.levels,
    db: db ?? this.db,
    seconds: seconds ?? this.seconds,
    recording: recording ?? this.recording,
    error: error,
  );
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState>(
  RecordingController.new,
);

class RecordingController extends Notifier<RecordingState> {
  StreamSubscription<double>? _amplitude;
  Timer? _timer;
  @override
  RecordingState build() {
    ref.onDispose(() {
      _amplitude?.cancel();
      _timer?.cancel();
    });
    return const RecordingState();
  }

  Future<void> start(bool lossless) async {
    if (state.busy ||
        state.phase == RecordingPhase.recording ||
        state.phase == RecordingPhase.paused) {
      return;
    }
    state = const RecordingState(busy: true);
    try {
      await AudioSession.stopAll();
      await ref.read(recorderProvider).start(lossless: lossless);
      state = const RecordingState(phase: RecordingPhase.recording);
      await _amplitude?.cancel();
      _amplitude = ref
          .read(recorderProvider)
          .amplitudes
          .listen(
            (db) {
              if (state.phase != RecordingPhase.recording || !db.isFinite) {
                return;
              }
              final level = pow(
                10,
                db / 20,
              ).toDouble().clamp(0.0, 1.0).toDouble();
              final levels = [...state.levels, level];
              state = state.copy(
                db: db,
                levels: List.unmodifiable(
                  levels.length > 100
                      ? levels.sublist(levels.length - 100)
                      : levels,
                ),
              );
            },
            onError: (Object _) {
              state = state.copy(error: 'error');
            },
          );
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.phase == RecordingPhase.recording) {
          state = state.copy(seconds: state.seconds + 1);
          if (state.seconds >= 1200) unawaited(stop());
        }
      });
    } catch (e) {
      state = RecordingState(
        error: e.toString().contains('permission') ? 'permission' : 'error',
      );
    }
  }

  Future<void> pause() async {
    if (state.busy || state.phase != RecordingPhase.recording) return;
    state = state.copy(busy: true);
    try {
      await ref.read(recorderProvider).pause();
      state = state.copy(phase: RecordingPhase.paused, busy: false);
    } catch (_) {
      state = state.copy(busy: false, error: 'error');
    }
  }

  Future<void> resume() async {
    if (state.busy || state.phase != RecordingPhase.paused) return;
    state = state.copy(busy: true);
    try {
      await ref.read(recorderProvider).resume();
      state = state.copy(phase: RecordingPhase.recording, busy: false);
    } catch (_) {
      state = state.copy(busy: false, error: 'error');
    }
  }

  Future<void> stop() async {
    if (state.busy ||
        ![
          RecordingPhase.recording,
          RecordingPhase.paused,
        ].contains(state.phase)) {
      return;
    }
    state = state.copy(busy: true);
    try {
      final recording = await ref.read(recorderProvider).stop();
      _timer?.cancel();
      await _amplitude?.cancel();
      // Publish a stopped state even if the later database write fails.
      state = state.copy(
        phase: RecordingPhase.saved,
        recording: recording,
        busy: true,
      );
      // Persist metadata so app restart does not lose the recording location.
      await ref
          .read(localStoreProvider)
          .write('${ref.read(accountProvider)}:recording:${recording.id}', {
            'id': recording.id,
            'path': recording.path,
            'mime': recording.mime,
            'duration_seconds': recording.durationSeconds,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
      state = state.copy(
        phase: RecordingPhase.saved,
        recording: recording,
        busy: false,
      );
    } catch (_) {
      state = state.copy(busy: false, error: 'error');
    }
  }
}
