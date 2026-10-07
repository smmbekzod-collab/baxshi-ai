import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/analysis/domain/report.dart';
import '../features/analysis/data/report_repository.dart';
import '../features/recording/domain/recorder.dart';
import '../features/recording/data/device_recorder.dart';
import 'network/api_client.dart';
import 'storage/local_store.dart';
import 'audio/chunk_uploader.dart';
import 'audio/audio_cache.dart';

const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('Bootstrap required'),
);
final tokensProvider = Provider<TokenStore>(
  (ref) => const SecureTokenStore(FlutterSecureStorage()),
);
final apiProvider = Provider<ApiClient>((ref) {
  const url = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://baxshi-ai-production.up.railway.app',
  );
  final client = ApiClient(url, ref.watch(tokensProvider));
  ref.onDispose(client.close);
  return client;
});
final repositoryProvider = Provider<AnalysisRepository>((ref) {
  ref.watch(accountProvider);
  return demoMode
      ? DemoReportRepository()
      : RemoteReportRepository(
          ref.watch(apiProvider),
          ref.watch(localStoreProvider),
          reportId: ref.watch(selectedReportProvider),
        );
});
final reportProvider = FutureProvider<ReportResult>(
  (ref) => LoadLatestReport(ref.watch(repositoryProvider))(),
);
final recorderProvider = Provider<Recorder>((ref) {
  final recorder = DeviceRecorder(ref.watch(accountProvider));
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});
final uploaderProvider = Provider<ChunkUploader>(
  (ref) =>
      ChunkUploader(ref.watch(apiProvider).dio, ref.watch(localStoreProvider)),
);
final audioCacheProvider = Provider<AudioCache>(
  (ref) => AudioCache(ref.watch(apiProvider).dio, ref.watch(accountProvider)),
);

final accountProvider = NotifierProvider<Account, String>(Account.new);

class Account extends Notifier<String> {
  @override
  String build() => "demo";
  void set(String id) => state = id;
}

final selectedReportProvider = NotifierProvider<SelectedReport, String?>(
  SelectedReport.new,
);

class SelectedReport extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}
