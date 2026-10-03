import 'package:flutter_test/flutter_test.dart';
import 'package:baxshi_ai/l10n/strings.dart';

void main() {
  test('all supported app languages have identical keys', () {
    final keys = translations['en']!.keys.toSet();
    for (final lang in ['uz', 'kaa']) {
      expect(translations[lang]!.keys.toSet(), keys);
      expect(translations[lang]!.values.every((v) => v.isNotEmpty), isTrue);
    }
  });
}
