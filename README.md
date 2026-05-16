# jpzip

[![pub.dev](https://img.shields.io/pub/v/jpzip.svg)](https://pub.dev/packages/jpzip)
[![pub points](https://img.shields.io/pub/points/jpzip)](https://pub.dev/packages/jpzip/score)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-%5E3.0.0-0175C2.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Publish](https://github.com/jpzip/dart/actions/workflows/publish.yml/badge.svg)](https://github.com/jpzip/dart/actions/workflows/publish.yml)

> Dart / Flutter SDK for **jpzip** — a free, unlimited Japanese postal code (郵便番号) API.
> 日本の全郵便番号 120,677 件を CDN 配信 JSON から引く Dart SDK。

**English** | [日本語](./README.ja.md)

`jpzip` looks up Japanese postal codes (郵便番号) from `jpzip.nadai.dev`,
a CDN-hosted dataset built from Japan Post's `KEN_ALL.csv` and `KEN_ALL_ROME.csv`
normalized to JSON. No registration, no rate limits, no API key.

- 🇯🇵 **Complete dataset** — 120,677 entries with kanji, kana, romaji, and government codes (JIS X 0401 / 総務省地方公共団体コード)
- ⚡️ **Fast** — L1 LRU + optional L2 persistent cache; `preload` to serve lookups without per-request network round-trips
- 🛡️ **Resilient** — 3-attempt retry with exponential backoff on 5xx / network failures
- 📱 **Flutter-ready** — pure Dart, runs on Flutter (mobile / desktop / web), CLI, and server
- 🪶 **Minimal deps** — only `package:http` + `package:meta`
- 🆓 **Free forever** — backed by Cloudflare Pages' free tier (no billing axis exists)
- 🔌 **Drop-in** — same API surface across [every jpzip SDK](#other-languages)

## Requirements

Dart SDK `^3.0.0` (null-safe). Works in Flutter, server, CLI, and Flutter Web.

## Install

```sh
dart pub add jpzip
# Flutter project
flutter pub add jpzip
```

Or in `pubspec.yaml`:

```yaml
dependencies:
  jpzip: ^0.1.1
```

## Quick Start

```dart
import 'package:jpzip/jpzip.dart';

Future<void> main() async {
  final entry = await lookup('2310017');
  if (entry == null) {
    print('not found');
    return;
  }
  print('${entry.prefecture} ${entry.city} ${entry.towns.first.town}');
  // Output: 神奈川県 横浜市中区 港町
}
```

Romaji and government codes are included on the same entry:

```dart
print('${entry.prefectureRoma} ${entry.cityRoma} ${entry.towns.first.roma}');
// Output: Kanagawa Ken Yokohama Shi Naka Ku Minatocho

print('${entry.prefectureCode} ${entry.cityCode}');
// Output: 14 14104
```

## Use Cases

### Filling an address form in Flutter

Call `lookup` from a `StatefulWidget` (or your Riverpod / Bloc notifier) and
push the result into your `TextEditingController`s when the user finishes
typing a 7-digit postal code:

```dart
import 'package:flutter/material.dart';
import 'package:jpzip/jpzip.dart';

class AddressForm extends StatefulWidget {
  const AddressForm({super.key});
  @override
  State<AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<AddressForm> {
  final _zip = TextEditingController();
  final _pref = TextEditingController();
  final _city = TextEditingController();
  final _town = TextEditingController();

  Future<void> _onZipChanged(String value) async {
    if (!isValidZipcode(value)) return; // skip until 7 digits typed
    final entry = await lookup(value);
    if (entry == null || !mounted) return;
    setState(() {
      _pref.text = entry.prefecture;
      _city.text = entry.city;
      _town.text = entry.towns.first.town;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: _zip,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '郵便番号 (7桁)'),
        onChanged: _onZipChanged,
      ),
      TextField(controller: _pref, decoration: const InputDecoration(labelText: '都道府県')),
      TextField(controller: _city, decoration: const InputDecoration(labelText: '市区町村')),
      TextField(controller: _town, decoration: const InputDecoration(labelText: '町名')),
    ]);
  }
}
```

### Batch validation

```dart
final all = await lookupAll(); // entire dataset in memory (~37 MiB JSON)
for (final zip in csvZipcodes) {
  if (!all.containsKey(zip)) {
    print('invalid zipcode: $zip');
  }
}
```

### Serve lookups from cache (BYO L2 backend)

The dataset is partitioned into 948 three-digit prefix buckets. The default
L1 (100 entries) keeps the hottest buckets; to cache the whole dataset, pair
`preload('all')` with an L2 cache or raise `memoryCacheSize` above 948.

```dart
final client = JpzipClient(
  memoryCacheSize: 1024,
  cache: myFileCache, // any Cache implementation (file / Hive / sqflite / KV)
);
await client.preload('all');
// Subsequent lookups are served from L1/L2 without hitting the network.
final entry = await client.lookup('2310017');
```

## API Reference

Full docs on [pub.dev](https://pub.dev/documentation/jpzip/latest/).

### Top-level functions (share a lazily-initialized default client)

| Function | Description |
|---|---|
| `Future<ZipcodeEntry?> lookup(zipcode)` | Look up a single 7-digit zipcode. Returns `null` if not found or malformed (no network call for malformed input). |
| `Future<Map<String, ZipcodeEntry>> lookupGroup(prefix)` | Look up by 1-, 2-, or 3-digit prefix. 1-digit fetches `/g/{d}.json`; 3-digit fetches `/p/{ddd}.json`; 2-digit fans out into 10 parallel 3-digit fetches and merges. |
| `Future<Map<String, ZipcodeEntry>> lookupAll()` | Fetch entire dataset (120k entries, ~37 MiB) in parallel across `/g/0..9.json`. |
| `Future<Meta?> getMeta()` | Dataset version, generated-at, per-prefecture counts, spec version. Result is cached until `refresh()`. |
| `Future<void> preload(scope)` | Warm L1 (and L2 when configured) for `'all'` or a specific prefix. |
| `bool isValidZipcode(s)` | Pure syntax check (`^\d{7}$`) — no network, synchronous. |

### `JpzipClient` (advanced)

Construct a configurable instance for L2 caching, custom HTTP client, alternate
base URL, or multiple isolated caches:

```dart
final client = JpzipClient(
  baseURL: 'https://jpzip.nadai.dev',
  httpClient: http.Client(),       // optional shared http.Client
  memoryCacheSize: 200,            // L1 capacity in prefix buckets, default 100
  cache: myCache,                  // optional L2
  onSpecMismatch: (expected, received) {
    debugPrint('jpzip spec mismatch: SDK=$expected server=$received');
  },
);
```

`JpzipClient` exposes `lookup` / `lookupGroup` / `lookupAll` / `getMeta` / `preload` plus:

| Method | Description |
|---|---|
| `Future<void> client.refresh()` | Wipe L1 (and L2 when configured) and forget the cached meta. |
| `void client.close()` | Close the underlying `http.Client` if it was created by the SDK. Safe to skip if you passed in your own. |

When `getMeta` observes that `/meta.json`'s `version` has changed since the last
successful fetch, L1 and L2 are cleared automatically — call `getMeta` periodically
to pick up dataset rollovers.

### Errors

- `InvalidPrefixError` (a subclass of `ArgumentError`) — thrown by `lookupGroup` / `preload` when the prefix is not 1-3 digits.
- Transient network failures and 5xx responses are retried up to 3 attempts (initial + 2 retries) with exponential backoff sleeps of 400ms and 800ms. Non-404 4xx responses (e.g. 403) throw immediately. 404 yields `null`.

### `Cache` interface

Bring your own L2 backend (file, `shared_preferences`, Hive, sqflite, IndexedDB, etc.):

```dart
abstract class Cache {
  Future<List<int>?> get(String key);
  Future<void> set(String key, List<int> value);
  Future<void> delete(String key);
  Future<void> clear();
}
```

Keys are the full prefix-bucket URLs (e.g. `https://jpzip.nadai.dev/p/231.json`); values are raw JSON bytes.

## Why jpzip?

| | **jpzip** | [postal_jp][postal_jp] | [japan_post_api_client][jp_client] | [postal_code_jp][postal_code_jp] |
|---|---|---|---|---|
| Romaji (`Yokohama Shi`) | ✅ | ❌ | ✅ | ❌ |
| Government codes (JIS / 総務省) | ✅ | ❌ | ⚠️ Partial | ❌ |
| No API key / credentials | ✅ | ✅ | ❌ Client ID + secret + IP allowlist | ✅ |
| No rate limit | ✅ | ⚠️ ZipCloud discouraged for bulk | ❌ Official quota | ✅ |
| Dart 3 / null-safe | ✅ | ✅ | ✅ | ❌ Dart 3 incompatible |
| Offline after preload | ✅ | ❌ | ❌ | ❌ |
| L1 + pluggable L2 cache | ✅ | ❌ | ❌ | ❌ |
| Actively maintained (2026) | ✅ | ❌ Discontinued | ✅ | ❌ 2020 |

[postal_jp]: https://pub.dev/packages/postal_jp
[jp_client]: https://pub.dev/packages/japan_post_api_client
[postal_code_jp]: https://pub.dev/packages/postal_code_jp

## Other Languages

Same API surface across all SDKs:

[Go](https://github.com/jpzip/go) · [TypeScript](https://github.com/jpzip/js) · [Python](https://github.com/jpzip/python) · [Rust](https://github.com/jpzip/rust) · [Ruby](https://github.com/jpzip/ruby) · [PHP](https://github.com/jpzip/php) · [Swift](https://github.com/jpzip/swift)

## Resources

- **Website** — https://jpzip.nadai.dev
- **Protocol spec** — [jpzip/spec](https://github.com/jpzip/spec)
- **Data ETL** — [jpzip/data](https://github.com/jpzip/data)
- **MCP server** — [jpzip/mcp](https://github.com/jpzip/mcp) — use jpzip from Claude / ChatGPT / Cursor

## Keywords

japanese postal code, japan zipcode, 郵便番号, KEN_ALL, KEN_ALL_ROME, address validation, japan address api, postal code lookup dart, flutter japanese address form, JIS X 0401, 総務省地方公共団体コード

## License

[MIT](./LICENSE)
