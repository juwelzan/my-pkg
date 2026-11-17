# OmniNetwork — সম্পূর্ণ ব্যবহার গাইড

এই গাইডে `omni_network` প্রথম install থেকে production অ্যাপ পর্যন্ত ধাপে ধাপে দেখানো হয়েছে:
client তৈরি, model, error, login/token, log, retry, cache, upload/download, pagination,
UI state, offline queue, test, আর OmniRoute-এর সাথে জোড়া লাগানো।

> সংক্ষেপে দেখতে চাইলে: [README](../README.md) (ইংরেজি)।
> প্রতিটা option-এর ইংরেজি reference: [advanced.md](advanced.md)।
> এই গাইড `omni_network 0.1.1`-এর জন্য।

---

## সূচিপত্র

1. [Install](#১-install)
2. [৫ মিনিটে প্রথম call](#২-৫-মিনিটে-প্রথম-call)
3. [অ্যাপে কীভাবে সাজাবেন — প্রস্তাবিত গঠন](#৩-অ্যাপে-কীভাবে-সাজাবেন)
4. [Client-এর সব setting](#৪-client-এর-সব-setting)
5. [Request পাঠানো](#৫-request-পাঠানো)
6. [Response পড়া](#৬-response-পড়া)
7. [Backend-এর response format — Adapter](#৭-backend-এর-response-format--adapter)
8. [Error সামলানো](#৮-error-সামলানো)
9. [Login, Token আর Refresh](#৯-login-token-আর-refresh)
10. [Interceptor](#১০-interceptor)
11. [Terminal Log](#১১-terminal-log)
12. [Retry আর Circuit Breaker](#১২-retry-আর-circuit-breaker)
13. [Cache আর De-duplication](#১৩-cache-আর-de-duplication)
14. [Request বাতিল](#১৪-request-বাতিল)
15. [Upload আর Download](#১৫-upload-আর-download)
16. [Pagination — infinite scroll](#১৬-pagination--infinite-scroll)
17. [UI-তে Loading / Data / Error](#১৭-ui-তে-loading--data--error)
18. [Endpoint আর OpenAPI](#১৮-endpoint-আর-openapi)
19. [Offline Queue](#১৯-offline-queue)
20. [Low-level: sendRaw, stream, cURL](#২০-low-level-sendraw-stream-curl)
21. [Test — OmniMock](#২১-test--omnimock)
22. [Flutter: Secure storage আর Inspector](#২২-flutter-secure-storage-আর-inspector)
23. [Live data: WebSocket আর SSE](#২৩-live-data-websocket-আর-sse)
24. [OmniRoute-এর সাথে পুরো অ্যাপ](#২৪-omniroute-এর-সাথে-পুরো-অ্যাপ)
25. [নিরাপত্তা](#২৫-নিরাপত্তা)
26. [Platform](#২৬-platform)
27. [সমস্যা ও সমাধান (FAQ)](#২৭-সমস্যা-ও-সমাধান-faq)
28. [Cheat sheet](#২৮-cheat-sheet)

---

## ১. Install

pub.dev-এ এখনো publish হয়নি, তাই GitHub tag দিয়ে যোগ করুন:

```yaml
dependencies:
  omni_network:
    git:
      url: https://github.com/juwelzan/omni_route.git
      path: packages/omni_network
      ref: omni_network-v0.1.1

  # ঐচ্ছিক — Flutter অ্যাপে secure token storage আর inspector
  omni_network_flutter:
    git:
      url: https://github.com/juwelzan/omni_route.git
      path: packages/omni_network_flutter
      ref: omni_network_flutter-v0.1.0

  # ঐচ্ছিক — WebSocket / Server-Sent Events
  omni_network_ws:
    git:
      url: https://github.com/juwelzan/omni_route.git
      path: packages/omni_network_ws
      ref: omni_network_ws-v0.1.0

dev_dependencies:
  # ঐচ্ছিক — OpenAPI spec থেকে model আর endpoint তৈরি
  omni_network_openapi:
    git:
      url: https://github.com/juwelzan/omni_route.git
      path: packages/omni_network_openapi
      ref: omni_network_openapi-v0.1.0
```

> **খেয়াল রাখুন:** `omni_network_flutter` আর `omni_network_ws`-এর `v0.1.0` tag নিজের
> ভিতরে `omni_network 0.1.0` ব্যবহার করে। এগুলো একসাথে নিলে pub একটা মাত্র
> `omni_network` বেছে নেবে; conflict দেখালে `dependency_overrides`-এ `omni_network`-কে
> `omni_network-v0.1.1` tag-এ রাখুন।

তিনটা import আছে — যেটা দরকার সেটাই নিন:

| Import | কী পাবেন |
|---|---|
| `package:omni_network/omni_network.dart` | সাধারণ সব কিছু: client, get/post, error, `OmniAuth`, retry, cache, pagination, request state |
| `package:omni_network/advanced.dart` | উপরের সব + `OfflineQueue`, `CircuitBreaker`, `PrettyLogSink`, `Redactor`, transport, store, cURL, `BearerAuth` |
| `package:omni_network/testing.dart` | `OmniMock`, `MockResponse` — test-এর জন্য |

`omni_network` pure Dart — Flutter, router বা কোনো state management লাগে না।
ভিতরে HTTP-র কাজ করে [Dio](https://pub.dev/packages/dio)।

---

## ২. ৫ মিনিটে প্রথম call

```dart
import 'package:omni_network/omni_network.dart';

class User {
  User({required this.id, required this.name});
  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);
  final int id;
  final String name;
}

Future<void> main() async {
  final api = OmniNetwork(
    baseUrl: 'https://api.example.com/v1',
    enableLogging: true, // debug-এ প্রতিটা call terminal-এ দেখাবে
  );

  try {
    final user = await api.get<User>('/users/10', decoder: User.fromJson);
    print(user.name);
  } on OmniNetworkException catch (e) {
    print(e.message); // নিরাপদ — এতে কখনো token থাকে না
  } finally {
    await api.close();
  }
}
```

তিনটা জিনিস মনে রাখলেই চলে:

1. **একটা client, পুরো অ্যাপে।** প্রতি request-এ নতুন `OmniNetwork` বানাবেন না।
2. **`decoder`** = JSON map থেকে আপনার class বানানোর function — সাধারণত `fromJson`।
3. **সব error** একটাই type: `OmniNetworkException`।

---

## ৩. অ্যাপে কীভাবে সাজাবেন

বড় অ্যাপে network কোড এক জায়গায় রাখুন; screen বা Bloc সরাসরি URL লিখবে না।

```
lib/
  data/
    api_client.dart        ← একটা OmniNetwork তৈরি (base URL, auth, log, retry)
    models/
      user.dart            ← User.fromJson / toJson
    repositories/
      user_repository.dart ← সব user-সংক্রান্ত call
  features/...             ← Bloc/screen শুধু repository ব্যবহার করে
```

**`api_client.dart`**

```dart
import 'package:omni_network/omni_network.dart';

OmniNetwork createApi({required void Function() onLogout}) => OmniNetwork(
  baseUrl: const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.example.com/v1',
  ),
  enableLogging: true,                  // release build-এ নিজে থেকেই বন্ধ
  timeout: const Duration(seconds: 20),
  headers: {'Accept-Language': 'bn'},
  retry: const RetryPolicy(),           // ব্যর্থ GET/HEAD সর্বোচ্চ ৩ বার
  cache: OmniCache(),                   // HTTP cache নিয়ম মেনে
  auth: OmniAuth(
    refresh: (tokens, api) async {
      final r = await api.post<Map<String, dynamic>>(
        '/auth/refresh',
        body: {'refresh_token': tokens.refresh},
      );
      return Tokens(
        access: r['access_token'] as String,
        refresh: r['refresh_token'] as String?,
        expiresIn: Duration(seconds: r['expires_in'] as int),
      );
    },
    onLogout: onLogout,
  ),
);
```

**`user_repository.dart`**

```dart
class UserRepository {
  UserRepository(this._api);
  final OmniNetwork _api;

  Future<User> me() => _api.get<User>('/me', decoder: User.fromJson);

  Future<List<User>> search(String q, {int page = 1}) => _api.getList<User>(
    '/users',
    decoder: User.fromJson,
    query: {'q': q, 'page': page},
  );

  Future<User> rename(int id, String name) => _api.patch<User>(
    '/users/$id',
    body: {'name': name},
    decoder: User.fromJson,
  );

  Future<void> remove(int id) => _api.delete<void>('/users/$id');
}
```

এভাবে রাখলে test-এ শুধু client-এর `transport:` বদলে `OmniMock` দিলেই পুরো repository
backend ছাড়া চালানো যায় ([২১ নম্বর অংশ](#২১-test--omnimock))।

---

## ৪. Client-এর সব setting

```dart
final api = OmniNetwork(
  baseUrl: 'https://api.example.com/v1',
  headers: {'X-App': 'shop'},
  timeout: const Duration(seconds: 30),
  enableLogging: true,
  logOptions: const LogOptions(headers: true),
  auth: OmniAuth(refresh: ...),
  retry: const RetryPolicy(),
  cache: OmniCache(),
  interceptors: [AppVersionHeader()],
);
```

| Setting | Default | কী করে |
|---|---|---|
| `baseUrl` | `null` | সব relative path এর সাথে জোড়া লাগে। `'/users'` → `https://api.example.com/v1/users` |
| `headers` | `{}` | সব request-এ যায় |
| `timeout` | ৩০ সেকেন্ড | প্রতিটা request-এর সর্বোচ্চ সময় (per-call `timeout:` দিয়ে বদলানো যায়) |
| `enableLogging` | `false` | terminal-এ প্রতিটা call ([১১](#১১-terminal-log)); release build-এ বন্ধ থাকে |
| `logOptions` | `LogOptions()` | log-এর বিস্তারিত (header, body, লাইন সংখ্যা) |
| `logSink` | `PrettyLogSink()` | log কোথায় যাবে — নিজের `Logger`, inspector ইত্যাদি (`advanced.dart`) |
| `logInRelease` | `false` | release build-এও log চাইলে `true` (সাধারণত দরকার নেই) |
| `logBodies` | `true` | `false` দিলে log-এ body একেবারেই যাবে না |
| `redactor` | `Redactor()` | log-এ কোন key/header লুকাবে (বাড়ানো যায়, কমানো যায় না) |
| `auth` | `OmniAuth()` | token manager ([৯](#৯-login-token-আর-refresh)) |
| `token` | — | নিজের রাখা token দিতে: `token: () => myToken`। `auth`-এর বদলে, দুটো একসাথে নয় |
| `interceptors` | `[]` | প্রতিটা request/response-এ নিজের কাজ ([১০](#১০-interceptor)) |
| `retry` | `null` (বন্ধ) | `RetryPolicy` ([১২](#১২-retry-আর-circuit-breaker)) |
| `circuitBreaker` | `null` | বারবার ব্যর্থ host-কে কিছুক্ষণ ডাকা বন্ধ |
| `cache` | `null` (বন্ধ) | `OmniCache` ([১৩](#১৩-cache-আর-de-duplication)) |
| `deduplicate` | `true` | একই সময়ে একই GET একবারই network-এ যায় |
| `responseAdapter` | `PlainResponseAdapter()` | backend-এর `{ "data": ... }` খোলস খোলা ([৭](#৭-backend-এর-response-format--adapter)) |
| `followRedirects` / `maxRedirects` | `true` / `5` | redirect নিরাপদভাবে অনুসরণ |
| `transport` | `DioTransport()` | আসল HTTP layer; test-এ `OmniMock` |

উপযোগী getter:

```dart
api.isLogging;   // এখন log হচ্ছে কি না (release build-এ false)
api.isClosed;    // close() হয়েছে কি না
api.auth;        // token manager
api.cancelAll(); // চলমান সব request বাতিল, client চালু থাকে
await api.close(); // সব বাতিল, client বন্ধ
```

---

## ৫. Request পাঠানো

### ৫.১ Verb

```dart
final user  = await api.get<User>('/users/10', decoder: User.fromJson);
final users = await api.getList<User>('/users', decoder: User.fromJson);

final made = await api.post<User>('/users',
    body: {'name': 'Ana'}, decoder: User.fromJson);
await api.put<void>('/users/10', body: {'name': 'Ana B.'});    // পুরো বদল
await api.patch<void>('/users/10', body: {'name': 'Ana C.'});  // আংশিক বদল
await api.delete<void>('/users/10');

final head = await api.head('/files/report.pdf');              // শুধু header
print(head.headers['content-length']);
```

### ৫.২ Decoder ছাড়া কী ফেরত আসে

| `T` | ফলাফল |
|---|---|
| `User` + `decoder: User.fromJson` | আপনার model |
| `Map<String, dynamic>` / `List<dynamic>` | কাঁচা JSON |
| `int`, `double`, `bool` | JSON মান (`api.get<int>('/users/count')`) |
| `String` | response-এর লেখা যেমন আছে |
| `void` বা nullable (`User?`) | খালি body গ্রহণযোগ্য (`204 No Content`) |

ভুল type হলে `DecodeFailure` হয় — অ্যাপ crash করে না।
বড় JSON (২৫৬ KB-এর বেশি) mobile/desktop-এ আলাদা isolate-এ decode হয়, তাই UI আটকায় না।

### ৫.৩ Body

| আপনি যা দেন | যা যায় | Content-Type |
|---|---|---|
| `Map` / `List` / `num` / `bool` | JSON | `application/json; charset=utf-8` |
| `String` | যেমন আছে | `text/plain; charset=utf-8` |
| `Uint8List` / `List<int>` | bytes | `application/octet-stream` |
| ফাইল + field | multipart | `api.upload(...)` ব্যবহার করুন ([১৫](#১৫-upload-আর-download)) |

নিজে `headers: {'Content-Type': ...}` দিলে সেটাই থাকে। GET/HEAD-এ body দিলে
`RequestFailure` হয় (ভুলটা সাথে সাথে ধরা পড়ে)।

### ৫.৪ Query

```dart
await api.getList<User>('/users', decoder: User.fromJson, query: {
  'page': 2,             // ?page=2
  'tag': ['a', 'b'],     // &tag=a&tag=b
  'q': 'রহিম',           // নিজে থেকেই encode হয়
});
```

### ৫.৫ প্রতিটা call-এর ঐচ্ছিক setting

সব verb একই setting নেয় (GET-এ শুধু `cache:` বাড়তি):

```dart
await api.get<User>('/me',
  decoder: User.fromJson,
  query: {'expand': 'roles'},           // ?expand=roles
  headers: {'X-Trace': traceId},        // শুধু এই call-এ বাড়তি header
  timeout: const Duration(seconds: 5),  // শুধু এই call-এর সময়সীমা
  cancelToken: token,                   // পরে token.cancel()
  retry: RetryPolicy.none,              // এই call-এ retry বন্ধ
  cache: CachePolicy.networkFirst,      // এই call-এর cache নিয়ম
  auth: false,                          // token পাঠাবে না (login, public API)
  adapter: const EnvelopeResponseAdapter(), // শুধু এই call-এর format
);
```

---

## ৬. Response পড়া

শুধু data নয়, status/header-ও লাগলে `...Response` method ব্যবহার করুন:

```dart
final res = await api.getResponse<User>('/users/10', decoder: User.fromJson);

res.data;               // User
res.statusCode;         // 200
res.headers['etag'];    // header (key সবসময় lowercase)
res.duration;           // কত সময় লেগেছে
res.source;             // ResponseSource.network / cache / revalidated
res.raw.text;           // কাঁচা লেখা
```

আছে: `getResponse`, `postResponse`, `putResponse`, `patchResponse`, `deleteResponse`,
`callResponse`।

---

## ৭. Backend-এর response format — Adapter

অনেক backend সব কিছু একটা খোলসে মুড়ে পাঠায়:

```json
{ "data": { "id": 10, "name": "Ana" }, "meta": { "page": 1 } }
```

একবার বলে দিন, তারপর decoder সরাসরি ভিতরের অংশ পায়:

```dart
final api = OmniNetwork(
  baseUrl: url,
  responseAdapter: const EnvelopeResponseAdapter(dataKey: 'data'),
);

final user = await api.get<User>('/users/10', decoder: User.fromJson); // data খোলা
```

শুধু একটা call-এ ভিন্ন format: `adapter: const PlainResponseAdapter()`।
নিজের নিয়ম লাগলে `ResponseAdapter` implement করুন (`advanced.dart`)।

---

## ৮. Error সামলানো

### ৮.১ সহজ check

সব ব্যর্থতা `OmniNetworkException`। ধরন মুখস্থ রাখতে হয় না — getter দিয়েই চলে:

```dart
try {
  final user = await api.get<User>('/users/10', decoder: User.fromJson);
  show(user);
} on OmniNetworkException catch (e) {
  if (e.isOffline) {
    showMessage('ইন্টারনেট সংযোগ নেই');   // connection নেই বা timeout
  } else if (e.isUnauthorized) {
    goToLogin();                            // 401, বা refresh ব্যর্থ
  } else if (e.statusCode == 404) {
    showMessage('পাওয়া যায়নি');
  } else if (e.isCancelled) {
    // ব্যবহারকারী/অ্যাপ বাতিল করেছে — কিছু দেখানোর দরকার নেই
  } else {
    showMessage(e.message);                 // নিরাপদ: token/body/query নেই
  }
}
```

| Getter | কখন `true` |
|---|---|
| `isOffline` | `ConnectionFailure` বা `TimeoutFailure` |
| `isTimeout` | `TimeoutFailure` |
| `isCancelled` | `CancelledFailure` বা `ClosedFailure` |
| `isUnauthorized` | status 401 বা `AuthFailure` |
| `statusCode` | server উত্তর দিলে তার code, নইলে `null` |

### ৮.২ Error-এর ধরন (sealed)

| Type | কখন |
|---|---|
| `HttpFailure` | server 2xx ছাড়া অন্য status দিয়েছে; `e.response` দিয়ে পুরো response |
| `DecodeFailure` | JSON আপনার model-এ মেলেনি |
| `TimeoutFailure` | সময়সীমা পার |
| `ConnectionFailure` | network নেই, DNS, TLS ইত্যাদি |
| `CancelledFailure` | `cancelToken.cancel()` বা `api.cancelAll()` |
| `ClosedFailure` | `api.close()`-এর পরে call |
| `AuthFailure` | token refresh ব্যর্থ, ব্যবহারকারী sign out |
| `CircuitOpenFailure` | circuit breaker খোলা — host-কে আপাতত ডাকা হচ্ছে না |
| `RequestFailure` | request-টাই ভুল (যেমন GET-এ body) |

`switch` দিয়ে সব ধরন:

```dart
final text = switch (e) {
  HttpFailure(:final response) when response.statusCode == 422 =>
      'ফর্মে ভুল আছে',
  HttpFailure() => 'Server সমস্যা (${e.statusCode})',
  TimeoutFailure() || ConnectionFailure() => 'সংযোগ নেই',
  AuthFailure() => 'আবার login করুন',
  _ => e.message,
};
```

Server-এর error body পড়তে (যেমন validation message):

```dart
} on HttpFailure catch (e) {
  final body = jsonDecode(e.response.text) as Map<String, dynamic>;
  showMessage(body['message'] as String? ?? e.message);
}
```

### ৮.৩ `try/catch` ছাড়া — `Result`

```dart
final result = await api.get<User>('/users/10', decoder: User.fromJson).asResult();

switch (result) {
  case Ok(:final value):  show(value);
  case Err(:final error): showMessage(error.message);
}
```

Bloc-এ এটা বেশ পরিষ্কার দেখায়:

```dart
on<LoadMe>((event, emit) async {
  emit(const MeLoading());
  emit(switch (await repo.me().asResult()) {
    Ok(:final value) => MeLoaded(value),
    Err(:final error) => MeFailed(error.message),
  });
});
```

---

## ৯. Login, Token আর Refresh

### ৯.১ Login আর Logout

প্রতিটা client-এর ভিতরে একটা token manager আছে: `api.auth`। Login call-এর পরে token
একবার দিয়ে দিন — এরপর প্রতিটা request নিজে থেকেই `Authorization: Bearer …` পাঠাবে।

```dart
Future<void> login(String email, String password) async {
  final r = await api.post<Map<String, dynamic>>(
    '/auth/login',
    body: {'email': email, 'password': password},
    auth: false,                      // এই call-এ token লাগে না
  );
  await api.auth.login(Tokens(
    access: r['access_token'] as String,
    refresh: r['refresh_token'] as String?,
    expiresIn: Duration(seconds: r['expires_in'] as int),
  ));
}

api.auth.isLoggedIn;   // true
api.auth.state;        // AuthState.signedIn
api.auth.tokens;       // বর্তমান Tokens (print করলে মান দেখায় না)
await api.auth.logout(); // token আর cache মুছে, onLogout চালায়
```

### ৯.২ Token নিজে থেকে refresh

```dart
final api = OmniNetwork(
  baseUrl: url,
  auth: OmniAuth(
    refresh: (tokens, api) async {
      final r = await api.post<Map<String, dynamic>>(
        '/auth/refresh',
        body: {'refresh_token': tokens.refresh},
      );
      return Tokens(
        access: r['access_token'] as String,
        refresh: r['refresh_token'] as String?,
        expiresIn: Duration(seconds: r['expires_in'] as int),
      );
    },
    onLogout: () => OmniRoute.go('/login'),
    refreshBefore: const Duration(seconds: 30), // মেয়াদ শেষের কত আগে
    refreshTimeout: const Duration(seconds: 30),
  ),
);
```

`OmniAuth` যা দেখাশোনা করে:

- **মেয়াদ শেষের আগেই refresh।** `expiresIn`/`expiresAt` জানা থাকলে `refreshBefore`
  আগে refresh হয়, তাই ব্যবহারকারী সাধারণত 401 দেখেই না।
- **401 এলে refresh।** তারপর request একবার নতুন token দিয়ে আবার যায়।
- **একবারে একটাই refresh।** দশটা call একসাথে 401 পেলেও refresh একবার চলে, সবাই সেটার জন্য অপেক্ষা করে।
- **Refresh-এর ভিতরের call** নিজে থেকেই token ছাড়া যায় (loop হয় না)।
- **Refresh ব্যর্থ** (`null` ফেরত, exception, বা timeout): token মুছে যায়, `onLogout` একবার চলে,
  অপেক্ষমাণ call-গুলো `AuthFailure` পায় (`e.isUnauthorized == true`)।
- **`refresh` না দিলে** শুধু token রাখে আর পাঠায়; 401 তখন সাধারণ `HttpFailure`।

### ৯.৩ Login অবস্থা শোনা

```dart
api.auth.changes.listen((state) {
  // AuthState.signedIn / AuthState.signedOut
});
```

এটা দিয়ে OmniRoute guard নিজে থেকে আবার চলে ([২৪](#২৪-omniroute-এর-সাথে-পুরো-অ্যাপ))।

### ৯.৪ অ্যাপ বন্ধ করে খুললেও login থাকবে

```dart
import 'package:omni_network_flutter/omni_network_flutter.dart';

auth: OmniAuth(
  storage: SecureTokenStorage(),   // Keychain / Keystore
  refresh: ...,
),
```

অ্যাপ শুরুতে login আছে কি না জানতে (splash screen-এ):

```dart
final loggedIn = await api.auth.restore(); // storage থেকে token পড়ে
OmniRoute.go(loggedIn ? '/home' : '/login');
```

নিজের storage লাগলে `TokenStorage` implement করুন (`advanced.dart`); `Tokens.toJson()` /
`Tokens.fromJson()` আছে।

### ৯.৫ Token আগে থেকেই অন্য কোথাও আছে

```dart
final api = OmniNetwork(baseUrl: url, token: () => mySession.accessToken);
```

এতে refresh হয় না, আর `api.auth` ব্যবহার করা যায় না (`StateError`)।
পুরো নিজের মতো নিয়ন্ত্রণ চাইলে `BearerAuth` (`advanced.dart`)।

---

## ১০. Interceptor

প্রতিটা request বা response-এ নিজের কাজ করতে:

```dart
final class AppHeaders extends OmniInterceptor {
  AppHeaders(this.version);
  final String version;

  @override
  OmniRequest onRequest(OmniRequest r) =>
      r.withHeader('X-App-Version', version);

  @override
  OmniRawResponse onResponse(OmniRequest r, OmniRawResponse res) {
    if (res.headers['x-app-update'] == 'required') showUpdateDialog();
    return res;
  }

  @override
  void onError(OmniRequest r, OmniNetworkException e) {
    analytics.log('api_error', {'path': r.path, 'status': e.statusCode});
  }
}

final api = OmniNetwork(baseUrl: url, interceptors: [AppHeaders('1.4.0')]);
```

- তিনটা method-ই ঐচ্ছিক; `async` হতে পারে।
- `onError`-এ `e.message` নিরাপদ, কিন্তু নিজে header/body log করলে secret বেরিয়ে যেতে পারে — সেটা করবেন না।
- Token যোগ করতে interceptor লাগে না — `OmniAuth` নিজেই করে।

---

## ১১. Terminal Log

### ১১.১ চালু করা

```dart
final api = OmniNetwork(baseUrl: url, enableLogging: true);
```

প্রতিটা call একটা পরিষ্কার block হিসেবে [`logger`](https://pub.dev/packages/logger)
package দিয়ে ছাপা হয় — OmniRoute-এর navigation log-এর মতোই দেখতে:

```
┌───────────────────────────────────────────────────────────
│ 2026-11-17 15:35:30.519
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ 💡 GET  https://api.example.com/v1/users/10
│ 💡 ✔ 200 OK · 3 ms · 43 B
│ 💡 {
│ 💡   "id": 10,
│ 💡   "name": "Rahim",
│ 💡   "access_token": "***"
│ 💡 }
└───────────────────────────────────────────────────────────
┌───────────────────────────────────────────────────────────
│ 2026-11-17 15:35:30.526
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ ⚠️ POST https://api.example.com/v1/orders
│ ⚠️ ⇢ body
│ ⚠️   {
│ ⚠️     "qty": 0
│ ⚠️   }
│ ⚠️ ✖ 422 Unprocessable Entity · 0 ms · 15 B
│ ⚠️ {
│ ⚠️   "error": "qty"
│ ⚠️ }
└───────────────────────────────────────────────────────────
```

কীভাবে পড়বেন:

| চিহ্ন | মানে |
|---|---|
| 💡 | সফল (2xx/3xx) |
| ⚠️ | 4xx — আপনার পাঠানো request-এ সমস্যা |
| ⛔ | 5xx বা কোনো উত্তরই আসেনি (timeout, network নেই) |
| `⇢ body` / `⇢ headers` | যা পাঠানো হয়েছে |
| `⇠ headers` | যা এসেছে |
| `↻ retry 2/3` | আবার চেষ্টা |
| `🔑 token refreshed` | token refresh হয়েছে |
| `· cache` | cache থেকে এসেছে |
| `↪` | আগের লাইনেরই বাকি অংশ (লম্বা লাইন ভেঙে পরের লাইনে) |
| `2026-11-17 15:35:30.519` | log-এর তারিখ আর সময় |
| `84 ms` / `1.24 s` / `2 min 05 s` | call-এ কত সময় লেগেছে |

- **পুরো response ছাপা হয়।** body যত বড়ই হোক, কোনো লাইন বাদ যায় না, অর্ধেক কাটা হয় না।
  ১৬০ অক্ষরের বেশি লম্বা লাইন `↪` দিয়ে পরের লাইনে চলে যায় — কারণ Android আর iOS
  একটা log লাইন প্রায় ১০০০ byte-এর বেশি হলে বাকিটা ফেলে দেয়।
- শুধু binary body (ছবি, ফাইল) আর ভাঙা JSON (যেটা redact করা যায় না) size দিয়ে দেখানো হয়।
- Request আর response একসাথে এক block-এ, তাই একসাথে অনেক call চললেও log মিশে যায় না।
- JSON সুন্দরভাবে indent করা — request body-ও।
- **রং:** সফল call সবুজ, JSON-এর key, string, number, `true/false/null` আলাদা রঙে;
  4xx, 5xx আর ব্যর্থ call পুরোটা লাল।
  Android-এ (`flutter run`, VS Code, Android Studio) আর রং-সমর্থিত terminal-এ নিজে থেকে চালু।
  **iOS-এর log রং দেখাতে পারে না** (রং-এর code `\^[` লেখা হয়ে যায়), তাই iOS-এ রং বন্ধ থাকে —
  তখন emoji (💡 ⚠️ ⛔) আর `✔`/`✖` দিয়ে বোঝা যায়।

### ১১.২ Secret কখনো log-এ যায় না

সবসময় `***` হয়ে যায় — বন্ধ করার কোনো উপায় নেই:

- `Authorization`, `Cookie`, `Set-Cookie`, API-key জাতীয় header;
- `password`, `token`, `access_token`, `refresh_token`, `secret`, `api_key` জাতীয় JSON field;
- query-র মান (`?api_key=***`) আর URL-এর user info।

নিজের field যোগ করতে (`advanced.dart`):

```dart
OmniNetwork(
  baseUrl: url,
  enableLogging: true,
  redactor: const Redactor(
    extraKeys: {'nid', 'card_number'},
    extraHeaders: {'x-device-secret'},
  ),
);
```

### ১১.৩ Release build

`enableLogging: true` থাকলেও release build-এ log বন্ধ থাকে। `api.isLogging` দিয়ে দেখা যায়।
`logInRelease: true` দিলে release-এও চলে — তবে সাধারণত এটা করবেন না।

### ১১.৪ কতটুকু দেখাবে

```dart
OmniNetwork(
  baseUrl: url,
  enableLogging: true,
  logOptions: const LogOptions(
    headers: true,       // default false
    requestBody: true,   // default true
    responseBody: true,  // default true
    maxLines: null,      // default null = সব লাইন; সংখ্যা দিলে "… N more lines" দিয়ে কাটে
    maxLineLength: 160,  // এর চেয়ে লম্বা লাইন "↪" দিয়ে পরের লাইনে চলে যায়
    colors: null,        // null = আপনা থেকে (Android/terminal: চালু, iOS: বন্ধ)
  ),
);
```

### ১১.৫ নিজের Logger বা অন্য কোথাও পাঠানো

```dart
import 'package:logger/logger.dart';
import 'package:omni_network/advanced.dart';

OmniNetwork(
  baseUrl: url,
  enableLogging: true,
  logSink: PrettyLogSink(logger: Logger(printer: SimplePrinter())),
);

// পুরনো ধাঁচের নিজস্ব frame, একবারে একটা print:
logSink: PrettyLogSink(printer: print),
```

ফাইল, crash reporter বা অন্য কিছুতে পাঠাতে নিজের `LogSink` লিখুন। Sink যে record পায়
সেটা আগেই redact করা থাকে।

---

## ১২. Retry আর Circuit Breaker

### ১২.১ Retry

Default-এ বন্ধ। চালু করুন:

```dart
final api = OmniNetwork(baseUrl: url, retry: const RetryPolicy());
```

| Option | Default | মানে |
|---|---|---|
| `maxAttempts` | `3` | প্রথম চেষ্টা সহ মোট |
| `baseDelay` / `maxDelay` / `multiplier` | 300 ms / 10 s / 2 | অপেক্ষা ধাপে ধাপে বাড়ে |
| `jitter` | `true` | সবাই একই মুহূর্তে আবার চেষ্টা না করে |
| `methods` | `{GET, HEAD}` | কোন method retry হবে |
| `statuses` | `{408, 429, 500, 502, 503, 504}` | কোন status-এ retry |
| `retryOnTimeout` / `retryOnConnectionError` | `true` / `true` | |
| `respectRetryAfter` / `maxRetryAfter` | `true` / 60 s | server-এর `Retry-After` মানে; বেশি হলে অপেক্ষা না করে response ফেরত |
| `retryWithIdempotencyKey` | `false` | POST/PATCH retry — শুধু `Idempotency-Key` header থাকলে |

**কেন POST নিজে থেকে retry হয় না?** একটা payment POST দুবার গেলে দুবার টাকা কাটতে পারে।
POST retry চাইলে দুটোই লাগবে:

```dart
await api.post<Order>('/orders',
    body: order.toJson(),
    decoder: Order.fromJson,
    headers: {'Idempotency-Key': order.clientId},
    retry: const RetryPolicy(
      methods: {HttpMethod.post},
      retryWithIdempotencyKey: true,
    ));
```

শুধু একটা call-এ retry বন্ধ: `retry: RetryPolicy.none`।

### ১২.২ Circuit Breaker

একটা host বারবার ব্যর্থ হলে কিছুক্ষণ তাকে ডাকাই বন্ধ, যাতে অ্যাপ অযথা অপেক্ষা না করে
(`advanced.dart`):

```dart
final api = OmniNetwork(
  baseUrl: url,
  circuitBreaker: CircuitBreaker(
    failureThreshold: 5,                     // পরপর ৫ ব্যর্থতায় খোলে
    openDuration: const Duration(seconds: 30), // ৩০ সেকেন্ড বন্ধ
  ),
);
```

খোলা থাকলে call সাথে সাথে `CircuitOpenFailure` পায়।

---

## ১৩. Cache আর De-duplication

### ১৩.১ Cache চালু

```dart
final api = OmniNetwork(baseUrl: url, cache: OmniCache());
```

এরপর GET-গুলো HTTP-র নিয়ম (RFC 9111) মেনে cache হয়: `Cache-Control: max-age`, `Expires`,
`no-store`, `no-cache`, `Vary`, আর `ETag`/`Last-Modified` দিয়ে যাচাই (`304` এলে cache-এর body)।

প্রতিটা call-এ নিয়ম বদলানো:

```dart
api.get<List<dynamic>>('/feed', cache: CachePolicy.staleWhileRevalidate);
```

| Policy | কী করে | কখন ভালো |
|---|---|---|
| `standard` | HTTP নিয়ম মেনে | default |
| `cacheFirst` | cache থাকলে সেটাই (পুরনো হলেও) | প্রায় না-বদলানো data (দেশের তালিকা) |
| `staleWhileRevalidate` | সাথে সাথে cache দেখায়, পেছনে নতুন আনে | feed, dashboard |
| `networkFirst` | network; না পেলে cache | offline-এ পুরনো data দেখানো |
| `refresh` | সবসময় network, নতুনটা রাখে | pull-to-refresh |
| `noCache` | cache ছোঁয় না | সবসময় তাজা |

### ১৩.২ নিয়ম

- POST/PUT/PATCH/DELETE সফল হলে সেই URL-এর cache নিজে থেকে মুছে যায়।
- **Login করা request** (`Authorization` আছে) default-এ cache হয় **না**। চাইলে:

  ```dart
  OmniCache(
    cacheAuthenticated: true,
    authScope: () => currentUserId, // প্রতিটা ব্যবহারকারীর cache আলাদা
  );
  ```

  `api.auth.logout()` cache মুছে দেয়।
- `maxEntryBytes` (default 2 MB) এর বড় response cache হয় না।
- হাতে মোছা: `await cache.clear()`, `await cache.invalidate(url)`।
- Default store memory-তে; disk-এ রাখতে `CacheStore` implement করে `OmniCache(store: ...)`।
- কোথা থেকে এল: `res.source` → `network`, `cache`, `revalidated`।

### ১৩.৩ De-duplication

একই মুহূর্তে একই GET (একই URL আর header) একাধিকবার হলে network-এ একবারই যায়, সবাই একই
উত্তর পায়। প্রত্যেকের নিজের timeout আর cancel আলাদা থাকে। বন্ধ: `deduplicate: false`।

---

## ১৪. Request বাতিল

```dart
final token = OmniCancelToken();
api.get<User>('/slow', decoder: User.fromJson, cancelToken: token);
token.cancel();                 // সেই call CancelledFailure পায়
```

Screen ছেড়ে গেলে তার সব call বাতিল — parent/child token:

```dart
class _ProfileState extends State<ProfilePage> {
  final _cancel = OmniCancelToken();

  @override
  void initState() {
    super.initState();
    api.get<User>('/me', decoder: User.fromJson, cancelToken: _cancel.child());
  }

  @override
  void dispose() {
    _cancel.cancel(); // সব child-ও বাতিল
    super.dispose();
  }
}
```

- `api.cancelAll()` — চলমান সব বাতিল, client চালু থাকে (যেমন logout-এর সময়)।
- `api.close()` — সব বাতিল, client বন্ধ; এরপর call করলে `ClosedFailure`।
- বাতিল হওয়া error `e.isCancelled` — সাধারণত ব্যবহারকারীকে দেখানোর দরকার নেই।

---

## ১৫. Upload আর Download

### ১৫.১ Upload (multipart)

```dart
await api.upload<void>('/me/avatar',
  fields: {'album': 'profile'},
  files: [
    UploadFile.fromBytes('file', bytes,
        filename: 'me.png', contentType: 'image/png'),
  ],
  onProgress: (sent, total) => setProgress(sent / total),
);
```

বড় ফাইল memory-তে না এনে (mobile/desktop):

```dart
final f = File(path);
UploadFile.fromStream('file', f.openRead,
    length: f.lengthSync(), filename: 'video.mp4', contentType: 'video/mp4');
```

`method: HttpMethod.put`, `decoder:`, `query:`, `headers:`, `cancelToken:` সবই দেওয়া যায়।

### ১৫.২ Download

```dart
// memory-তে (সব platform, Web সহ)
final Uint8List pdf = await api.downloadBytes('/reports/1.pdf',
    onProgress: (got, total) => setProgress(got / total));

// সরাসরি ফাইলে (Android, iOS, macOS, Windows, Linux)
if (OmniNetwork.supportsFileDownload) {
  await api.downloadToFile('/files/big.zip', '${dir.path}/big.zip',
      resume: true, cancelToken: token);
}
```

- **`.part` ফাইল।** প্রথমে `<file>.part`-এ লেখে, শেষ হলে নাম বদলায় — অর্ধেক ফাইল কখনো আসল নামে থাকে না।
- **Resume।** `resume: true` দিলে আগের `.part` থেকে HTTP `Range` দিয়ে চালিয়ে যায়
  (server `206` দিলে; `200` দিলে শুরু থেকে)।
- **Timeout।** Transfer-এ মোট সময়সীমা নেই (চাইলে `timeout:`); তবে `idleTimeout` সময় কোনো
  progress না হলে ব্যর্থ হয়।
- Upload/download কখনো নিজে থেকে retry হয় না।
- অ্যাপ background-এ গেলে transfer চলতে থাকার নিশ্চয়তা নেই।

---

## ১৬. Pagination — infinite scroll

```dart
final pager = api.paginate<User>('/users',
    decoder: User.fromJson,
    strategy: const PagePagination(pageSize: 20));

await pager.next();             // প্রথম পাতা
if (pager.hasMore) await pager.next();

pager.items;        // এ পর্যন্ত সব item
pager.isLoading;    // পাতা আসছে কি না
pager.pageCount;    // কত পাতা এসেছে
pager.lastError;    // শেষ ব্যর্থতা (সফল হলে null)
await pager.refresh();  // শুরু থেকে আবার
await pager.close();
```

Backend অনুযায়ী strategy:

| Strategy | Backend যা চায় | উদাহরণ |
|---|---|---|
| `PagePagination(pageParam: 'page', sizeParam: 'limit', pageSize: 20, firstPage: 1)` | `?page=2&limit=20` | `totalPagesKey:` / `hasMoreKey:` দিলে শেষ বোঝে |
| `OffsetPagination(offsetParam: 'offset', limitParam: 'limit', limit: 20)` | `?offset=40&limit=20` | `totalKey:` |
| `CursorPagination(nextCursorKey: 'meta.next')` | `?cursor=abc` | পরের cursor JSON-এর যেকোনো path থেকে |
| `LinkHeaderPagination()` (`advanced.dart`) | `Link: <...>; rel="next"` header | GitHub-ধাঁচ |

Item যদি JSON-এর ভিতরে থাকে (`{"items": [...], "total": 90}`): `itemsKey: 'items'`।

UI থেকে নিশ্চিন্তে ডাকা যায়:

- পাতা আসার সময় আবার `next()` ডাকলে একই future ফেরত (দুবার request যায় না);
- ব্যর্থ হলে আবার `next()` ডাকলেই সেই পাতা আবার চেষ্টা;
- server একই cursor আবার দিলে paging থামে (অসীম loop নয়);
- `LinkHeaderPagination` অন্য domain-এর link মানে না, তাই token বাইরে যায় না।

Flutter-এ:

```dart
ListView.builder(
  itemCount: pager.items.length + (pager.hasMore ? 1 : 0),
  itemBuilder: (context, i) {
    if (i == pager.items.length) {
      pager.next().then((_) => setState(() {}));
      return const Center(child: CircularProgressIndicator());
    }
    return UserTile(pager.items[i]);
  },
);
```

---

## ১৭. UI-তে Loading / Data / Error

`api.watch` একটা `RequestController` দেয় — এর `stream` অবস্থা বদলালেই নতুন মান পাঠায়:

```dart
final me = api.watch<User>('/me', decoder: User.fromJson); // নিজে থেকে load শুরু

StreamBuilder<RequestState<User>>(
  stream: me.stream,
  builder: (context, snap) => switch (snap.data) {
    null || RequestIdle() || RequestLoading(previous: null) =>
        const CircularProgressIndicator(),
    RequestLoading(:final previous?) => UserCard(previous, refreshing: true),
    RequestSuccess(:final data) => UserCard(data),
    RequestEmpty() => const Text('কিছু নেই'),
    RequestError(:final networkError) => RetryView(
        message: networkError?.message ?? 'কিছু ভুল হয়েছে',
        onRetry: me.refresh),
  },
);

await me.refresh(); // আবার আনা; পুরনো data previous-এ থাকে
await me.close();   // dispose-এ
```

| State | মানে |
|---|---|
| `RequestIdle` | এখনো শুরু হয়নি (`autoLoad: false`) |
| `RequestLoading(previous:)` | আনা চলছে; আগের data থাকলে `previous`-এ |
| `RequestSuccess(data:)` | এসেছে |
| `RequestEmpty` | এসেছে কিন্তু খালি (`null`, খালি list/map/string; নিজের নিয়ম `isEmpty:`) |
| `RequestError(error:, previous:)` | ব্যর্থ; `networkError` = `OmniNetworkException` (অন্য error হলে `null`), আগের data `previous`-এ |

- তালিকার জন্য `api.watchList<User>('/users', decoder: User.fromJson)`।
- `refresh()` চলাকালীন আগেরটা বাতিল হয় — পুরনো উত্তর কখনো নতুনকে ঢেকে দেয় না।
- নিজের যেকোনো async কাজেও: `RequestController((token) => repo.me(cancelToken: token))`।
- এটা plain Dart — `StreamBuilder`, Bloc, Riverpod সবকিছুর সাথে চলে।

---

## ১৮. Endpoint আর OpenAPI

### ১৮.১ Endpoint — একবার লিখুন

```dart
abstract final class UserApi {
  static final byId = Endpoint.get<User>('/users/{id}', decoder: User.fromJson);
  static final list = Endpoint.getList<User>('/users', decoder: User.fromJson);
  static final create = Endpoint.post<User>('/users', decoder: User.fromJson);
  static final remove = Endpoint.delete<void>('/users/{id}');
}

final u = await api.call(UserApi.byId, path: {'id': 10});
final all = await api.call(UserApi.list, query: {'page': 2});
await api.call(UserApi.create, body: {'name': 'Ana'});
```

Endpoint-এ `cachePolicy:`, `retry:`, `headers:`, `name:`, `description:`, `tags:` রাখা যায়;
`api.callResponse(...)` দিয়ে পুরো response।

### ১৮.২ OpenAPI spec থেকে সব তৈরি

Backend-এর `openapi.yaml`/`.json` থাকলে model আর endpoint হাতে লিখতে হয় না:

```sh
dart run omni_network_openapi -i openapi.yaml -o lib/data/api.g.dart --name ShopApi
```

```dart
import 'data/api.g.dart';

final pets = await api.call(ShopApi.listPets, query: {'limit': 10});
await api.call(ShopApi.createPet, body: const NewPet(name: 'Rex').toJson());
```

যা পারে না (stderr-এ `warning:` দেখায়, চুপচাপ বাদ দেয় না): Swagger 2, অন্য ফাইলের `$ref`,
multipart body (`api.upload` ব্যবহার করুন), cookie parameter।
বিস্তারিত: [omni_network_openapi](../../omni_network_openapi/README.md)।

---

## ১৯. Offline Queue

Network না থাকলে request জমিয়ে রেখে পরে পাঠানো (`advanced.dart`)। **কিছুই নিজে থেকে জমা
হয় না** — আপনাকে স্পষ্ট করে বলতে হয়।

```dart
final queue = OfflineQueue(client: api, maxAttempts: 5);

final result = await queue.sendOrQueue(
  const OmniRequest.post('/notes', body: {'text': 'হ্যালো'}),
);
switch (result) {
  case SentNow(:final response): showSaved(response);
  case Queued(:final item): showMessage('Online হলে পাঠানো হবে');
}

queue.attach(connectivityStream);  // Stream<bool>; online হলেই flush
queue.events.listen((e) => print(e.kind)); // enqueued / sent / rejected / deferred / deadLettered
await queue.flush();               // হাতে পাঠানো
```

নিয়ম:

- `sendOrQueue` শুধু তখনই জমায় যখন server-এ পৌঁছানোই যায়নি; server উত্তর দিলে (৪২২ ইত্যাদি)
  জমায় না, ফলাফল ফেরত দেয়।
- GET, HEAD আর multipart কখনো জমা হয় না।
- **PUT, PATCH, DELETE** জমাতে `allowDestructive: true` লাগে — ভুল করে পরে কিছু মুছে
  যাওয়া ঠেকাতে।
- প্রতিটা item-এ একটা `Idempotency-Key` থাকে, প্রতিবার একই key যায় — backend চাইলে duplicate ধরতে পারে।
- `Authorization` আর `Cookie` কখনো store হয় না; পাঠানোর সময় তখনকার token যোগ হয়।
- `flush()` পুরনোটা আগে পাঠায়, প্রথম অস্থায়ী ব্যর্থতায় থামে (ক্রম ঠিক থাকে)।
- অ্যাপ বন্ধ হলেও রাখতে `QueueStore` implement করুন (`QueuedRequest.toJson()` সংরক্ষণ করুন)।
- `await queue.pending` — এখনো যা বাকি; `queue.discard(id)` — একটা বাদ দেওয়া।

---

## ২০. Low-level: sendRaw, stream, cURL

`advanced.dart` থেকে:

```dart
// যেকোনো status ফেরত, কোনো decode বা HttpFailure নয়
final raw = await api.sendRaw(const OmniRequest.get('/health'));
print('${raw.statusCode} ${raw.text}');

// নিজে OmniRequest বানিয়ে typed পাঠানো
final res = await api.send<User>(
    const OmniRequest.get('/me'), decoder: User.fromJson);

// streaming body (auth, interceptor, log সব প্রযোজ্য)
final stream = await api.openStream(const OmniRequest.get('/events'));

// cURL — secret default-এ লুকানো
print(api.toCurl(const OmniRequest.get('/users')));
final imported = parseCurl(copiedFromBrowser).request; // browser থেকে copy করা cURL
```

---

## ২১. Test — OmniMock

Backend বা internet ছাড়াই পুরো network layer test করুন (`testing.dart`):

```dart
import 'package:omni_network/omni_network.dart';
import 'package:omni_network/testing.dart';
import 'package:test/test.dart';

void main() {
  late OmniMock mock;
  late OmniNetwork api;

  setUp(() {
    mock = OmniMock(basePath: '/v1')
      ..get('/users/{id}', (r) => MockResponse.json(
          {'id': int.parse(r.pathParams['id']!), 'name': 'Ana'}))
      ..post('/users', (r) => MockResponse.json(r.json, status: 201))
      ..get('/feed', OmniMock.sequence([
          const MockResponse.offline(),   // প্রথমবার network নেই
          MockResponse.json([]),          // পরেরবার খালি তালিকা
        ]));
    api = OmniNetwork(baseUrl: 'https://api.test/v1', transport: mock);
  });

  tearDown(() => api.close());

  test('user আনে', () async {
    final u = await api.get<User>('/users/7', decoder: User.fromJson);
    expect(u.id, 7);
    expect(mock.callsTo(HttpMethod.get, '/users/{id}'), hasLength(1));
  });

  test('network না থাকলে isOffline', () async {
    final r = await api.get<List<dynamic>>('/feed').asResult();
    expect(r, isA<Err<List<dynamic>>>());
    expect((r as Err).error.isOffline, isTrue);
  });
}
```

| সুবিধা | কীভাবে |
|---|---|
| route | `get`, `post`, `put`, `patch`, `delete`, `any`, `endpoint(UserApi.byId, ...)` |
| path parameter | `'/users/{id}'` → `r.pathParams['id']` |
| request body | `r.json`, `r.text` |
| response | `MockResponse.json(...)`, `.text`, `.bytes`, `.status(503)`, `.error(...)`, `.offline()`, `.hang()` (timeout test) |
| ক্রমানুসারে ভিন্ন উত্তর | `OmniMock.sequence([...])` |
| পরিস্থিতি | `scenario('down', (s) => s.any((_) => const MockResponse.status(503)))` + `mock.use('down')` |
| পরের N টা ব্যর্থ | `mock.failNext(2)` |
| ধীর network | `OmniMock(latency: ...)`, `MockResponse.json(..., delay: ...)` |
| এলোমেলো ব্যর্থতা | `OmniMock(failureRate: 0.2, random: Random(1))` |
| কী ডাকা হলো | `mock.callsTo(method, template)`, `mock.resetCalls()` |

OmniMock **strict**: কোনো route না মিললে সেই request-এর নাম সহ ব্যর্থ হয়, তাই ভুল URL চোখে পড়ে।
Upload/download-ও সমর্থন করে।

> এই repo-তে `dart test` Dart 3.13-এ runner crash করে; প্রতিটা ফাইল
> `dart run test/<file>_test.dart` দিয়ে চালান। আপনার নিজের অ্যাপে `flutter test` স্বাভাবিকভাবে চলে।

---

## ২২. Flutter: Secure storage আর Inspector

`omni_network_flutter` থেকে।

### ২২.১ `SecureTokenStorage`

```dart
auth: OmniAuth(
  storage: SecureTokenStorage(),          // key: 'omni_network.tokens'
  refresh: ...,
),
```

| Platform | কোথায় থাকে |
|---|---|
| iOS / macOS | Keychain (macOS-এ Keychain Sharing entitlement লাগে) |
| Android | Keystore দিয়ে encrypt করা storage |
| Windows / Linux | Credential Manager / libsecret |
| Web | WebCrypto দিয়ে encrypt করা `localStorage` — browser পুরো সুরক্ষা দিতে পারে না, তাই access token স্বল্পমেয়াদি রাখুন |

- নষ্ট data মুছে signed out ধরা হয় — অ্যাপ আটকে যায় না।
- Platform error অ্যাপ crash করে না; `onError`-এ যায় (default শুধু error type ছাপে, token নয়)।
- একাধিক client: প্রতিটার আলাদা `key:`।

### ২২.২ অ্যাপের ভিতরে Network Inspector

```dart
final inspector = OmniInspector();        // release build-এ নিজে থেকে বন্ধ

final api = OmniNetwork(
  baseUrl: url,
  enableLogging: inspector.enabled,
  logSink: inspector.sink('api'),         // প্রতিটা client-এর একটা label
);

MaterialApp(
  builder: (context, child) =>
      OmniInspectorLauncher(inspector: inspector, child: child!),
);
```

ছোট একটা ভাসমান বোতাম আসে; চাপলে সব call-এর তালিকা, filter, header/body, আর
"Copy as cURL"। শুধু redact করা data পায়, তাই token clipboard-এ যায় না।
`maxEntries` (default ৩০০) পর্যন্ত রাখে। Terminal-এও চাইলে: `OmniInspector(forwardTo: PrettyLogSink())`।

> OmniRoute ব্যবহার করলে `OmniApp(builder: (_, r) => MaterialApp.router(routerConfig: r, builder: ...))`-এর
> `builder`-এ `OmniInspectorLauncher` বসান।

---

## ২৩. Live data: WebSocket আর SSE

`omni_network_ws` থেকে।

### Server-Sent Events

```dart
final sse = SseConnection(api, '/events');     // api-র auth, interceptor, log সবই চলে
sse.events.listen((e) => print('${e.event}: ${e.data}'));
sse.states.listen(print);                      // connecting / open / waiting / closed
await sse.close();
```

সংযোগ ছিঁড়লে নিজে থেকে আবার যুক্ত হয়, `Last-Event-ID` পাঠায় যাতে server যেখানে ছিল সেখান থেকে দেয়।
`204`, ৪০৮/৪২৯ ছাড়া অন্য 4xx, বা `maxReconnects` পার হলে থামে।

### WebSocket

```dart
final ws = OmniWebSocket(
  Uri.parse('wss://api.example.com/live'),
  headers: () async => {'authorization': 'Bearer ${api.auth.tokens?.access}'},
  onOpen: (s) => s.sendJson({'subscribe': 'prices'}),
);
ws.jsonMessages.listen(print);
await ws.close();
```

- Error বা অস্বাভাবিক বন্ধে backoff দিয়ে আবার যুক্ত হয়; স্বাভাবিক বন্ধ (`1000`) বা `close()`-এর পরে নয়।
- `headers` প্রতিটা সংযোগে চলে, তাই refresh করা token যায়। Browser handshake header দিতে দেয় না
  (`OmniWebSocket.supportsHandshakeHeaders`) — Web-এ token query/প্রথম message-এ পাঠানোর নিয়ম backend-এর সাথে ঠিক করুন।
- বিচ্ছিন্ন অবস্থায় `send` exception দেয় — চুপচাপ জমায় না। জমাতে চাইলে
  `bufferWhileDisconnected: true` (সর্বোচ্চ `maxBuffered`)।

---

## ২৪. OmniRoute-এর সাথে পুরো অ্যাপ

Login অবস্থা বদলালেই route guard নিজে থেকে আবার চলে, token refresh ব্যর্থ হলে login পাতায় যায়:

```dart
import 'package:flutter/material.dart';
import 'package:omni_network/omni_network.dart';
import 'package:omni_network_flutter/omni_network_flutter.dart';
import 'package:omni_route/omni_route.dart';

final inspector = OmniInspector();

final api = OmniNetwork(
  baseUrl: 'https://api.example.com/v1',
  enableLogging: inspector.enabled,
  logSink: inspector.sink('api'),
  retry: const RetryPolicy(),
  auth: OmniAuth(
    storage: SecureTokenStorage(),
    refresh: (tokens, api) async {
      final r = await api.post<Map<String, dynamic>>('/auth/refresh',
          body: {'refresh_token': tokens.refresh});
      return Tokens(
        access: r['access_token'] as String,
        refresh: r['refresh_token'] as String?,
        expiresIn: Duration(seconds: r['expires_in'] as int),
      );
    },
    // guard নিজেই /login-এ পাঠাবে (auth.changes শুনে), তাই এখানে কিছু লাগে না
  ),
);

/// UI-র সুবিধার জন্য guard — আসল নিরাপত্তা backend-এ।
final authGuard = OmniGuard.fn(
  (context, state) {
    final atLogin = state.matchedLocation == '/login';
    if (!api.auth.isLoggedIn && !atLogin) return '/login';
    if (api.auth.isLoggedIn && atLogin) return '/';
    return null;
  },
  refresh: (_) => api.auth.changes,     // login/logout হলেই guard আবার চলে
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.auth.restore();             // আগের login থাকলে storage থেকে আনে
  runApp(const ShopApp());
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) => OmniApp(
    guards: [authGuard],
    routes: [
      OmniPage('/login', (_) => const LoginScreen()),
      OmniPage('/', (_) => const HomeScreen()),
    ],
    builder: (_, router) => MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          OmniInspectorLauncher(inspector: inspector, child: child!),
    ),
  );
}
```

Login screen-এর Bloc শুধু `api.auth.login(...)` ডাকবে; route বদলানোর কাজ guard নিজে করবে।

---

## ২৫. নিরাপত্তা

Default-গুলো নিরাপদ দিকে রাখা:

| বিষয় | Default |
|---|---|
| Log | বন্ধ; চালু থাকলেও secret সবসময় `***`; release build-এ বন্ধ |
| Error message | কখনো body, header, query বা URL user info থাকে না — UI-তে দেখানো নিরাপদ |
| Retry | বন্ধ; চালু হলেও শুধু GET/HEAD |
| POST/PATCH retry | শুধু `Idempotency-Key` + স্পষ্ট অনুমতি |
| Offline queue | কিছুই নিজে থেকে জমে না; PUT/PATCH/DELETE-এ অনুমতি লাগে; token store হয় না |
| Cache | বন্ধ; login করা response cache হয় না (অনুমতি ছাড়া) |
| Redirect | অন্য domain-এ গেলে `Authorization`/`Cookie` বাদ; HTTPS → HTTP প্রত্যাখ্যান |
| Link pagination | শুধু একই origin |
| TLS | certificate যাচাই কখনো বন্ধ করা হয় না |

আপনার দিক থেকে যা করবেন:

- **Certificate validation বন্ধ করবেন না** — self-signed dev server-এর জন্যও না;
  এর বদলে dev certificate device-এ trust করান।
- **Client-এর route guard backend authorization-এর বিকল্প নয়।** Guard শুধু UI ঠিক রাখে;
  প্রতিটা API-কে server-এ নিজে অনুমতি যাচাই করতে হবে।
- Interceptor বা `onError`-এ নিজে header/body/token log করবেন না।
- নিজের secret field থাকলে `Redactor(extraKeys: {...})`-এ যোগ করুন।
- Access token স্বল্পমেয়াদি রাখুন, বিশেষ করে Web-এ।
- অর্থ/অর্ডার জাতীয় POST-এ `Idempotency-Key` দিন।

---

## ২৬. Platform

| | Android | iOS | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| HTTP, auth, retry, cache, queue | ✅ | ✅ | ✅¹ | ✅ | ✅ | ✅² |
| Upload/download progress | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `downloadToFile` / resume | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ `downloadBytes` ব্যবহার করুন |
| বড় JSON আলাদা isolate-এ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ (main thread-এ) |
| অ্যাপ suspend অবস্থায় transfer | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

1. macOS অ্যাপে `com.apple.security.network.client` entitlement লাগে
   (`macos/Runner/DebugProfile.entitlements` আর `Release.entitlements`)।
2. Web-এ server-কে CORS header দিতে হবে। Browser কিছু header দিতে দেয় না
   (`Cookie`, `User-Agent` ইত্যাদি)।

Android emulator থেকে নিজের কম্পিউটারের server: `http://10.0.2.2:<port>`; iOS simulator থেকে
`http://localhost:<port>`। Plain HTTP দিতে Android-এ `usesCleartextTraffic` আর iOS-এ ATS
exception লাগবে — শুধু debug build-এ রাখুন।

---

## ২৭. সমস্যা ও সমাধান (FAQ)

**Terminal-এ কোনো log আসছে না।**
`enableLogging: true` দিয়েছেন? Release/profile build-এ চলছে কি না দেখুন (`api.isLogging`)।
নিজে `logSink` দিলে সেটা কোথায় লিখছে দেখুন।

**iOS console-এ `\^[[32m` জাতীয় লেখা দেখাচ্ছে।**
নিজে `LogOptions(colors: true)` দিয়েছেন — iOS-এর log রং দেখাতে পারে না। `colors` না দিলে (null) iOS-এ রং নিজে থেকেই বন্ধ থাকে।

**Android-এ রং নেই।**
`flutter run` terminal, VS Code বা Android Studio-তে দেখুন; `adb logcat` সরাসরি খুললে কিছু viewer রং দেখায় না।
`colors: false` দেওয়া থাকলে সরিয়ে দিন।

**`DecodeFailure` হচ্ছে।**
Server-এর JSON আর `fromJson` মিলছে না (যেমন `id` string আসছে কিন্তু `as int`)। Log-এ body দেখুন;
খোলসে মোড়া হলে `EnvelopeResponseAdapter` দিন।

**সব call 401, refresh হচ্ছে না।**
`OmniAuth(refresh: ...)` দিয়েছেন? `token:` দিলে refresh হয় না। Refresh call নিজে 401 দিলে
ব্যবহারকারী sign out হয় — এটা ইচ্ছাকৃত।

**`StateError: api.auth is only available with OmniAuth`।**
Client `token:` বা `BearerAuth` দিয়ে বানানো। `auth: OmniAuth(...)` ব্যবহার করুন।

**POST retry হচ্ছে না।**
ইচ্ছাকৃত — [১২.১](#১২১-retry) দেখুন।

**Cache কাজ করছে না।**
Client-এ `cache: OmniCache()` দিয়েছেন? Server `Cache-Control: no-store` পাঠাচ্ছে কি না দেখুন।
Login করা request cache হয় না যতক্ষণ না `cacheAuthenticated: true`।

**Web-এ `ConnectionFailure`, কিন্তু Postman-এ চলে।**
প্রায় সবসময় CORS। Browser devtools-এর console দেখুন; server-এ CORS header যোগ করুন।

**macOS-এ সব call `ConnectionFailure`।**
`com.apple.security.network.client` entitlement নেই।

**Download থেমে গেল, আবার শুরু থেকে হচ্ছে।**
`resume: true` দিন। Server `Range` সমর্থন না করলে (`200` দেয়) শুরু থেকেই হবে।

**`ClosedFailure`।**
`api.close()`-এর পরে call হয়েছে — সাধারণত hot restart বা একাধিক client বানানোর ফল।
পুরো অ্যাপে একটাই client রাখুন।

---

## ২৮. Cheat sheet

| কাজ | কোড |
|---|---|
| client | `OmniNetwork(baseUrl: url, enableLogging: true)` |
| একটা object | `api.get<User>('/users/1', decoder: User.fromJson)` |
| তালিকা | `api.getList<User>('/users', decoder: User.fromJson)` |
| পাঠানো | `api.post / put / patch / delete` + `body:` |
| status/header সহ | `api.getResponse<T>(...)` |
| error | `on OmniNetworkException catch (e)` → `e.isOffline`, `e.isUnauthorized`, `e.statusCode` |
| try ছাড়া | `.asResult()` → `Ok` / `Err` |
| login | `api.auth.login(Tokens(access: a, refresh: r))` |
| logout | `api.auth.logout()` |
| refresh | `OmniAuth(refresh: (tokens, api) async => Tokens(...))` |
| login মনে রাখা | `OmniAuth(storage: SecureTokenStorage())` + `api.auth.restore()` |
| token ছাড়া call | `auth: false` |
| retry | `retry: const RetryPolicy()` |
| cache | `cache: OmniCache()` + `cache: CachePolicy.networkFirst` |
| খোলস খোলা | `responseAdapter: const EnvelopeResponseAdapter()` |
| বাতিল | `OmniCancelToken()` → `token.cancel()`; `api.cancelAll()` |
| upload | `api.upload('/x', files: [UploadFile.fromBytes(...)])` |
| download | `api.downloadBytes(...)`, `api.downloadToFile(..., resume: true)` |
| পাতায় পাতায় | `api.paginate<T>(..., strategy: const PagePagination())` |
| UI state | `api.watch<T>(...)` → `stream` |
| endpoint | `Endpoint.get<T>(...)` + `api.call(...)` |
| offline | `OfflineQueue(client: api).sendOrQueue(...)` |
| header যোগ | `OmniInterceptor.onRequest` → `r.withHeader(...)` |
| test | `OmniNetwork(transport: OmniMock()..get(...))` |
| inspector | `OmniInspector()` + `logSink: inspector.sink('api')` |
| cURL | `api.toCurl(request)` |
| বন্ধ | `await api.close()` |
