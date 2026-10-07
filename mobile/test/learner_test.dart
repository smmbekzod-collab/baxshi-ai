import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxshi_ai/features/community/community.dart';
import 'package:baxshi_ai/features/learning/learning_screen.dart';
import 'package:baxshi_ai/shared/api_ui.dart';
import 'package:baxshi_ai/shared/quality_panel.dart';

void main() {
  testWidgets('Measured pitch is visible without traditional scores', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QualityPanel(
            quality: {
              'duration_seconds': 12,
              'median_pitch_hz': 220,
              'rms_dbfs': -18,
              'voiced_coverage': .9,
              'clipping_ratio': 0,
            },
          ),
        ),
      ),
    );
    expect(find.text('O‘rta chastota: 220 Hz'), findsOneWidget);
    expect(find.text('Ovozli kadrlar: 90%'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Quiz cannot submit before every question is answered', (
    t,
  ) async {
    await t.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LessonPage(
            lesson: {
              'id': 'test',
              'title': 'Sinov',
              'minutes': 8,
              'body': 'Tinglang va mashq qiling.',
              'questions': [
                {
                  'prompt': 'Birinchi?',
                  'options': ['A', 'B'],
                },
                {
                  'prompt': 'Ikkinchi?',
                  'options': ['C', 'D'],
                },
              ],
            },
          ),
        ),
      ),
    );
    final submit = find.widgetWithText(FilledButton, 'Javoblarni tekshirish');
    expect(t.widget<FilledButton>(submit).onPressed, isNull);
    await t.tap(find.text('A'));
    await t.pump();
    expect(t.widget<FilledButton>(submit).onPressed, isNull);
    await t.tap(find.text('C'));
    await t.pump();
    expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('Profile exposes own name and avatar controls', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          avatarProvider.overrideWith((ref) async => null),
          dataProvider('/v1/profile').overrideWith(
            (ref) async => {'name': 'Talaba', 'bio': 'Doston o‘rganaman'},
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ProfileCard())),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Talaba'), findsOneWidget);
    expect(find.text('Profilni tahrirlash'), findsOneWidget);
    expect(find.text('JPG, PNG yoki WEBP • 3 MB gacha'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
