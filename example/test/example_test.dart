import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_route/omni_route.dart';
import 'package:omni_route_example/main.dart';

void main() {
  testWidgets('full example flow', (t) async {
    await t.pumpWidget(const ExampleApp());
    await t.pumpAndSettle();
    expect(
      find.text('Log in'),
      findsOneWidget,
      reason: 'guard redirects to login',
    );

    await t.tap(find.text('Log in'));
    await t.pumpAndSettle();
    expect(OmniRoute.location.path, '/dashboard');

    await t.tap(find.text('Open student 101'));
    await t.pumpAndSettle();
    expect(find.text('Student #101'), findsOneWidget);
    await t.tap(find.text('Mark present'));
    await t.pump();
    expect(find.text('Present 1 days'), findsOneWidget);

    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(
      Theme.of(t.element(find.text('Dark mode'))).brightness,
      Brightness.dark,
    );

    await t.tap(find.text('Profile'));
    await t.pumpAndSettle();
    expect(OmniRoute.location.path, '/settings/profile');

    await t.tap(find.text('Students'));
    await t.pumpAndSettle();
    expect(
      find.text('Student #101'),
      findsOneWidget,
      reason: 'tab kept its stack',
    );

    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    OmniRoute.go('/settings');
    await t.pumpAndSettle();
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
  });
}
