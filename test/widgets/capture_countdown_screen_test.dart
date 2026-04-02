import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a_snap/screens/capture_countdown_screen.dart';
import 'package:a_snap/state/app_state.dart';

void main() {
  testWidgets('renders region countdown copy and cancels on Escape', (
    tester,
  ) async {
    var cancelCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CaptureCountdownScreen(
          kind: CaptureKind.region,
          secondsRemaining: 3,
          onCancel: () => cancelCount++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('capture-countdown')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Region capture'), findsOneWidget);
    expect(find.text('Press Esc to cancel'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancelCount, 1);
  });
}
