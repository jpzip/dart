import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cache.dart';
import 'http.dart';
import 'types.dart';

/// Hook signature for spec-version mismatch notifications.
typedef SpecMismatchHook = void Function(String expected, String received);

final RegExp _zipRegex = RegExp(r'^\d{7}$');
final RegExp _prefixRegex = RegExp(r'^\d{1,3}$');

/// The jpzip SDK entry point.
class JpzipClient {
  final String baseURL;
  final http.Client _http;
  final bool _ownsHttp;
  final Cache? cache;
  final int memCap;
  final SpecMismatchHook? onSpecMismatch;

  late final MemoryLRU _mem = MemoryLRU(memCap);

  Meta? _metaCached;
  bool _metaResolved = false;
  String _knownVersion = '';
  final _metaLock = _Lock();
  bool _specWarned = false;

  /// Creates a client.
  ///
  /// - [baseURL]: CDN origin (default `defaultBaseURL`).
  /// - [httpClient]: optional shared `http.Client` (e.g. for testing). If not
  ///   provided, the client creates and owns one and will close it via
  ///   [close].
  /// - [cache]: optional L2 persistent cache.
  /// - [memoryCacheSize]: L1 capacity in prefix entries (default 100).
  /// - [onSpecMismatch]: invoked once if `/meta.json`'s spec_version differs
  ///   from this SDK's [specVersion].
  JpzipClient({
    String? baseURL,
    http.Client? httpClient,
    this.cache,
    int memoryCacheSize = 100,
    this.onSpecMismatch,
  })  : baseURL = _trimTrailingSlash(baseURL ?? defaultBaseURL),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        memCap = memoryCacheSize;

