import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../storage/local_store.dart';

// Upload transport, not live inference. Chunks are byte ranges of one file;
// the server must concatenate before decoding a WAV/M4A container.
class ChunkUploader {
  ChunkUploader(this.dio, this.local);
  final Dio dio;
  final LocalStore local;
  final Set<String> _active = {};
  static const chunkBytes = 1024 * 1024;

  Future<String> upload({
    required String subject,
    required String recordingId,
    required String path,
    required String mime,
    required CancelToken cancel,
    required void Function(double) progress,
  }) async {
    final key = '$subject:upload:$recordingId';
    if (!_active.add(key)) throw StateError('Upload already active');
    try {
      final file = File(path);
      final length = await file.length();
      if (length == 0) throw StateError('Empty recording');
      // Stream hash: do not read a multi-hour recording into memory.
      final digest = (await sha256.bind(file.openRead()).first).toString();
      var session = local.read(key);
      if (session != null &&
          (session['sha256'] != digest || session['size'] != length)) {
        throw StateError('Recording changed; create a new recording ID');
      }
      if (session == null) {
        final response = await dio.post<Map<String, dynamic>>(
          '/v1/uploads',
          data: {
            'size': length,
            'sha256': digest,
            'mime': mime,
            'recording_id': recordingId,
          },
          cancelToken: cancel,
          options: Options(headers: {'Idempotency-Key': recordingId}),
        );
        session = {
          'id': response.data!['id'],
          'sha256': digest,
          'size': length,
        };
        await local.write(key, session);
      }
      final id = Uri.encodeComponent(session['id'] as String);
      final status = await dio.get<Map<String, dynamic>>(
        '/v1/uploads/$id',
        cancelToken: cancel,
      );
      var offset = status.data!['offset'] as int;
      if (offset < 0 || offset > length) {
        throw const FormatException('Invalid upload offset');
      }
      final handle = await file.open();
      try {
        await handle.setPosition(offset);
        while (offset < length) {
          if (cancel.isCancelled) {
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.cancel,
            );
          }
          final bytes = await handle.read(min(chunkBytes, length - offset));
          if (bytes.isEmpty) throw StateError('Recording truncated');
          final end = offset + bytes.length;
          await dio.put<dynamic>(
            '/v1/uploads/$id/chunks/$offset',
            data: bytes,
            cancelToken: cancel,
            options: Options(
              contentType: 'application/octet-stream',
              headers: {
                'Content-Range': 'bytes $offset-${end - 1}/$length',
                'X-Chunk-SHA256': sha256.convert(bytes).toString(),
                'Idempotency-Key': '$recordingId:$offset',
              },
            ),
          );
          offset = end;
          progress(offset / length);
        }
      } finally {
        await handle.close();
      }
      // Completion response must remain replayable on the server if the response is lost.
      final completed = await dio.post<Map<String, dynamic>>(
        '/v1/uploads/$id/complete',
        data: {'sha256': digest},
        cancelToken: cancel,
        options: Options(headers: {'Idempotency-Key': '$recordingId:complete'}),
      );
      await local.remove(key);
      return completed.data!['asset_id'] as String;
    } finally {
      _active.remove(key);
    }
  }
}
