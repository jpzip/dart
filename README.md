# jpzip — Dart SDK

> 日本の郵便番号を CDN 配信の JSON データから引く Dart SDK。Flutter / CLI / サーバー / Web で動く。

- 配信ドメイン: `https://jpzip.nadai.dev`
- プロトコル仕様: [`jpzip/spec`](https://github.com/jpzip/spec)
- データ ETL: [`jpzip/data`](https://github.com/jpzip/data)

## インストール

`pubspec.yaml`:

```yaml
dependencies:
  jpzip: ^0.1.0
```

```sh
dart pub get
# Flutter プロジェクトなら
flutter pub get
```

## 使い方

### 関数 API

```dart
import 'package:jpzip/jpzip.dart';

void main() async {
  final entry = await lookup('2310831');
  // entry == null なら見つからなかった
  print(entry?.prefecture); // 神奈川県
  print(entry?.city);       // 横浜市中区

  final dict = await lookupGroup('23'); // 2 桁は 10 並列 fetch
  final all  = await lookupAll();
  final meta = await getMeta();
}
```

### クライアント API (L2 キャッシュ・複数インスタンス用)

```dart
import 'package:jpzip/jpzip.dart';

final client = JpzipClient(
  baseURL: 'https://jpzip.nadai.dev',
  memoryCacheSize: 200,
  cache: myCache,            // Cache を実装
  onSpecMismatch: (expected, received) {
    print('spec mismatch: $expected vs $received');
  },
);

await client.preload('all');
final entry = await client.lookup('2310831');
client.close(); // 内部 http.Client を閉じる
```

## Cache 抽象クラス

```dart
abstract class Cache {
  Future<List<int>?> get(String key);
  Future<void> set(String key, List<int> value);
  Future<void> delete(String key);
  Future<void> clear();
}
```

ファイル / SharedPreferences / Hive / sqflite / IndexedDB 等、任意の実装を渡せる。

## 入力検証

`lookup()` は `^\d{7}$` にマッチしない入力には fetch せず `null` を返す。検証だけしたい場合は `isValidZipcode()` を使う。

## バージョン整合性

`getMeta()` で `spec_version` が SDK の対応バージョンと異なる場合、`onSpecMismatch` コールバックが 1 度だけ呼ばれる。データバージョン (`version`) が変わった場合、L1 / L2 キャッシュは自動 invalidate される。

## リトライ

5xx / ネットワークエラーは最大 3 回まで指数バックオフ (200ms × 2^attempt) でリトライする。404 はリトライしない (該当なしとして `null` を返す)。

## ライセンス

[MIT](./LICENSE)
