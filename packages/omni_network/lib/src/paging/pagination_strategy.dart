import 'package:meta/meta.dart';

import '../core/omni_request.dart';
import '../core/omni_response.dart';

/// What a [PaginationStrategy] sees after a page has loaded.
@immutable
final class PageContext {
  /// Creates a context.
  const PageContext({
    required this.cursor,
    required this.json,
    required this.response,
    required this.itemCount,
  });

  /// Cursor used for this page (`null` for the first page).
  final Object? cursor;

  /// The full parsed body (before item extraction), for metadata.
  final Object? json;

  /// The raw response, e.g. for `Link` headers.
  final OmniRawResponse response;

  /// Items on this page.
  final int itemCount;
}

/// How pages are requested and when the end is reached.
///
/// A cursor is whatever the strategy needs (page number, offset, token,
/// URL); `null` means "first page".
abstract interface class PaginationStrategy {
  /// The request for the page at [cursor], derived from [base].
  OmniRequest requestFor(OmniRequest base, Object? cursor);

  /// The cursor of the next page, or `null` when there are no more pages.
  Object? nextCursor(PageContext page);
}

/// Reads a dotted [path] (`meta.next`, `data.items`, `pages.0`) from JSON.
Object? readJsonPath(Object? json, String path) {
  Object? v = json;
  for (final part in path.split('.')) {
    if (v is Map) {
      v = v[part];
    } else if (v is List) {
      final i = int.tryParse(part);
      v = i != null && i >= 0 && i < v.length ? v[i] : null;
    } else {
      return null;
    }
  }
  return v;
}

OmniRequest _withQuery(OmniRequest base, Map<String, Object?> extra) =>
    base.copyWith(query: {...base.query, ...extra});

/// `?page=N&limit=S` pagination.
///
/// The end is reached when a page is empty, has fewer than [pageSize] items
/// (when [pageSize] is set), [hasMoreKey] is `false`, or the page number
/// reaches [totalPagesKey].
final class PagePagination implements PaginationStrategy {
  /// Creates page-number pagination.
  const PagePagination({
    this.pageParam = 'page',
    this.sizeParam = 'limit',
    this.pageSize = 20,
    this.firstPage = 1,
    this.totalPagesKey,
    this.hasMoreKey,
  });

  /// Query parameter for the page number.
  final String pageParam;

  /// Query parameter for the page size (`null` to omit).
  final String? sizeParam;

  /// Requested page size (`null` = server default; disables the
  /// "short page" end check).
  final int? pageSize;

  /// Number of the first page.
  final int firstPage;

  /// JSON path of the total page count, if the API sends it.
  final String? totalPagesKey;

  /// JSON path of a `has_more` flag, if the API sends it.
  final String? hasMoreKey;

  @override
  OmniRequest requestFor(OmniRequest base, Object? cursor) => _withQuery(base, {
    pageParam: cursor ?? firstPage,
    if (sizeParam != null && pageSize != null) sizeParam!: pageSize,
  });

  @override
  Object? nextCursor(PageContext page) {
    final current = (page.cursor as int?) ?? firstPage;
    if (page.itemCount == 0) return null;
    if (hasMoreKey case final k?) {
      if (readJsonPath(page.json, k) == false) return null;
    }
    if (totalPagesKey case final k?) {
      final total = readJsonPath(page.json, k);
      if (total is num && current - firstPage + 1 >= total) return null;
    }
    final size = pageSize;
    if (size != null && page.itemCount < size) return null;
    return current + 1;
  }
}

/// `?offset=N&limit=L` pagination.
final class OffsetPagination implements PaginationStrategy {
  /// Creates offset pagination.
  const OffsetPagination({
    this.offsetParam = 'offset',
    this.limitParam = 'limit',
    this.limit = 20,
    this.totalKey,
  });

  /// Query parameter for the offset.
  final String offsetParam;

  /// Query parameter for the limit.
  final String limitParam;

  /// Items per request.
  final int limit;

  /// JSON path of the total item count, if sent.
  final String? totalKey;

  @override
  OmniRequest requestFor(OmniRequest base, Object? cursor) =>
      _withQuery(base, {offsetParam: cursor ?? 0, limitParam: limit});

  @override
  Object? nextCursor(PageContext page) {
    final next = ((page.cursor as int?) ?? 0) + page.itemCount;
    if (page.itemCount == 0 || page.itemCount < limit) return null;
    if (totalKey case final k?) {
      final total = readJsonPath(page.json, k);
      if (total is num && next >= total) return null;
    }
    return next;
  }
}

/// Opaque-cursor pagination: `?cursor=<token>`, next token in the body.
final class CursorPagination implements PaginationStrategy {
  /// Creates cursor pagination.
  const CursorPagination({
    this.cursorParam = 'cursor',
    this.nextCursorKey = 'next_cursor',
    this.limitParam,
    this.limit,
  });

  /// Query parameter carrying the cursor.
  final String cursorParam;

  /// JSON path of the next cursor; `null`/empty/missing ends paging.
  final String nextCursorKey;

  /// Optional limit parameter.
  final String? limitParam;

  /// Optional limit value.
  final int? limit;

  @override
  OmniRequest requestFor(OmniRequest base, Object? cursor) => _withQuery(base, {
    cursorParam: ?cursor,
    if (limitParam != null && limit != null) limitParam!: limit,
  });

  @override
  Object? nextCursor(PageContext page) {
    final next = readJsonPath(page.json, nextCursorKey);
    if (next == null || next == '' || page.itemCount == 0) return null;
    return '$next';
  }
}

/// RFC 8288 `Link: <url>; rel="next"` pagination (e.g. GitHub).
///
/// For safety the next URL must have the same scheme, host and port as the
/// current request; a link to another origin ends paging instead of
/// sending headers (and tokens) there.
final class LinkHeaderPagination implements PaginationStrategy {
  /// Creates Link-header pagination.
  const LinkHeaderPagination({this.rel = 'next'});

  /// Relation to follow.
  final String rel;

  static final _part = RegExp(r'<([^>]*)>\s*((?:;\s*[^;,]+)*)');

  @override
  OmniRequest requestFor(OmniRequest base, Object? cursor) => cursor == null
      ? base
      : base.copyWith(path: cursor as String, query: const {});

  @override
  Object? nextCursor(PageContext page) {
    final header = page.response.headers['link'];
    final current = page.response.requestUri;
    if (header == null || page.itemCount == 0) return null;
    for (final m in _part.allMatches(header)) {
      final params = m[2] ?? '';
      final rels = RegExp(
        r'rel="?([^";]+)"?',
      ).firstMatch(params)?[1]?.split(' ');
      if (rels == null || !rels.contains(rel)) continue;
      final target = current == null
          ? Uri.tryParse(m[1]!)
          : current.resolve(m[1]!);
      if (target == null) return null;
      if (current != null &&
          (target.scheme != current.scheme ||
              target.host != current.host ||
              target.port != current.port)) {
        return null;
      }
      return target.toString();
    }
    return null;
  }
}
