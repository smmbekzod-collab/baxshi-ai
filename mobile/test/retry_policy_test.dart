import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxshi_ai/core/network/api_client.dart';

void main() {
  test('non-idempotent POST never auto retries', () {
    expect(
      retryable(
        RequestOptions(method: 'POST', path: '/payments', data: {'x': 1}),
      ),
      isFalse,
    );
  });
  test('upload bytes are reusable, streams are not', () {
    expect(retryable(RequestOptions(method: 'PUT', data: [1, 2, 3])), isTrue);
    expect(
      retryable(
        RequestOptions(method: 'PUT', data: const Stream<List<int>>.empty()),
      ),
      isFalse,
    );
  });
  test('idempotency key permits replayable POST', () {
    expect(
      retryable(
        RequestOptions(
          method: 'POST',
          data: {'x': 1},
          headers: {'Idempotency-Key': 'stable-id'},
        ),
      ),
      isTrue,
    );
  });
}
