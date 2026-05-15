import 'dart:collection';
import 'dart:typed_data';

import 'types.dart';

/// The abstract interface a user-supplied L2 persistent cache must satisfy.
abstract class Cache {
  /// Returns the value previously stored under [key], or `null` if absent.
  Future<List<int>?> get(String key);

  /// Stores [value] under [key].
  Future<void> set(String key, List<int> value);

  /// Removes [key].
  Future<void> delete(String key);

  /// Wipes all entries.
  Future<void> clear();
}

/// The L1 in-memory cache, bounded by a fixed number of prefix entries.
///
/// Uses a `LinkedHashMap` to maintain insertion order; on access we move the
/// entry to the end so the head is always the least-recently-used.
class MemoryLRU {
  final int capacity;
  final LinkedHashMap<String, Map<String, ZipcodeEntry>> _items =
      LinkedHashMap<String, Map<String, ZipcodeEntry>>();

  MemoryLRU(int capacity) : capacity = capacity < 1 ? 1 : capacity;

  Map<String, ZipcodeEntry>? get(String key) {
    final v = _items.remove(key);
    if (v == null) return null;
    _items[key] = v; // re-insert at tail (most-recently-used)
    return v;
  }

  void set(String key, Map<String, ZipcodeEntry> value) {
    if (_items.containsKey(key)) {
      _items.remove(key);
    } else if (_items.length >= capacity) {
      _items.remove(_items.keys.first);
    }
    _items[key] = value;
  }

  void clear() {
    _items.clear();
  }

  int get size => _items.length;
}

/// Helper to convert a `List<int>` (possibly a `Uint8List`) to bytes.
Uint8List toBytes(List<int> v) =>
    v is Uint8List ? v : Uint8List.fromList(v);
