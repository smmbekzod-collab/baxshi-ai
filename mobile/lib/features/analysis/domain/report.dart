// Pure Dart domain: no Flutter, Dio, Hive, or plugin imports.
enum School { xorazm, qashqadaryo, surxondaryo, qoraqalpogiston }

enum MetricKind { pitch, rhythm, breath, resonance, style }

class Metric {
  Metric({
    required this.kind,
    required this.score,
    required this.confidence,
    required this.reason,
  }) {
    if (score != null && (!score!.isFinite || score! < 0 || score! > 100)) {
      throw const FormatException('Invalid score');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Invalid confidence');
    }
    if (score == null && reason.isEmpty) {
      throw const FormatException('Unavailable metric needs a reason');
    }
  }
  final MetricKind kind;
  final double? score;
  final double confidence;
  final String reason;
}

class Sample {
  const Sample(this.seconds, this.user, this.reference);
  final double seconds;
  // Normalized, aligned metric score; not raw Hz and not a spectrogram.
  final double user;
  final double reference;
}

class FeedbackItem {
  const FeedbackItem({
    required this.start,
    required this.end,
    required this.message,
    required this.exercise,
  });
  final double start, end;
  final String message, exercise;
}

class Report {
  const Report({
    required this.id,
    required this.school,
    required this.metrics,
    required this.samples,
    required this.feedback,
    required this.modelVersion,
    required this.referenceId,
    required this.createdAt,
    required this.demo,
    required this.coachText,
    required this.audioAvailable,
  });
  final String id, modelVersion, referenceId, coachText;
  final School school;
  final List<Metric> metrics;
  final List<Sample> samples;
  final List<FeedbackItem> feedback;
  final DateTime createdAt;
  final bool demo, audioAvailable;
}

class ReportResult {
  const ReportResult(this.report, {this.fromCache = false});
  final Report report;
  final bool fromCache;
}

abstract interface class AnalysisRepository {
  Future<ReportResult> latest();
}

class LoadLatestReport {
  const LoadLatestReport(this.repository);
  final AnalysisRepository repository;
  Future<ReportResult> call() => repository.latest();
}
