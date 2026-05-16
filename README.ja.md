# jpzip

[![pub.dev](https://img.shields.io/pub/v/jpzip.svg)](https://pub.dev/packages/jpzip)
[![pub points](https://img.shields.io/pub/points/jpzip)](https://pub.dev/packages/jpzip/score)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-%5E3.0.0-0175C2.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Publish](https://github.com/jpzip/dart/actions/workflows/publish.yml/badge.svg)](https://github.com/jpzip/dart/actions/workflows/publish.yml)

> **jpzip** の Dart / Flutter SDK — 無料・無制限の日本郵便番号 API。
> 日本郵便の `KEN_ALL.csv` / `KEN_ALL_ROME.csv` を JSON 正規化し CDN 配信。

[English](./README.md) | **日本語**

`jpzip` は `jpzip.nadai.dev` から日本の郵便番号 120,677 件を引く Dart SDK です。
登録不要、レート制限なし、API キー不要。

- 🇯🇵 **全件収録** — 漢字・カナ・ローマ字・自治体コード(JIS X 0401 / 総務省地方公共団体コード)
- ⚡️ **高速** — L1 LRU + 任意の L2 永続キャッシュ。`preload` でネットワーク往復なしのルックアップが可能
- 🛡️ **堅牢** — 5xx / ネットワーク失敗時は指数バックオフで最大 3 回リトライ
- 📱 **Flutter 対応** — 純粋 Dart で Flutter(モバイル / デスクトップ / Web)・CLI・サーバーで動作
- 🪶 **最小依存** — `package:http` と `package:meta` のみ
- 🆓 **永久無料** — Cloudflare Pages 無料枠で運用(課金軸が存在しない)
- 🔌 **同一 API** — [全 jpzip SDK](#他言語版) で API が揃う

## 必要環境

Dart SDK `^3.0.0`(null safety)。Flutter / サーバー / CLI / Flutter Web で動作します。

## インストール

```sh
dart pub add jpzip
# Flutter プロジェクトなら
flutter pub add jpzip
```

または `pubspec.yaml`:

```yaml
dependencies:
  jpzip: ^0.1.1
```

## クイックスタート

```dart
import 'package:jpzip/jpzip.dart';

Future<void> main() async {
  final entry = await lookup('2310017');
  if (entry == null) {
    print('見つかりません');
    return;
  }
  print('${entry.prefecture} ${entry.city} ${entry.towns.first.town}');
  // 出力: 神奈川県 横浜市中区 港町
}
```

ローマ字・自治体コードも同じエントリに含まれます:

```dart
print('${entry.prefectureRoma} ${entry.cityRoma} ${entry.towns.first.roma}');
// 出力: Kanagawa Ken Yokohama Shi Naka Ku Minatocho

print('${entry.prefectureCode} ${entry.cityCode}');
// 出力: 14 14104
```

## ユースケース

### Flutter のフォームから住所を埋める

`StatefulWidget`(または Riverpod / Bloc などの notifier)から `lookup` を呼び、
ユーザーが 7 桁を入力し終わったタイミングで結果を `TextEditingController` に
反映するだけです:

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
    if (!isValidZipcode(value)) return; // 7 桁揃うまで何もしない
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

### CSV のバッチ検証

```dart
final all = await lookupAll(); // 全件をメモリに展開(JSON 約 37 MiB)
for (final zip in csvZipcodes) {
  if (!all.containsKey(zip)) {
    print('不正な郵便番号: $zip');
  }
}
```

### キャッシュからの提供(任意の L2 バックエンド)

データは 948 個の 3 桁 prefix バケットに分割されています。デフォルト L1 (100 件) は
ホットなバケットを保持しますが、全件を常駐させるには L2 を併用するか
`memoryCacheSize` を 948 超に設定してください。

```dart
final client = JpzipClient(
  memoryCacheSize: 1024,
  cache: myFileCache, // Cache 実装(file / Hive / sqflite / KV など)
);
await client.preload('all');
// 以降の lookup は L1/L2 で完結し、ネットワークにアクセスしない
final entry = await client.lookup('2310017');
```

## API リファレンス

完全版は [pub.dev のドキュメント](https://pub.dev/documentation/jpzip/latest/) を参照。

### トップレベル関数(内部の default Client を共有)

| 関数 | 説明 |
|---|---|
| `Future<ZipcodeEntry?> lookup(zipcode)` | 7 桁の郵便番号で 1 件引く。見つからない / 不正な入力は `null`(不正入力時はネットワーク不使用)。 |
| `Future<Map<String, ZipcodeEntry>> lookupGroup(prefix)` | 1〜3 桁の prefix で引く。1 桁は `/g/{d}.json` を 1 回、3 桁は `/p/{ddd}.json` を 1 回、2 桁は 10 並列 fetch して結合。 |
| `Future<Map<String, ZipcodeEntry>> lookupAll()` | `/g/0..9.json` を並列取得して全件(120k 件、約 37 MiB)を返す。 |
| `Future<Meta?> getMeta()` | データバージョン・生成日時・都道府県別件数・spec version。`refresh()` までは結果をキャッシュ。 |
| `Future<void> preload(scope)` | `'all'` または特定 prefix で L1(L2 設定時は L2 も)を温める。 |
| `bool isValidZipcode(s)` | 純粋な書式チェック(`^\d{7}$`)。同期・ネットワーク不使用。 |

### `JpzipClient`(高度な用途)

L2 キャッシュ、HTTP クライアント差し替え、配信元変更、複数の独立キャッシュが
必要な場合に使用:

```dart
final client = JpzipClient(
  baseURL: 'https://jpzip.nadai.dev',
  httpClient: http.Client(),       // 共有 http.Client(任意)
  memoryCacheSize: 200,            // L1 容量(prefix バケット数)、デフォルト 100
  cache: myCache,                  // L2(任意)
  onSpecMismatch: (expected, received) {
    debugPrint('jpzip spec 不一致: SDK=$expected server=$received');
  },
);
```

`JpzipClient` は `lookup` / `lookupGroup` / `lookupAll` / `getMeta` / `preload` に加えて:

| メソッド | 説明 |
|---|---|
| `Future<void> client.refresh()` | L1(L2 設定時は L2 も)を消し、キャッシュ済み meta を破棄。 |
| `void client.close()` | SDK が内部生成した `http.Client` を閉じる。`httpClient` を自前で渡した場合は呼ぶ必要なし。 |

`getMeta` が `/meta.json` の `version` 変更を検知すると L1/L2 が自動クリアされます。
データ切り替えに追従するには `getMeta` を定期的に呼んでください。

### エラー

- `InvalidPrefixError`(`ArgumentError` のサブクラス)— prefix が 1〜3 桁でない場合に `lookupGroup` / `preload` から送出される。
- ネットワーク失敗と 5xx は最大 3 回試行(初回 + リトライ 2 回)、指数バックオフのスリープは 400ms / 800ms。404 以外の 4xx(例: 403)は即座に例外。404 は `null` 返却。

### `Cache` インターフェース

任意の L2 バックエンド(ファイル / `shared_preferences` / Hive / sqflite / IndexedDB など)を渡せます:

```dart
abstract class Cache {
  Future<List<int>?> get(String key);
  Future<void> set(String key, List<int> value);
  Future<void> delete(String key);
  Future<void> clear();
}
```

キーは prefix バケットの完全 URL(例: `https://jpzip.nadai.dev/p/231.json`)、値は生 JSON バイト列。

## なぜ jpzip か

| | **jpzip** | [postal_jp][postal_jp] | [japan_post_api_client][jp_client] | [postal_code_jp][postal_code_jp] |
|---|---|---|---|---|
| ローマ字(`Yokohama Shi`) | ✅ | ❌ | ✅ | ❌ |
| 自治体コード(JIS / 総務省) | ✅ | ❌ | ⚠️ 一部 | ❌ |
| API キー / 認証情報なし | ✅ | ✅ | ❌ Client ID + Secret + IP 許可制 | ✅ |
| レート制限なし | ✅ | ⚠️ ZipCloud は大量アクセス非推奨 | ❌ 公式クォータあり | ✅ |
| Dart 3 / null safe | ✅ | ✅ | ✅ | ❌ Dart 3 非対応 |
| Preload 後オフライン | ✅ | ❌ | ❌ | ❌ |
| L1 + 差し替え可能な L2 | ✅ | ❌ | ❌ | ❌ |
| 現役メンテ(2026) | ✅ | ❌ Discontinued | ✅ | ❌ 2020 で停止 |

[postal_jp]: https://pub.dev/packages/postal_jp
[jp_client]: https://pub.dev/packages/japan_post_api_client
[postal_code_jp]: https://pub.dev/packages/postal_code_jp

## 他言語版

全 SDK で同一の API を提供しています:

[Go](https://github.com/jpzip/go) · [TypeScript](https://github.com/jpzip/js) · [Python](https://github.com/jpzip/python) · [Rust](https://github.com/jpzip/rust) · [Ruby](https://github.com/jpzip/ruby) · [PHP](https://github.com/jpzip/php) · [Swift](https://github.com/jpzip/swift)

## 関連リソース

- **Web サイト** — https://jpzip.nadai.dev
- **プロトコル仕様** — [jpzip/spec](https://github.com/jpzip/spec)
- **データ ETL** — [jpzip/data](https://github.com/jpzip/data)
- **MCP サーバー** — [jpzip/mcp](https://github.com/jpzip/mcp) — Claude / ChatGPT / Cursor から jpzip を呼ぶ

## キーワード

日本郵便番号, 郵便番号, KEN_ALL, KEN_ALL_ROME, 住所検索, 住所バリデーション, Flutter 住所フォーム, Dart 住所検索, japanese postal code, japan zipcode, JIS X 0401, 総務省地方公共団体コード

## ライセンス

[MIT](./LICENSE)
