import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:hostel_cc_app/main.dart";

void main() {
  testWidgets("HostelCC app opens login when session is empty", (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const HostelCCApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text("HostelCC"), findsOneWidget);
    expect(find.text("Sign In"), findsOneWidget);
  });
}
