import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxshi_ai/core/providers.dart';
import 'package:baxshi_ai/features/analysis/data/report_repository.dart';
import 'package:baxshi_ai/features/analysis/domain/report.dart';
import 'package:baxshi_ai/features/analysis/presentation/analytics_screen.dart';
import 'package:baxshi_ai/features/coach/presentation/coach_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = parseReport(
    jsonDecode(File('assets/demo_report.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => true,
        );
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets('Dashboard lays out at width $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportProvider.overrideWith((ref) async => ReportResult(report)),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const Scaffold(body: AnalyticsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Coach displays report feedback', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportProvider.overrideWith((ref) async => ReportResult(report)),
        ],
        child: const MaterialApp(home: Scaffold(body: CoachScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(report.coachText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