  static String _trimTrailingSlash(String s) {
    var t = s;
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// Returns the entry for [zipcode], or `null` if not found.
  /// Malformed input returns `null` without contacting the network.
  Future<ZipcodeEntry?> lookup(String zipcode) async {
    if (!_zipRegex.hasMatch(zipcode)) return null;
    final dict = await _fetchPrefixDict(zipcode.substring(0, 3));
    if (dict == null) return null;
    return dict[zipcode];
  }

  /// Fetches all entries under a 1-, 2-, or 3-digit prefix.
  /// A 2-digit prefix fans out into 10 prefix-3 fetches.
  Future<Map<String, ZipcodeEntry>> lookupGroup(String prefix) async {
    if (!_prefixRegex.hasMatch(prefix)) {
      throw InvalidPrefixError(prefix);
    }
    switch (prefix.length) {
      case 3:
        final d = await _fetchPrefixDict(prefix);
        return d ?? <String, ZipcodeEntry>{};
      case 1:
        final d = await _fetchURL('$baseURL/g/$prefix.json');
        return d ?? <String, ZipcodeEntry>{};
      case 2:
        final futures = List<Future<Map<String, ZipcodeEntry>?>>.generate(
          10,
          (i) => _fetchPrefixDict('$prefix$i'),
        );
        final results = await Future.wait(futures);
        final out = <String, ZipcodeEntry>{};
        for (final d in results) {
          if (d != null) out.addAll(d);
        }
        return out;
    }
    throw InvalidPrefixError(prefix);
  }

  /// Fetches the full dataset by fanning out across `/g/0..9.json` in
  /// parallel and merging the results.
  Future<Map<String, ZipcodeEntry>> lookupAll() async {
    final futures = List<Future<Map<String, ZipcodeEntry>?>>.generate(
      10,
      (i) => _fetchURL('$baseURL/g/$i.json'),
    );
    final results = await Future.wait(futures);
    final out = <String, ZipcodeEntry>{};
    for (final d in results) {
      if (d != null) out.addAll(d);
    }
    return out;
  }

  /// Returns the cached `/meta.json`. The first call hits the network;
  /// subsequent calls reuse the result until [refresh] is called.
  Future<Meta?> getMeta() async {
    return _metaLock.synchronized(() async {
      if (_metaResolved) return _metaCached;
      final raw = await getRaw(_http, '$baseURL/meta.json');
      if (raw.statusCode == 404 || raw.body == null) {
        _metaResolved = true;
        return null;
      }
      final Meta m;
      try {
        m = Meta.fromJson(
          jsonDecode(utf8.decode(raw.body!)) as Map<String, dynamic>,
        );
      } catch (e) {
        throw FormatException('jpzip: parse meta: $e');
      }
      if (m.specVersion != specVersion &&
          onSpecMismatch != null &&
          !_specWarned) {
        _specWarned = true;
        onSpecMismatch!(specVersion, m.specVersion);
      }
      if (_knownVersion.isNotEmpty && _knownVersion != m.version) {
        _mem.clear();
        if (cache != null) await cache!.clear();
      }
      _knownVersion = m.version;
      _metaCached = m;
      _metaResolved = true;
      return m;
    });
  }

  /// Pulls the requested scope into L1 (and L2 when configured).
  /// `scope == 'all'` downloads the full dataset; otherwise it must be a
  /// valid prefix.
  Future<void> preload(String scope) async {
    if (scope == 'all') {
      final dict = await lookupAll();
      final buckets = <String, Map<String, ZipcodeEntry>>{};
      for (final entry in dict.entries) {
        final p = entry.key.substring(0, 3);
        (buckets[p] ??= <String, ZipcodeEntry>{})[entry.key] = entry.value;
      }
      for (final e in buckets.entries) {
        final url = _prefixURL(e.key);
        _mem.set(url, e.value);
        await _writeL2(url, e.value);
      }
      return;
    }
    if (!_prefixRegex.hasMatch(scope)) {
      throw InvalidPrefixError(scope);
    }
    await lookupGroup(scope);
  }

  /// Wipes L1 (and L2 when configured) and forgets the cached meta.
  Future<void> refresh() async {
    _mem.clear();
    _metaCached = null;
    _metaResolved = false;
    _knownVersion = '';
    _specWarned = false;
    if (cache != null) await cache!.clear();
  }

  /// Closes the underlying [http.Client] if this client owns it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  /* ---------------------------- internals ---------------------------- */

  String _prefixURL(String prefix3) => '$baseURL/p/$prefix3.json';

  Future<Map<String, ZipcodeEntry>?> _fetchPrefixDict(String prefix3) async {
    final url = _prefixURL(prefix3);
    final l1 = _mem.get(url);
    if (l1 != null) return l1;
    final l2 = await _readL2(url);
    if (l2 != null) {
      _mem.set(url, l2);
      return l2;
    }
    final d = await _fetchURL(url);
    if (d != null) {
      _mem.set(url, d);
      await _writeL2(url, d);
    }
    return d;
  }

  Future<Map<String, ZipcodeEntry>?> _fetchURL(String url) async {
    final raw = await getRaw(_http, url);
    if (raw.statusCode == 404 || raw.body == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(raw.body!)) as Map<String, dynamic>;
      return decoded.map(
        (k, v) =>
            MapEntry(k, ZipcodeEntry.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      throw FormatException('jpzip: parse $url: $e');
    }
  }

  Future<Map<String, ZipcodeEntry>?> _readL2(String url) async {
    final c = cache;
    if (c == null) return null;
    final bytes = await c.get(url);
    if (bytes == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return decoded.map(
        (k, v) =>
            MapEntry(k, ZipcodeEntry.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      // corrupt cache - drop it
      await c.delete(url);
      return null;
    }
  }

  Future<void> _writeL2(String url, Map<String, ZipcodeEntry> dict) async {
    final c = cache;
    if (c == null) return;
    final raw = dict.map((k, v) => MapEntry(k, v.toJson()));
    await c.set(url, utf8.encode(jsonEncode(raw)));
  }
}

/// Reports whether [s] syntactically looks like a 7-digit zipcode.
bool isValidZipcode(String s) => _zipRegex.hasMatch(s);

/// A tiny re-entrant-free async mutex used to serialize meta access.
class _Lock {
  Future<void>? _tail;

  Future<T> synchronized<T>(Future<T> Function() body) async {
    final prev = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    if (prev != null) {
      await prev;
    }
    try {
      return await body();
    } finally {
      completer.complete();
    }
  }
}
