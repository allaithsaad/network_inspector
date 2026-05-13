import 'dart:convert';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_http_watcher/network_inspector.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_http_watcher Demo',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) => HttpWatcherOverlay(
        navigatorKey: navigatorKey,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

// ─── http wrapper ────────────────────────────────────────────────────────────
class _WatcherHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now();
    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    HttpWatcherLogger.instance.logRequest(
      method: request.method,
      url: request.url.toString(),
      headers: Map<String, String>.from(request.headers),
      body: request is http.Request ? request.body : null,
      statusCode: streamed.statusCode,
      responseBody: utf8.decode(bytes, allowMalformed: true),
      startTime: start,
    );
    return http.StreamedResponse(Stream.value(bytes), streamed.statusCode,
        headers: streamed.headers, contentLength: bytes.length);
  }

  @override
  void close() => _inner.close();
}

// ─── dio interceptor ─────────────────────────────────────────────────────────
class _WatcherDioInterceptor extends dio_pkg.Interceptor {
  final _starts = <int, DateTime>{};

  @override
  void onRequest(dio_pkg.RequestOptions o, dio_pkg.RequestInterceptorHandler h) {
    _starts[o.hashCode] = DateTime.now();
    h.next(o);
  }

  @override
  void onResponse(dio_pkg.Response r, dio_pkg.ResponseInterceptorHandler h) {
    final start = _starts.remove(r.requestOptions.hashCode) ?? DateTime.now();
    HttpWatcherLogger.instance.logRequest(
      method: r.requestOptions.method,
      url: r.requestOptions.uri.toString(),
      headers: r.requestOptions.headers.map((k, v) => MapEntry(k, v.toString())),
      body: r.requestOptions.data,
      statusCode: r.statusCode ?? 0,
      responseBody: r.data?.toString() ?? '',
      startTime: start,
    );
    h.next(r);
  }

  @override
  void onError(dio_pkg.DioException e, dio_pkg.ErrorInterceptorHandler h) {
    final start = _starts.remove(e.requestOptions.hashCode) ?? DateTime.now();
    HttpWatcherLogger.instance.logRequest(
      method: e.requestOptions.method,
      url: e.requestOptions.uri.toString(),
      headers: e.requestOptions.headers.map((k, v) => MapEntry(k, v.toString())),
      body: e.requestOptions.data,
      statusCode: e.response?.statusCode ?? 0,
      responseBody: e.response?.data?.toString() ?? e.message ?? '',
      startTime: start,
    );
    h.next(e);
  }
}

// ─── Home ─────────────────────────────────────────────────────────────────────
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_http_watcher Demo'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(tabs: [
            Tab(text: 'http'),
            Tab(text: 'dio'),
            Tab(text: 'Manual'),
          ]),
        ),
        body: const TabBarView(children: [
          _HttpTab(),
          _DioTab(),
          _ManualTab(),
        ]),
      ),
    );
  }
}

// ─── http tab ────────────────────────────────────────────────────────────────
class _HttpTab extends StatefulWidget {
  const _HttpTab();
  @override
  State<_HttpTab> createState() => _HttpTabState();
}

class _HttpTabState extends State<_HttpTab> with AutomaticKeepAliveClientMixin {
  final _client = _WatcherHttpClient();
  final List<String> _results = [];
  bool _loading = false;

