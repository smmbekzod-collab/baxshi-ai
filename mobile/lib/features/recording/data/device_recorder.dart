import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../domain/recorder.dart';

class DeviceRecorder implements Recorder {
  DeviceRecorder(this.subject);
  final String subject;
  final AudioRecorder _device = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  String? _id;
  bool _lossless = true;
  @override
  Stream<double> get amplitudes => _device
      .onAmplitudeChanged(const Duration(milliseconds: 60))
      .map((v) => v.current);
  @override
  Future<void> start({required bool lossless}) async {
    if (!await _device.hasPermission()) throw StateError('permission');
    final encoder = lossless ? AudioEncoder.wav : AudioEncoder.aacLc;
    if (!await _device.isEncoderSupported(encoder)) {
      throw StateError('unsupported');
    }
    final dir = await getApplicationDocumentsDirectory();
    await Directory('${dir.path}/$subject').create(recursive: true);
    _id = const Uuid().v4();
    _lossless = lossless;
    await _device.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: 48000,
        numChannels: 1,
        bitRate: 128000,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: '${dir.path}/$subject/$_id.${lossless ? 'wav' : 'm4a'}',
    );
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<void> pause() async {
    await _device.pause();
    _clock.stop();
  }

  @override
  Future<void> resume() async {
    await _device.resume();
    _clock.start();
  }

  @override
  Future<Recording> stop() async {
    final path = await _device.stop();
    _clock.stop();
    if (path == null || _id == null) throw StateError('No recording');
    return Recording(
      id: _id!,
      path: path,
      mime: _lossless ? 'audio/wav' : 'audio/mp4',
      durationSeconds: _clock.elapsed.inSeconds,
    );
  }

  @override
  Future<void> dispose() => _device.dispose();
}
