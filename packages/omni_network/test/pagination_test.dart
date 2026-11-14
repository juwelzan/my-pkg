import 'dart:async';
import 'dart:convert';

import 'package:omni_network/advanced.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

final class Item {
  Item(this.id);
  factory Item.fromJson(Map<String, dynamic> j) => Item(j['id'] as int);
  final int id;
  @override
  String toString() => 'Item($id)';
}

List<Map<String, int>> ids(int from, int count) => [
  for (var i = from; i < from + count; i++) {'id': i},
];

OmniRawResponse body(Object json, {Map<String, String> headers = const {}}) =>
    OmniRawResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json', ...headers},
      bodyBytes: utf8.encode(jsonEncode(json)),
    );

void main() {
  late MockTransport mock;
  late OmniNetwork api;

  setUp(() {
    mock = MockTransport((_) => body([]));
    api = OmniNetwork(baseUrl: 'https://h.io/api', transport: mock);
  });
  tearDown(() => api.close());

  Map<String, String> q(int i) => mock.requests[i].uri.queryParameters;

  group('PagePagination', () {
    test('loads pages until a short page', () async {
      // 25 items, page size 10 -> pages of 10, 10, 5.
      mock.handler = (r) {
        final page = int.parse(r.uri.queryParameters['page']!);
        final start = (page - 1) * 10;
        return body(ids(start, start + 10 > 25 ? 25 - start : 10));
      };
      final pager = api.paginate<Item>(
        '/items',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 10),
        query: {'sort': 'name'},
      );
      while (pager.hasMore) {
        await pager.next();
      }
      expect(pager.items.map((i) => i.id), List.generate(25, (i) => i));
      expect(pager.pageCount, 3);
      expect(q(0), {'sort': 'name', 'page': '1', 'limit': '10'});
      expect(q(2)['page'], '3');
      expect(await pager.next(), isEmpty);
      expect(mock.requests, hasLength(3));
    });

    test('exact multiple ends on an empty page', () async {
      mock.handler = (r) =>
          body(r.uri.queryParameters['page'] == '3' ? [] : ids(0, 10));
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 10),
      );
      while (pager.hasMore) {
        await pager.next();
      }
      expect(pager.items, hasLength(20));
      expect(mock.requests, hasLength(3));
    });

    test('totalPagesKey / hasMoreKey with itemsKey', () async {
      mock.handler = (r) {
        final p = int.parse(r.uri.queryParameters['page']!);
        return body({
          'data': ids(p * 100, 2),
          'meta': {'total_pages': 2, 'has_more': p < 2},
        });
      };
      for (final s in [
        const PagePagination(pageSize: null, totalPagesKey: 'meta.total_pages'),
        const PagePagination(pageSize: null, hasMoreKey: 'meta.has_more'),
      ]) {
        mock.requests.clear();
        final pager = api.paginate<Item>(
          '/i',
          decoder: Item.fromJson,
          strategy: s,
          itemsKey: 'data',
        );
        while (pager.hasMore) {
          await pager.next();
        }
        expect(pager.items.map((i) => i.id), [100, 101, 200, 201]);
        expect(mock.requests, hasLength(2));
        expect(q(0).containsKey('limit'), isFalse);
      }
    });
  });

  test('OffsetPagination with totalKey', () async {
    mock.handler = (r) {
      final off = int.parse(r.uri.queryParameters['offset']!);
      return body({'items': ids(off, 5), 'total': 15});
    };
    final pager = api.paginate<Item>(
      '/i',
      decoder: Item.fromJson,
      strategy: const OffsetPagination(limit: 5, totalKey: 'total'),
      itemsKey: 'items',
    );
    while (pager.hasMore) {
      await pager.next();
    }
    expect(pager.items, hasLength(15));
    expect([for (var i = 0; i < 3; i++) q(i)['offset']], ['0', '5', '10']);
  });

  test('CursorPagination', () async {
    mock.handler = (r) => switch (r.uri.queryParameters['cursor']) {
      null => body({'data': ids(0, 2), 'next_cursor': 'abc'}),
      'abc' => body({'data': ids(2, 2), 'next_cursor': 'def'}),
      _ => body({'data': ids(4, 1), 'next_cursor': null}),
    };
    final pager = api.paginate<Item>(
      '/i',
      decoder: Item.fromJson,
      strategy: const CursorPagination(limitParam: 'n', limit: 2),
      itemsKey: 'data',
    );
    while (pager.hasMore) {
      await pager.next();
    }
    expect(pager.items.map((i) => i.id), [0, 1, 2, 3, 4]);
    expect(q(0), {'n': '2'});
    expect(q(1), {'cursor': 'abc', 'n': '2'});
  });

  test('repeating cursor stops paging (server loop guard)', () async {
    mock.handler = (_) => body({'data': ids(0, 1), 'next_cursor': 'same'});
    final pager = api.paginate<Item>(
      '/i',
      decoder: Item.fromJson,
      strategy: const CursorPagination(),
      itemsKey: 'data',
    );
    var guard = 0;
    while (pager.hasMore && guard++ < 10) {
      await pager.next();
    }
    expect(mock.requests, hasLength(2));
  });

  test('maxPages', () async {
    mock.handler = (_) => body({
      'data': ids(0, 1),
      'next_cursor': '${DateTime.now().microsecondsSinceEpoch}',
    });
    final pager = api.paginate<Item>(
      '/i',
      decoder: Item.fromJson,
      strategy: const CursorPagination(),
      itemsKey: 'data',
      maxPages: 3,
    );
    while (pager.hasMore) {
      await pager.next();
    }
    expect(pager.pageCount, 3);
  });

  group('LinkHeaderPagination', () {
    test('follows rel=next on the same origin', () async {
      mock.handler = (r) => r.uri.queryParameters['page'] == '2'
          ? body(
              ids(10, 1),
              headers: {'link': '<https://h.io/api/i?page=1>; rel="prev"'},
            )
          : body(
              ids(0, 1),
              headers: {
                'link':
                    '<https://h.io/api/i?page=1>; rel="first", '
                    '</api/i?page=2&per_page=1>; rel="next"',
              },
            );
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const LinkHeaderPagination(),
      );
      while (pager.hasMore) {
        await pager.next();
      }
      expect(pager.items.map((i) => i.id), [0, 10]);
      expect(
        mock.requests[1].uri.toString(),
        'https://h.io/api/i?page=2&per_page=1',
      );
    });

    test('refuses a next link to another origin (token safety)', () async {
      mock.handler = (_) => body(
        ids(0, 1),
        headers: {'link': '<https://evil.example/steal>; rel="next"'},
      );
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const LinkHeaderPagination(),
      );
      await pager.next();
      expect(pager.hasMore, isFalse);
      expect(mock.requests, hasLength(1));
    });
  });

  group('pager behaviour', () {
    test('concurrent next() shares one request', () async {
      final gate = Completer<OmniRawResponse>();
      mock.handler = (_) => gate.future;
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 2),
      );
      final a = pager.next();
      final b = pager.next();
      expect(identical(a, b), isTrue);
      expect(pager.isLoading, isTrue);
      gate.complete(body(ids(0, 2)));
      expect(await a, hasLength(2));
      expect(pager.items, hasLength(2));
      expect(mock.requests, hasLength(1));
      expect(pager.isLoading, isFalse);
    });

    test('failure keeps state; next() retries the same page', () async {
      var fail = true;
      mock.handler = (r) =>
          fail ? OmniRawResponse(statusCode: 500) : body(ids(0, 2));
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 2),
      );
      await expectLater(pager.next(), throwsA(isA<HttpFailure>()));
      expect(pager.lastError, isA<HttpFailure>());
      expect(pager.items, isEmpty);
      expect(pager.isLoading, isFalse);
      fail = false;
      await pager.next();
      expect(q(1)['page'], '1');
      expect(pager.lastError, isNull);
    });

    test('decode errors surface as DecodeFailure', () async {
      mock.handler = (_) => body({'data': 'nope'});
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(),
        itemsKey: 'data',
      );
      await expectLater(pager.next(), throwsA(isA<DecodeFailure>()));
    });

    test('refresh discards a stale in-flight page', () async {
      final first = Completer<OmniRawResponse>();
      var calls = 0;
      mock.handler = (_) => ++calls == 1 ? first.future : body(ids(100, 1));
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 1),
      );
      final stale = pager.next();
      await Future<void>.delayed(Duration.zero);
      final fresh = pager.refresh();
      await expectLater(stale, throwsA(isA<CancelledFailure>()));
      first.complete(body(ids(0, 1)));
      await fresh;
      expect(pager.items.map((i) => i.id), [100]);
      expect(pager.lastError, isNull);
    });

    test('uses the client response adapter when itemsKey is null', () async {
      final env = OmniNetwork(
        baseUrl: 'https://h.io',
        transport: mock,
        responseAdapter: const EnvelopeResponseAdapter(),
      );
      addTearDown(env.close);
      mock.handler = (_) => body({'data': ids(0, 3)});
      final pager = env.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(pageSize: 5),
      );
      expect(await pager.next(), hasLength(3));
      expect(pager.hasMore, isFalse);
    });

    test('close cancels and further next() throws StateError', () async {
      mock.handler = (_) => Completer<OmniRawResponse>().future;
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(),
      );
      final f = pager.next();
      await Future<void>.delayed(Duration.zero);
      final failed = expectLater(f, throwsA(isA<CancelledFailure>()));
      await pager.close();
      await failed;
      expect(pager.next, throwsStateError);
      expect(api.pendingRequests, 0);
    });

    test('items view is unmodifiable', () async {
      mock.handler = (_) => body(ids(0, 1));
      final pager = api.paginate<Item>(
        '/i',
        decoder: Item.fromJson,
        strategy: const PagePagination(),
      );
      await pager.next();
      expect(() => pager.items.add(Item(9)), throwsUnsupportedError);
    });
  });

  test('readJsonPath', () {
    final j = {
      'a': {
        'b': [
          {'c': 1},
        ],
      },
    };
    expect(readJsonPath(j, 'a.b.0.c'), 1);
    expect(readJsonPath(j, 'a.x'), isNull);
    expect(readJsonPath(j, 'a.b.5'), isNull);
    expect(readJsonPath(1, 'a'), isNull);
  });
}