  Future<void> _get(String label, String url) async {
    setState(() => _loading = true);
    try {
      final res = await _client.get(Uri.parse(url));
      final decoded = jsonDecode(res.body);
      final preview = _preview(decoded);
      setState(() => _results.insert(0, '[$label] ${res.statusCode} — $preview'));
    } catch (e) {
      setState(() => _results.insert(0, '[$label] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    setState(() => _loading = true);
    try {
      final res = await _client.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': 'Hello', 'body': 'World', 'userId': 1}),
      );
      final id = (jsonDecode(res.body) as Map)['id'];
      setState(() => _results.insert(0, '[POST /posts] ${res.statusCode} — id: $id'));
    } catch (e) {
      setState(() => _results.insert(0, '[POST] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _TabLayout(
      loading: _loading,
      results: _results,
      buttons: [
        _Btn('GET /posts', () => _get('GET /posts', 'https://jsonplaceholder.typicode.com/posts'), _loading),
        _Btn('GET /users', () => _get('GET /users', 'https://jsonplaceholder.typicode.com/users'), _loading),
        _Btn('GET /post/1', () => _get('GET /post/1', 'https://jsonplaceholder.typicode.com/posts/1'), _loading),
        _Btn('GET 404', () => _get('GET 404', 'https://jsonplaceholder.typicode.com/posts/99999'), _loading),
        _Btn('POST /posts', _post, _loading, primary: true),
      ],
    );
  }
}

// ─── dio tab ─────────────────────────────────────────────────────────────────
class _DioTab extends StatefulWidget {
  const _DioTab();
  @override
  State<_DioTab> createState() => _DioTabState();
}

class _DioTabState extends State<_DioTab> with AutomaticKeepAliveClientMixin {
  late final dio_pkg.Dio _dio = dio_pkg.Dio()
    ..interceptors.add(_WatcherDioInterceptor());
  final List<String> _results = [];
  bool _loading = false;

  Future<void> _get(String label, String url) async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get(url);
      final preview = _preview(res.data);
      setState(() => _results.insert(0, '[$label] ${res.statusCode} — $preview'));
    } catch (e) {
      setState(() => _results.insert(0, '[$label] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.post(
        'https://jsonplaceholder.typicode.com/posts',
        data: {'title': 'Hello', 'body': 'World', 'userId': 1},
      );
      final id = (res.data as Map)['id'];
      setState(() => _results.insert(0, '[POST /posts] ${res.statusCode} — id: $id'));
    } catch (e) {
      setState(() => _results.insert(0, '[POST] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _TabLayout(
      loading: _loading,
      results: _results,
      buttons: [
        _Btn('GET /posts', () => _get('GET /posts', 'https://jsonplaceholder.typicode.com/posts'), _loading),
        _Btn('GET /users', () => _get('GET /users', 'https://jsonplaceholder.typicode.com/users'), _loading),
        _Btn('GET /post/1', () => _get('GET /post/1', 'https://jsonplaceholder.typicode.com/posts/1'), _loading),
        _Btn('GET 404', () => _get('GET 404', 'https://jsonplaceholder.typicode.com/posts/99999'), _loading),
        _Btn('POST /posts', _post, _loading, primary: true),
      ],
    );
  }
}

// ─── manual tab ──────────────────────────────────────────────────────────────
class _ManualTab extends StatefulWidget {
  const _ManualTab();
  @override
  State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab> with AutomaticKeepAliveClientMixin {
  final _client = http.Client();
  final List<String> _results = [];
  bool _loading = false;

  Future<void> _get(String label, String url) async {
    setState(() => _loading = true);
    final start = DateTime.now();
    try {
      final res = await _client.get(Uri.parse(url));
      // Manually log — works with any HTTP client
      HttpWatcherLogger.instance.logRequest(
        method: 'GET',
        url: url,
        statusCode: res.statusCode,
        responseBody: res.body,
        startTime: start,
      );
      final preview = _preview(jsonDecode(res.body));
      setState(() => _results.insert(0, '[$label] ${res.statusCode} — $preview'));
    } catch (e) {
      setState(() => _results.insert(0, '[$label] Error: $e'));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _TabLayout(
      loading: _loading,
      results: _results,
      buttons: [
        _Btn('GET /posts', () => _get('GET /posts', 'https://jsonplaceholder.typicode.com/posts'), _loading),
        _Btn('GET /users', () => _get('GET /users', 'https://jsonplaceholder.typicode.com/users'), _loading),
        _Btn('GET /todos', () => _get('GET /todos', 'https://jsonplaceholder.typicode.com/todos?_limit=5'), _loading),
        _Btn('GET 404', () => _get('GET 404', 'https://jsonplaceholder.typicode.com/posts/99999'), _loading),
      ],
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────
String _preview(dynamic data) {
  if (data is List) return '${data.length} items';
  if (data is Map) return data.entries.take(2).map((e) => '${e.key}: ${e.value}').join(', ');
  return data.toString();
}

class _TabLayout extends StatelessWidget {
  final bool loading;
  final List<String> results;
  final List<Widget> buttons;

  const _TabLayout({required this.loading, required this.results, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ),
        if (loading) const LinearProgressIndicator(),
        const Divider(height: 1),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text(
                    'Tap a button to make a request.\nWatch the floating inspector button.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(results[i], style: const TextStyle(fontSize: 13)),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool primary;

  const _Btn(this.label, this.onPressed, this.loading, {this.primary = false});

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton(
        onPressed: loading ? null : onPressed,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }
    return FilledButton.tonal(
      onPressed: loading ? null : onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
