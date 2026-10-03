import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxshi_ai/features/analysis/data/report_repository.dart';
import 'package:baxshi_ai/features/analysis/domain/report.dart';

void main() {
  Map<String, dynamic> fixture() =>
      jsonDecode(File('assets/demo_report.json').readAsStringSync())
          as Map<String, dynamic>;
  test('unavailable scores stay null, never fabricated as zero', () {
    final r = parseReport(fixture());
    expect(
      r.metrics.singleWhere((m) => m.kind == MetricKind.breath).score,
      isNull,
    );
    expect(r.demo, isTrue);
  });
  test('invalid confidence fails at boundary', () {
    final j = fixture();
    j['metrics'][0]['confidence'] = 1.2;
    expect(() => parseReport(j), throwsFormatException);
  });
  test('duplicate and missing metric rejected', () {
    final j = fixture();
    j['metrics'][1]['kind'] = 'pitch';
    expect(() => parseReport(j), throwsFormatException);
  });
  test('unsorted or invalid time series rejected', () {
    final j = fixture();
    j['samples'][1]['seconds'] = -1;
    expect(() => parseReport(j), throwsFormatException);
  });
  test('unsupported schema fails instead of corrupting cached report', () {
    final j = fixture();
    j['schema_version'] = 2;
    expect(() => parseReport(j), throwsFormatException);
  });
}
