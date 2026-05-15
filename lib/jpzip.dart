/// jpzip Dart SDK — the Japanese postal-code dataset from
/// https://jpzip.nadai.dev.
///
/// The SDK fetches normalized JSON from the CDN, keeps a per-prefix
/// in-memory LRU, and optionally backs that with a user-supplied persistent
/// cache.
library;

import 'src/client.dart';
import 'src/types.dart';

export 'src/cache.dart' show Cache, MemoryLRU;
export 'src/client.dart' show JpzipClient, SpecMismatchHook, isValidZipcode;
export 'src/types.dart'
    show
        Endpoints,
        InvalidPrefixError,
        Meta,
        Town,
        ZipcodeEntry,
        defaultBaseURL,
        specVersion;

JpzipClient? _default;

JpzipClient _dflt() => _default ??= JpzipClient();

/// Looks up a single zipcode using the lazily-initialized default client.
Future<ZipcodeEntry?> lookup(String zipcode) => _dflt().lookup(zipcode);

/// Fetches all entries under a 1-, 2-, or 3-digit prefix using the default
/// client.
Future<Map<String, ZipcodeEntry>> lookupGroup(String prefix) =>
    _dflt().lookupGroup(prefix);

/// Fetches the full dataset using the default client.
Future<Map<String, ZipcodeEntry>> lookupAll() => _dflt().lookupAll();

/// Preloads the requested scope into the default client's L1 cache.
Future<void> preload(String scope) => _dflt().preload(scope);

/// Returns `/meta.json` via the default client.
Future<Meta?> getMeta() => _dflt().getMeta();
