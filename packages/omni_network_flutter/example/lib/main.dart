import 'package:flutter/material.dart';
import 'package:omni_network/omni_network.dart';
import 'package:omni_network/testing.dart';
import 'package:omni_network_flutter/omni_network_flutter.dart';

/// A fake backend so the example runs without a server. Replace
/// `transport: backend` with nothing (Dio) and a real `baseUrl`.
OmniMock fakeBackend() => OmniMock()
  ..latency = const Duration(milliseconds: 300)
  ..get(
    '/posts',
    (_) => MockResponse.json([
      for (var i = 1; i <= 5; i++) {'id': i, 'title': 'Post $i'},
    ]),
  )
  ..get(
    '/posts/{id}',
    (r) => r.pathParams['id'] == '4'
        ? MockResponse.json({'error': 'gone'}, status: 404)
        : MockResponse.json({'id': r.pathParams['id'], 'body': 'Hello'}),
  )
  ..post('/login', (_) => MockResponse.json({'access_token': 'shown-as-***'}));

void main() {
  final inspector = OmniInspector(); // disabled automatically in release
  final api = OmniNetwork(
    baseUrl: 'https://api.example.com',
    transport: fakeBackend(),
    headers: {'Authorization': 'Bearer demo-token'},
    enableLogging: inspector.enabled,
    logSink: inspector.sink('api'),
  );
  runApp(ExampleApp(api: api, inspector: inspector));
}

/// The example app.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key, required this.api, required this.inspector});

  /// HTTP client.
  final OmniNetwork api;

  /// Inspector collecting [api]'s traffic.
  final OmniInspector inspector;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OmniNetwork',
    builder: (context, child) =>
        OmniInspectorLauncher(inspector: inspector, child: child!),
    home: PostsPage(api: api),
  );
}

/// Lists posts using a [RequestController].
class PostsPage extends StatefulWidget {
  /// Creates the page.
  const PostsPage({super.key, required this.api});

  /// HTTP client.
  final OmniNetwork api;

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  late final RequestController<List<Map<String, dynamic>>> _posts = widget.api
      .watchList('/posts', decoder: (j) => j);

  @override
  void dispose() {
    _posts.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Posts'),
      actions: [
        IconButton(
          tooltip: 'Log in',
          icon: const Icon(Icons.login),
          onPressed: () => widget.api
              .post<void>('/login', body: {'user': 'ana', 'password': 'pw'})
              .asResult(),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _posts.refresh,
        ),
      ],
    ),
    body: StreamBuilder(
      stream: _posts.stream,
      builder: (context, snap) => switch (snap.data ?? _posts.state) {
        RequestIdle() || RequestLoading(previous: null) => const Center(
          child: CircularProgressIndicator(),
        ),
        RequestError(:final error) => Center(child: Text('Error: $error')),
        RequestEmpty() => const Center(child: Text('No posts')),
        RequestLoading(:final previous?) ||
        RequestSuccess(data: final previous) => ListView(
          children: [
            for (final p in previous)
              ListTile(
                title: Text('${p['title']}'),
                onTap: () => widget.api
                    .get<Map<String, dynamic>>('/posts/${p['id']}')
                    .asResult(),
              ),
          ],
        ),
      },
    ),
  );
}
