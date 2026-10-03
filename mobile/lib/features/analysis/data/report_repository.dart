import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/report.dart';

Report parseReport(Map<String, dynamic> j) {
  if (j['schema_version'] != 1) {
    throw const FormatException('Unsupported report schema');
  }
  final metrics = (j['metrics'] as List).map((v) {
    final m = v as Map<String, dynamic>;
    return Metric(
      kind: MetricKind.values.byName(m['kind'] as String),
      score: (m['score'] as num?)?.toDouble(),
      confidence: (m['confidence'] as num).toDouble(),
      reason: m['reason'] as String? ?? '',
    );
  }).toList();
  if (metrics.map((m) => m.kind).toSet().length != MetricKind.values.length ||
      metrics.length != MetricKind.values.length) {
    throw const FormatException('Five distinct metrics required');
  }
  final samples = (j['samples'] as List)
      .map(
        (v) => Sample(
          (v['seconds'] as num).toDouble(),
          (v['user'] as num).toDouble(),
          (v['reference'] as num).toDouble(),
        ),
      )
      .toList();
  double previous = -1;
  for (final s in samples) {
    if (!s.seconds.isFinite ||
        s.seconds <= previous ||
        s.seconds < 0 ||
        !s.user.isFinite ||
        !s.reference.isFinite ||
        s.user < 0 ||
        s.user > 100 ||
        s.reference < 0 ||
        s.reference > 100) {
      throw const FormatException('Invalid time series');
    }
    previous = s.seconds;
  }
  final feedback = (j['feedback'] as List).map((v) {
    final start = (v['start'] as num).toDouble();
    final end = (v['end'] as num).toDouble();
    if (!start.isFinite || !end.isFinite || start < 0 || end < start) {
      throw const FormatException('Invalid feedback timestamps');
    }
    return FeedbackItem(
      start: start,
      end: end,
      message: v['message'] as String,
      exercise: v['exercise'] as String,
    );
  }).toList();
  return Report(
    id: j['id'] as String,
    school: School.values.byName(j['school'] as String),
    metrics: List.unmodifiable(metrics),
    samples: List.unmodifiable(samples),
    feedback: List.unmodifiable(feedback),
    modelVersion: j['model_version'] as String,
    referenceId: j['reference_id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    demo: j['demo'] as bool,
    coachText: j['coach_text'] as String,
    audioAvailable: j['audio_available'] as bool,
  );
}

class DemoReportRepository implements AnalysisRepository {
  @override
  Future<ReportResult> latest() async => ReportResult(
    parseReport(
      jsonDecode(await rootBundle.loadString('assets/demo_report.json'))
          as Map<String, dynamic>,
    ),
  );
}

class RemoteReportRepository implements AnalysisRepository {
  const RemoteReportRepository(this.api, this.local, {this.reportId});
  final String? reportId;
  final ApiClient api;
  final LocalStore local;
  @override
  Future<ReportResult> latest() async {
    final session = await api.tokens.read();
    if (session == null) throw StateError('auth');
    final key = '${session.subject}:report:${reportId ?? 'latest'}';
    try {
      final response = await api.dio.get<Map<String, dynamic>>(
        '/v1/reports/${reportId ?? 'latest'}',
      );
      final json = response.data!;
      final parsed = parseReport(json);
      if (parsed.demo) {
        throw const FormatException('Demo report on live endpoint');
      }
      await local.write(key, json);
      return ReportResult(parsed);
    } on DioException catch (e) {
      // 401/403/404 or schema failures must not masquerade as offline success.
      if (e.response != null || CancelToken.isCancel(e)) rethrow;
      final cached = local.read(key);
      if (cached == null) rethrow;
      return ReportResult(parseReport(cached), fromCache: true);
    }
  }
}
