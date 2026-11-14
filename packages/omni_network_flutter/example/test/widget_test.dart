import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_network/advanced.dart';
import 'package:omni_network_flutter/omni_network_flutter.dart';
import 'package:omni_network_flutter_example/main.dart';

void main() {
  testWidgets('posts load and show up in the inspector', (tester) async {
    final inspector = OmniInspector(enabled: true);
    addTearDown(inspector.dispose);
    final api = OmniNetwork(
      baseUrl: 'https://api.example.com',
      transport: fakeBackend()..latency = Duration.zero,
      enableLogging: true,
      logSink: inspector.sink('api'),
    );
    await tester.pumpWidget(ExampleApp(api: api, inspector: inspector));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Post 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Open network inspector'));
    await tester.pump();
    expect(find.text('Network (1)'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(api.close);
  });
}
