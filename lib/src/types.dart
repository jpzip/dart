import 'package:meta/meta.dart';

/// The jpzip protocol version this SDK targets.
const String specVersion = '1.0';

/// The production CDN origin.
const String defaultBaseURL = 'https://jpzip.nadai.dev';

/// One element of [ZipcodeEntry.towns].
@immutable
class Town {
  final String town;
  final String kana;
  final String roma;
  final String? note;

  const Town({
    required this.town,
    required this.kana,
    required this.roma,
    this.note,
  });

  factory Town.fromJson(Map<String, dynamic> json) {
    return Town(
      town: json['town'] as String? ?? '',
      kana: json['kana'] as String? ?? '',
      roma: json['roma'] as String? ?? '',
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'town': town,
      'kana': kana,
      'roma': roma,
    };
    if (note != null) m['note'] = note;
    return m;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Town &&
          other.town == town &&
          other.kana == kana &&
          other.roma == roma &&
          other.note == note;

  @override
  int get hashCode => Object.hash(town, kana, roma, note);

  @override
  String toString() =>
      'Town(town: $town, kana: $kana, roma: $roma, note: $note)';
}

/// One logical entry as published by the CDN.
@immutable
class ZipcodeEntry {
  final String prefecture;
  final String prefectureKana;
  final String prefectureRoma;
  final String prefectureCode;
  final String city;
  final String cityKana;
  final String cityRoma;
  final String cityCode;
  final List<Town> towns;

  const ZipcodeEntry({
    required this.prefecture,
    required this.prefectureKana,
    required this.prefectureRoma,
    required this.prefectureCode,
    required this.city,
    required this.cityKana,
    required this.cityRoma,
    required this.cityCode,
    required this.towns,
  });

  factory ZipcodeEntry.fromJson(Map<String, dynamic> json) {
    final rawTowns = json['towns'] as List<dynamic>? ?? const [];
    return ZipcodeEntry(
      prefecture: json['prefecture'] as String? ?? '',
      prefectureKana: json['prefecture_kana'] as String? ?? '',
      prefectureRoma: json['prefecture_roma'] as String? ?? '',
      prefectureCode: json['prefecture_code'] as String? ?? '',
      city: json['city'] as String? ?? '',
      cityKana: json['city_kana'] as String? ?? '',
      cityRoma: json['city_roma'] as String? ?? '',
      cityCode: json['city_code'] as String? ?? '',
      towns: rawTowns
          .map((t) => Town.fromJson(t as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'prefecture': prefecture,
        'prefecture_kana': prefectureKana,
        'prefecture_roma': prefectureRoma,
        'prefecture_code': prefectureCode,
        'city': city,
        'city_kana': cityKana,
        'city_roma': cityRoma,
        'city_code': cityCode,
        'towns': towns.map((t) => t.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZipcodeEntry &&
          other.prefecture == prefecture &&
          other.prefectureKana == prefectureKana &&
          other.prefectureRoma == prefectureRoma &&
          other.prefectureCode == prefectureCode &&
          other.city == city &&
          other.cityKana == cityKana &&
          other.cityRoma == cityRoma &&
          other.cityCode == cityCode &&
          _listEq(other.towns, towns);

  @override
  int get hashCode => Object.hash(
        prefecture,
        prefectureKana,
        prefectureRoma,
        prefectureCode,
        city,
        cityKana,
        cityRoma,
        cityCode,
        Object.hashAll(towns),
      );

  @override
  String toString() =>
      'ZipcodeEntry(prefecture: $prefecture, city: $city, towns: $towns)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Part of [Meta].
@immutable
class Endpoints {
  final String group;
  final String prefix;

  const Endpoints({required this.group, required this.prefix});

  factory Endpoints.fromJson(Map<String, dynamic> json) => Endpoints(
        group: json['group'] as String? ?? '',
        prefix: json['prefix'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'group': group, 'prefix': prefix};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Endpoints && other.group == group && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(group, prefix);

  @override
  String toString() => 'Endpoints(group: $group, prefix: $prefix)';
}

/// The shape of `/meta.json`.
@immutable
class Meta {
  final String version;
  final String generatedAt;
  final String specVersion;
  final int totalZipcodes;
  final int prefixCount;
  final Map<String, int> byPref;
  final String dataSource;
  final Endpoints endpoints;

  const Meta({
    required this.version,
    required this.generatedAt,
    required this.specVersion,
    required this.totalZipcodes,
    required this.prefixCount,
    required this.byPref,
    required this.dataSource,
    required this.endpoints,
  });

  factory Meta.fromJson(Map<String, dynamic> json) {
    final rawByPref = json['by_pref'] as Map<String, dynamic>? ?? const {};
    return Meta(
      version: json['version'] as String? ?? '',
      generatedAt: json['generated_at'] as String? ?? '',
      specVersion: json['spec_version'] as String? ?? '',
      totalZipcodes: (json['total_zipcodes'] as num?)?.toInt() ?? 0,
      prefixCount: (json['prefix_count'] as num?)?.toInt() ?? 0,
      byPref: rawByPref.map((k, v) => MapEntry(k, (v as num).toInt())),
      dataSource: json['data_source'] as String? ?? '',
      endpoints: Endpoints.fromJson(
        json['endpoints'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'generated_at': generatedAt,
        'spec_version': specVersion,
        'total_zipcodes': totalZipcodes,
        'prefix_count': prefixCount,
        'by_pref': byPref,
        'data_source': dataSource,
        'endpoints': endpoints.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Meta &&
          other.version == version &&
          other.generatedAt == generatedAt &&
          other.specVersion == specVersion &&
          other.totalZipcodes == totalZipcodes &&
          other.prefixCount == prefixCount &&
          other.dataSource == dataSource &&
          other.endpoints == endpoints;

  @override
  int get hashCode => Object.hash(
        version,
        generatedAt,
        specVersion,
        totalZipcodes,
        prefixCount,
        dataSource,
        endpoints,
      );

  @override
  String toString() =>
      'Meta(version: $version, totalZipcodes: $totalZipcodes, specVersion: $specVersion)';
}

/// The error thrown for prefixes that aren't 1-3 digits.
class InvalidPrefixError extends ArgumentError {
  InvalidPrefixError(String prefix)
      : super.value(prefix, 'prefix', 'must be 1-3 digits');
}
