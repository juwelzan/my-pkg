// Compares OmniRoute with the same app written directly on GoRouter +
// BlocProvider. Run in profile mode (any device; window may be in background):
//   flutter run --profile -d macos -t benchmark/benchmark_main.dart
// Results are printed as `BENCH {...}` lines, then the app exits.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_route/omni_route.dart';

const cycles = int.fromEnvironment('CYCLES', defaultValue: 300);

class ItemBloc extends Bloc<int, int> {
  ItemBloc(super.id) {
    on<int>((e, emit) => emit(e));
  }
}

class ListBloc extends Bloc<int, int> {
  ListBloc() : super(0);
}

Widget itemBody(int id, BuildContext context) => Scaffold(
  appBar: AppBar(title: Text('Item $id')),
  body: ListView.builder(
    itemCount: 30,
    itemBuilder: (_, i) =>
        ListTile(title: Text('Row $i of ${context.read<ItemBloc>().state}')),
  ),
);

Widget homeBody() => Scaffold(
  appBar: AppBar(title: const Text('Home')),
  body: ListView.builder(
    itemCount: 30,
    itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
  ),
);

// ── OmniRoute version ──
class OHome extends OmniStatelessWidget {
  const OHome({super.key});
  @override
  String get screenName => 'Home';
  @override
  List<Provide> get provide => const [Provide<ListBloc>()];
  @override
  Widget build(BuildContext context) => homeBody();
}

class OItem extends OmniStatelessWidget {
  const OItem(this.id, {super.key});
  final int id;
  @override
  String get screenName => 'Item';
  @override
  List<Provide> get provide => [Provide<ItemBloc>.create((_) => ItemBloc(id))];
  @override
  Widget build(BuildContext context) => itemBody(id, context);
}

Widget omniApp() => OmniApp(
  blocs: [OmniBloc<ListBloc>((_) => ListBloc())],
  routes: [
    OmniPage('/', (_) => const OHome()),
    OmniPage('/item/:id', (p) => OItem(p.pathInt('id'))),
  ],
  builder: (_, r) => MaterialApp.router(routerConfig: r),
);

// ── Raw GoRouter version ──
class RawApp extends StatefulWidget {
  const RawApp({super.key});
  @override
  State<RawApp> createState() => RawAppState();
}

class RawAppState extends State<RawApp> {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (_, s) => MaterialPage<void>(
          key: s.pageKey,
          child: BlocProvider(
            create: (_) => ListBloc(),
            child: Builder(builder: (_) => homeBody()),
          ),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        // Same page type OmniPage uses, so both animate identically.
        pageBuilder: (_, s) {
          final id = int.parse(s.pathParameters['id']!);
          return MaterialPage<void>(
            key: s.pageKey,
            child: BlocProvider(
              create: (_) => ItemBloc(id),
              child: Builder(builder: (c) => itemBody(id, c)),
            ),
          );
        },
      ),
    ],
  );

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);
}

/// Runs frames by hand (no vsync needed, so it works with a background
/// window) and returns the UI-thread time of each frame in microseconds.
class FrameDriver {
  FrameDriver(this.binding);
  final WidgetsBinding binding;
  Duration _clock = Duration.zero;
  final uiFrameUs = <int>[];

  int frame() {
    final sw = Stopwatch()..start();
    _clock += const Duration(microseconds: 16667);
    binding.handleBeginFrame(_clock);
    binding.handleDrawFrame();
    final us = sw.elapsedMicroseconds;
    uiFrameUs.add(us);
    return us;
  }

  /// Frames until nothing is scheduled (animations finished). Returns total µs.
  int settle() {
    var total = 0;
    for (var i = 0; i < 300 && (i == 0 || binding.hasScheduledFrame); i++) {
      total += frame();
    }
    return total;
  }

  void show(Widget w) {
    binding.attachRootWidget(binding.wrapWithDefaultView(w));
    binding.scheduleFrame();
  }
}

int pct(List<int> xs, double p) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * p).round()];
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Let the engine finish startup before measuring.
  await Future<void>.delayed(const Duration(seconds: 2));
  final results = <String, Object>{};

  void run(
    String key,
    Widget app,
    void Function(String) push,
    void Function() pop,
  ) {
    final d = FrameDriver(binding);
    d.show(const SizedBox());
    d.settle();
    final rssStart = ProcessInfo.currentRss;

    final sw = Stopwatch()..start();
    d.show(app);
    d.settle();
    final startupUs = sw.elapsedMicroseconds;

    for (var i = 0; i < 20; i++) {
      push('/item/$i');
      d.settle();
      pop();
      d.settle();
    }
    d.uiFrameUs.clear();

    final pushUs = <int>[], popUs = <int>[], pushTotalUs = <int>[];
    for (var i = 0; i < cycles; i++) {
      push('/item/$i');
      pushUs.add(d.frame());
      pushTotalUs.add(pushUs.last + d.settle());
      pop();
      popUs.add(d.frame());
      d.settle();
    }
    final rssEnd = ProcessInfo.currentRss;
    results[key] = {
      'startup_to_settled_us': startupUs,
      'push_first_frame_ui_us_p50': pct(pushUs, .5),
      'push_first_frame_ui_us_p90': pct(pushUs, .9),
      'push_all_frames_ui_us_p50': pct(pushTotalUs, .5),
      'pop_first_frame_ui_us_p50': pct(popUs, .5),
      'pop_first_frame_ui_us_p90': pct(popUs, .9),
      'ui_frame_us_p50': pct(d.uiFrameUs, .5),
      'ui_frame_us_p99': pct(d.uiFrameUs, .99),
      'ui_frame_us_max': pct(d.uiFrameUs, 1),
      'frames_measured': d.uiFrameUs.length,
      'rss_growth_kb': (rssEnd - rssStart) ~/ 1024,
    };
    // ignore: avoid_print
    print('BENCH ${jsonEncode({key: results[key]})}');
    d.show(const SizedBox());
    d.settle();
  }

  final rawKey = GlobalKey<RawAppState>();
  GoRouter rawRouter() => rawKey.currentState!.router;
  // MODE=both (default) alternates raw/omni; MODE=raw or MODE=omni runs one
  // kind for ROUNDS rounds, to separate harness drift from OmniRoute cost.
  const mode = String.fromEnvironment('MODE', defaultValue: 'both');
  const rounds = int.fromEnvironment('ROUNDS', defaultValue: 3);
  for (var round = 1; round <= rounds; round++) {
    if (mode != 'omni') {
      run(
        'raw_$round',
        RawApp(key: rawKey),
        (l) => rawRouter().push(l),
        () => rawRouter().pop(),
      );
    }
    if (mode != 'raw') {
      run('omni_$round', omniApp(), (l) => OmniRoute.push(l), OmniRoute.pop);
    }
  }
  // ignore: avoid_print
  print('BENCH done');
  exit(0);
}
