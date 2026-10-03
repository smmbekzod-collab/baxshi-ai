class Recording {
  const Recording({
    required this.id,
    required this.path,
    required this.mime,
    required this.durationSeconds,
  });
  final String id, path, mime;
  final int durationSeconds;
}

abstract interface class Recorder {
  Stream<double> get amplitudes;
  Future<void> start({required bool lossless});
  Future<void> pause();
  Future<void> resume();
  Future<Recording> stop();
  Future<void> dispose();
}
