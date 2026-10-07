import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

// Only caller-provided trusted IDs determine local filenames. Never URL basenames.
// Cache uses atomic rename and content checksum, with a bounded byte budget.
class AudioCache {
  AudioCache(this.dio, this.subject, {this.budgetBytes = 256 * 1024 * 1024});
  final Dio dio;
  final String subject;
  final int budgetBytes;
  final Map<String, Future<String>> _pending = {};
  Future<String> get(
    String hash,
    String relativeEndpoint, {
    String extension = "m4a",
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw ArgumentError('SHA-256 required');
    }
    if (!['wav', 'm4a'].contains(extension)) throw ArgumentError('extension');
    final existing = _pending[hash];
    if (existing != null) return existing;
    final task = _fetch(hash, relativeEndpoint, extension);
    _pending[hash] = task;
    try {
      return await task;
    } finally {
      _pending.remove(hash);
    }
  }

  Future<String> _fetch(String hash, String endpoint, String extension) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/$subject/audio_cache',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$hash.$extension');
    if (await file.exists()) {
      if ((await sha256.bind(file.openRead()).first).toString() == hash) {
        await file.setLastModified(DateTime.now());
        return file.path;
      }
      await file.delete();
    }
    final part = File('${file.path}.part');
    final cancel = CancelToken();
    try {
      await dio.download(
        endpoint,
        part.path,
        cancelToken: cancel,
        onReceiveProgress: (received, _) {
          if (received > budgetBytes) cancel.cancel('Cache limit');
        },
      );
      if ((await sha256.bind(part.openRead()).first).toString() != hash) {
        throw const FormatException('Audio checksum mismatch');
      }
      await part.rename(file.path);
      // Do not evict downloads currently completing in another call.
      final candidates = <File>[];
      await for (final item in dir.list()) {
        if (item is File &&
            (item.path.endsWith('.m4a') || item.path.endsWith('.wav'))) {
          candidates.add(item);
        }
      }
      final dated = <(File, DateTime, int)>[];
      for (final item in candidates) {
        final stat = await item.stat();
        dated.add((item, stat.modified, stat.size));
      }
      dated.sort((a, b) => a.$2.compareTo(b.$2));
      var bytes = dated.fold<int>(0, (sum, f) => sum + f.$3);
      for (final item in dated) {
        if (bytes <= budgetBytes) break;
        if (item.$1.path == file.path) continue;
        if (await item.$1.exists()) await item.$1.delete();
        bytes -= item.$3;
      }
      return file.path;
    } finally {
      if (await part.exists()) await part.delete();
    }
  }
}
