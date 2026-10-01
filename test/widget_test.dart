import 'package:flutter_test/flutter_test.dart';

import 'package:voice_journal/main.dart';

void main() {
  testWidgets('app launches with the Voice Journal title', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceJournalApp());

    expect(find.text('Voice Journal'), findsOneWidget);
  });
}
