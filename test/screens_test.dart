import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_route/omni_route.dart';

class StudentScreen extends OmniStatelessWidget {
  const StudentScreen({super.key, this.label = 'a'});
  final String label;
  static int builds = 0;
  @override
  String get screenName => 'Students';
  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(label, textDirection: TextDirection.ltr);
  }
}

class EmptyNameScreen extends OmniStatelessWidget {
  const EmptyNameScreen({super.key});
  @override
  String get screenName => '  ';
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class DashboardScreen extends OmniStatefulWidget {
  const DashboardScreen({super.key, this.label = 'a'});
  final String label;
  @override
  String get screenName => 'Dashboard';
  @override
  String get title => 'Home';
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

final events = <String>[];

class _DashboardState extends OmniState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    events.add('init:${metadata.screenName}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    events.add('deps');
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    events.add('update:${old.label}->${widget.label}');
  }

  @override
  void dispose() {
    events.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(widget.label, textDirection: TextDirection.ltr);
}

void main() {
  setUp(events.clear);

  group('OmniStatelessWidget', () {
    test('metadata', () {
      const s = StudentScreen();
      expect(s.screenName, 'Students');
      expect(s.title, 'Students');
      expect(s.name, 'StudentScreen');
      expect(s.metadata.type, StudentScreen);
      expect(s.metadata, const StudentScreen(label: 'b').metadata);
    });

    testWidgets('builds and rebuilds like StatelessWidget', (t) async {
      StudentScreen.builds = 0;
      await t.pumpWidget(const StudentScreen(label: 'one'));
      expect(find.text('one'), findsOneWidget);
      await t.pumpWidget(const StudentScreen(label: 'two'));
      expect(find.text('two'), findsOneWidget);
      expect(StudentScreen.builds, 2);
    });

    testWidgets('empty screenName throws', (t) async {
      await t.pumpWidget(const EmptyNameScreen());
      final e = t.takeException();
      expect(e, isA<OmniRouteException>()
          .having((e) => e.code, 'code', OmniErrorCode.emptyScreenName));
    });
  });

  group('OmniStatefulWidget', () {
    test('metadata with custom title', () {
      const d = DashboardScreen();
      expect(d.metadata.title, 'Home');
      expect(d.metadata.type, DashboardScreen);
    });

    testWidgets('follows Flutter State lifecycle', (t) async {
      await t.pumpWidget(const DashboardScreen(label: 'a'));
      await t.pumpWidget(const DashboardScreen(label: 'b'));
      await t.pumpWidget(const SizedBox());
      expect(events, ['init:Dashboard', 'deps', 'update:a->b', 'dispose']);
    });
  });
}
