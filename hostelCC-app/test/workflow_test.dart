import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_cc_app/forms.dart';
import 'package:hostel_cc_app/main.dart';
import 'package:hostel_cc_app/services/api.dart';

class FakeApi extends Api {
  final List<(String, String, Map<String, dynamic>?)> calls = [];
  @override
  Future<dynamic> call(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool retry = true}) async {
    calls.add((path, method, body));
    if (path == '/auth/request-code') {
      return {'message': 'Code sent'};
    }
    if (path == '/auth/verify-code') {
      return {'id': 'student', 'name': 'Test Student', 'role': 'STUDENT'};
    }
    if (path == '/cloakroom/scan') {
      return {
        'tokenNumber': 501,
        'studentName': 'Test Student',
        'item': 'CHAIR',
        'status': 'STORED',
        'receipt': 'HC-test'
      };
    }
    return {'message': 'Saved'};
  }
}

void main() {
  test('duty permission requires both the book and the assigned target', () {
    final user = {
      'role': 'WARDEN',
      'scopes': [
        {'book': 'MESS', 'targetId': 'mess-a', 'active': true}
      ]
    };
    expect(has(user, 'MESS', 'mess-a'), isTrue);
    expect(has(user, 'MESS', 'mess-b'), isFalse);
    expect(has(user, 'OUTINGS', 'mess-a'), isFalse);
    expect(has({'role': 'DIRECTOR'}, 'MESS', 'mess-a'), isFalse);
  });
  testWidgets(
      'email-code login includes remember choice and never asks for a password',
      (tester) async {
    final api = FakeApi();
    Map<String, dynamic>? loggedIn;
    await tester.pumpWidget(
        MaterialApp(home: LoginScreen(api: api, onLogin: (u) => loggedIn = u)));
    await tester.enterText(find.byType(TextFormField), 'student@example.test');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    expect(find.text('Verification code'), findsOneWidget);
    expect(find.textContaining('Password'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify & sign in'));
    await tester.pumpAndSettle();
    expect(loggedIn?['role'], 'STUDENT');
    expect(api.calls.last.$3?['remember'], true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('record form sends the completed action', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(
        home: RecordForm(
            title: 'Resolve task',
            path: '/maintenance/task/action',
            api: api,
            initial: const {'action': 'resolve'},
            fields: (_) =>
                [const Field('resolution', 'Work completed', type: 'long')])));
    await tester.enterText(find.byType(TextFormField), 'Corridor cleaned');
    await tester.tap(find.text('Confirm & save'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$1, '/maintenance/task/action');
    expect(api.calls.last.$3,
        {'action': 'resolve', 'resolution': 'Corridor cleaned'});
  });
  testWidgets('cloakroom scan submits the assigned room and displays token',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScanScreen(
                api: api,
                user: const {
                  'role': 'HOUSEKEEPING',
                  'scopes': [
                    {'active': true, 'book': 'CLOAKROOM', 'targetId': 'room'}
                  ]
                },
                data: const {
                  'storageRooms': [
                    {
                      'id': 'room',
                      'name': 'Chair room',
                      'itemType': 'CHAIR',
                      'active': true
                    }
                  ]
                },
                onProcessed: () async {}))));
    await tester.tap(find.text('Cloakroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chair room · Chair').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Item-pass code'), 'HCC1:test');
    await tester.ensureVisible(find.text('Check in & issue token'));
    await tester.tap(find.text('Check in & issue token'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3?['storageId'], 'room');
    expect(api.calls.last.$3?['qrToken'], 'HCC1:test');
    await tester.scrollUntilVisible(find.text('Token 501'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Token 501'), findsOneWidget);
  });
}
