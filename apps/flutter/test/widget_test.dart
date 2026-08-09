import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ytapis_desktop/main.dart';

void main() {
  testWidgets('YtapisApp renders search page', (WidgetTester tester) async {
    await tester.pumpWidget(const YtapisApp());

    expect(find.text('ytapis'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });
}
