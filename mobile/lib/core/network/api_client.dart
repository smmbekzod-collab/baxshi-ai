import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.access, this.refresh, this.subject);
  final String access, refresh, subject;
}

abstract interface class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore(this.storage);
  final FlutterSecureStorage storage;
  // One value prevents mixing old/new token pairs during rotation.
  @override
  Future<Tokens?> read() async {
    final raw = await storage.read(key: 'session_v1');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return Tokens(
      j['access'] as String,
      j['refresh'] as String,
      j['subject'] as String,
    );
  }

  @override
  Future<void> write(Tokens t) => storage.write(
    key: 'session_v1',
    value: jsonEncode({
      'access': t.access,
      'refresh': t.refresh,
      'subject': t.subject,
    }),
  );
  @override
  Future<void> clear() => storage.delete(key: 'session_v1');
}

// Only replay requests whose bodies are reusable. A consumed Stream/FormData
// must be rebuilt by its owner; silently replaying it corrupts large uploads.
bool replayable(RequestOptions r) => r.data is! Stream && r.data is! FormData;
bool retryable(RequestOptions r) =>
    replayable(r) &&
    (const ['GET', 'HEAD', 'PUT', 'DELETE'].contains(r.method) ||
        r.headers.containsKey('Idempotency-Key'));

class ApiClient {
  ApiClient(String baseUrl, this.tokens) {
    final uri = Uri.parse(baseUrl);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ArgumentError('API_BASE_URL must be an HTTPS origin');
    }
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 45),
      headers: {'X-App-Version': '0.2.0'},
      followRedirects: false, // Do not forward bearer tokens via redirects.
    );
    dio = Dio(options);
    _refreshDio = Dio(options.copyWith());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) async {
          try {
            if (r.uri.origin != uri.origin) {
              h.reject(
                DioException(
                  requestOptions: r,
                  error: 'Cross-origin request blocked',
                ),
              );
              return;
            }
            final t = await tokens.read();
            if (t != null) r.headers['Authorization'] = 'Bearer ${t.access}';
            h.next(r);
          } catch (e) {
            h.reject(DioException(requestOptions: r, error: e));
          }
        },
        onError: (e, h) async {
          final r = e.requestOptions;
          if (e.response?.statusCode == 401 &&
              r.extra['refreshed'] != true &&
              replayable(r)) {
            try {
              final current = await tokens.read();
              if (current == null) {
                h.next(e);
                return;
              }
              // A concurrent request may already have refreshed this token.
              if (r.headers['Authorization'] == 'Bearer ${current.access}') {
                final active = _refreshing ??= _refresh(current);
                try {
                  await active;
                } finally {
                  if (identical(_refreshing, active)) _refreshing = null;
                }
              }
              r.extra['refreshed'] = true;
              final updated = await tokens.read();
              if (updated == null) {
                h.next(e);
                return;
              }
              r.headers['Authorization'] = 'Bearer ${updated.access}';
              h.resolve(await dio.fetch<dynamic>(r));
            } on DioException catch (failure) {
              h.next(failure);
            } catch (_) {
              h.next(e);
            }
            return;
          }
          final attempt = (r.extra['retry'] as int?) ?? 0;
          final status = e.response?.statusCode;
          final transient =
              const [408, 429, 502, 503, 504].contains(status) ||
              const [
                DioExceptionType.connectionError,
                DioExceptionType.connectionTimeout,
                DioExceptionType.receiveTimeout,
                DioExceptionType.sendTimeout,
              ].contains(e.type);
          if (transient &&
              retryable(r) &&
              attempt < 3 &&
              !CancelToken.isCancel(e)) {
            r.extra['retry'] = attempt + 1;
            final retryAfter = int.tryParse(
              e.response?.headers.value('retry-after') ?? '',
            );
            final millis = retryAfter == null
                ? 400 * (1 << attempt) + Random().nextInt(200)
                : retryAfter.clamp(0, 60).toInt() * 1000;
            await Future<void>.delayed(Duration(milliseconds: millis));
            if (r.cancelToken?.isCancelled ?? false) {
              h.next(e);
              return;
            }
            try {
              h.resolve(await dio.fetch<dynamic>(r));
            } on DioException catch (failure) {
              h.next(failure);
            } catch (_) {
              h.next(e);
            }
            return;
          }
          h.next(e);
        },
      ),
    );
  }
  final TokenStore tokens;
  late final Dio dio, _refreshDio;
  Future<void>? _refreshing;
  Future<void> _refresh(Tokens old) async {
    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refresh_token': old.refresh},
      );
      final data = response.data!;
      // Do not resurrect a session after logout or an account switch.
      final current = await tokens.read();
      if (current?.refresh != old.refresh) return;
      await tokens.write(
        Tokens(
          data['access_token'] as String,
          data['refresh_token'] as String,
          old.subject,
        ),
      );
    } on DioException catch (e) {
      if (const [400, 401, 403].contains(e.response?.statusCode)) {
        final current = await tokens.read();
        if (current?.refresh == old.refresh) await tokens.clear();
      }
      rethrow; // A network outage must not erase a valid refresh token.
    }
  }

  void close() {
    dio.close(force: true);
    _refreshDio.close(force: true);
  }
}

String safeNetworkMessage(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401) return 'auth';
    if (error.response?.statusCode == 413) return 'tooLarge';
    if (CancelToken.isCancel(error)) return 'cancelled';
  }
  return 'error'; // Never display URLs, tokens, or raw server exceptions.
}
