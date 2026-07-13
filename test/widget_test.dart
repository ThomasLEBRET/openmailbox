import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openmailbox/main.dart';

void main() {
  testWidgets('App shows a loading indicator on first frame', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: OpenMailboxApp()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
