import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 路徑點（用於 path_data 解析）
class PathPoint {
  final double lat;
  final double lon;
  final double elevation;

  PathPoint({required this.lat, required this.lon, required this.elevation});
}

/// 步道詳情（含 path_data 與計算後統計）
class TrailDetail {
  final int id;
  final String name;
  final double? lat;
  final double? lon;
  final double? distanceKm;
  final double? elevationGain;
  final double? elevationLoss;
  final List<PathPoint> pathPoints;
  final List<({double distanceKm, double elevation, double lat, double lon})> profileData;

  TrailDetail({
    required this.id,
    required this.name,
    this.lat,
    this.lon,
    this.distanceKm,
    this.elevationGain,
    this.elevationLoss,
    required this.pathPoints,
    required this.profileData,
  });
}

/// 搜尋結果項目：步道
class SearchItem {
  final int id;
  final String name;
  final double? lat;
  final double? lon;
  final double? distanceKm;
  final double? elevation;
  final String? tagName;

  /// 與使用者位置的距離（公里），無 GPS 時為 null
  double? distanceFromUser;

  SearchItem({
    required this.id,
    required this.name,
    this.lat,
    this.lon,
    this.distanceKm,
    this.elevation,
    this.tagName,
    this.distanceFromUser,
  });

  SearchItem copyWith({
    int? id,
    String? name,
    double? lat,
    double? lon,
    double? distanceKm,
    double? elevation,
    String? tagName,
    double? distanceFromUser,
  }) =>
      SearchItem(
        id: id ?? this.id,
        name: name ?? this.name,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        distanceKm: distanceKm ?? this.distanceKm,
        elevation: elevation ?? this.elevation,
        tagName: tagName ?? this.tagName,
        distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      );
}

class MountainDbService {
  static const String _assetPath = 'lib/resource/db.sqlite3';
  static const String _dbFileName = 'mountain_map.db';
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, _dbFileName);

    final file = File(dbPath);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(_assetPath);
      final bytes = byteData.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes);
    }

    _database = await openDatabase(dbPath, readOnly: true);
    return _database!;
  }

  /// 步道名稱 autocomplete（前綴匹配，最多 20 筆）
  static Future<List<String>> searchTrailNames(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    final q = '${query.trim()}%';
    final rows = await db.query(
      'mountain_map_trail',
      columns: ['trail_name'],
      where: 'trail_name LIKE ?',
      whereArgs: [q],
      orderBy: 'trail_name',
      limit: 20,
    );
    return rows.map((r) => r['trail_name'] as String).toList();
  }

  /// 步道名稱 autocomplete 建議（最多 20 筆）
  static Future<List<String>> searchSuggestions(String query) async {
    return searchTrailNames(query);
  }

  /// 依標籤搜尋步道（百岳、小百岳）
  static Future<List<SearchItem>> searchTrailsByTag(String tagName) async {
    final db = await database;
    final tagRows = await db.query(
      'mountain_map_tag',
      where: 'name = ?',
      whereArgs: [tagName],
    );
    if (tagRows.isEmpty) return [];

    final tagId = tagRows.first['id'] as int;
    final rows = await db.rawQuery('''
      SELECT t.id, t.trail_id, t.trail_name, t.center_lat, t.center_lon, t.distance_km, t.elevation_gain
      FROM mountain_map_trail t
      INNER JOIN mountain_map_trail_tags tt ON t.id = tt.trail_id
      WHERE tt.tag_id = ?
    ''', [tagId]);

    return rows.map((r) => SearchItem(
          id: r['id'] as int,
          name: r['trail_name'] as String,
          lat: (r['center_lat'] as num?)?.toDouble(),
          lon: (r['center_lon'] as num?)?.toDouble(),
          distanceKm: (r['distance_km'] as num?)?.toDouble(),
          elevation: (r['elevation_gain'] as num?)?.toDouble(),
          tagName: tagName,
        )).toList();
  }

  /// 依關鍵字搜尋步道
  static Future<List<SearchItem>> searchTrailsByKeyword(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final db = await database;
    final q = '%${keyword.trim()}%';
    final rows = await db.query(
      'mountain_map_trail',
      where: 'trail_name LIKE ?',
      whereArgs: [q],
      orderBy: 'trail_name',
    );
    return rows.map((r) => SearchItem(
          id: r['id'] as int,
          name: r['trail_name'] as String,
          lat: (r['center_lat'] as num?)?.toDouble(),
          lon: (r['center_lon'] as num?)?.toDouble(),
          distanceKm: (r['distance_km'] as num?)?.toDouble(),
          elevation: (r['elevation_gain'] as num?)?.toDouble(),
        )).toList();
  }

  /// 附近步道：依 center_lat, center_lon 取得所有步道
  static Future<List<SearchItem>> getNearbyTrails() async {
    final db = await database;
    final rows = await db.query(
      'mountain_map_trail',
      where: 'center_lat IS NOT NULL AND center_lon IS NOT NULL',
      orderBy: 'id',
    );
    return rows.map((r) => SearchItem(
          id: r['id'] as int,
          name: r['trail_name'] as String,
          lat: (r['center_lat'] as num?)?.toDouble(),
          lon: (r['center_lon'] as num?)?.toDouble(),
          distanceKm: (r['distance_km'] as num?)?.toDouble(),
          elevation: (r['elevation_gain'] as num?)?.toDouble(),
        )).toList();
  }

  /// 取得步道詳情（含 path_data 與計算後統計）
  static Future<TrailDetail?> getTrailDetail(int trailId) async {
    final db = await database;
    final rows = await db.query(
      'mountain_map_trail',
      where: 'id = ?',
      whereArgs: [trailId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final pathDataStr = r['path_data'] as String?;
    List<PathPoint> pathPoints = [];
    List<({double distanceKm, double elevation, double lat, double lon})> profileData = [];
    double? distanceKm;
    double? elevationGain;
    double? elevationLoss;

    if (pathDataStr != null && pathDataStr.isNotEmpty) {
      try {
        final list = jsonDecode(pathDataStr) as List;
        pathPoints = list.map((e) {
          final m = e as Map<String, dynamic>;
          final elev = m['elevation'] ?? m['ele'];
          return PathPoint(
            lat: (m['lat'] as num).toDouble(),
            lon: (m['lon'] as num).toDouble(),
            elevation: (elev != null ? (elev as num).toDouble() : 0),
          );
        }).toList();
        final calc = _calculateFromPath(pathPoints);
        distanceKm = calc.distanceKm;
        elevationGain = calc.elevationGain;
        elevationLoss = calc.elevationLoss;
        profileData = calc.profileData;
      } catch (_) {}
    }
    if (pathPoints.isEmpty) {
      distanceKm = (r['distance_km'] as num?)?.toDouble();
      elevationGain = (r['elevation_gain'] as num?)?.toDouble();
      elevationLoss = (r['elevation_loss'] as num?)?.toDouble();
    }
    return TrailDetail(
      id: r['id'] as int,
      name: r['trail_name'] as String,
      lat: (r['center_lat'] as num?)?.toDouble(),
      lon: (r['center_lon'] as num?)?.toDouble(),
      distanceKm: distanceKm,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      pathPoints: pathPoints,
      profileData: profileData,
    );
  }

  /// 從 path 計算：距離、爬升、下降
  /// 參考：距離閾值 1km 過濾跳躍點；高度變化 >= 20m 才算（過濾 GPS 誤差）
  static ({
    double distanceKm,
    double elevationGain,
    double elevationLoss,
    List<({double distanceKm, double elevation, double lat, double lon})> profileData,
  }) _calculateFromPath(List<PathPoint> points) {
    const maxJumpKm = 1.0; // 距離閾值，過濾跳躍點
    const elevationThreshold = 20.0; // 高度變化閾值（米），過濾 GPS 誤差

    double totalDistance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    final profile = <({double distanceKm, double elevation, double lat, double lon})>[];

    if (points.isEmpty) {
      return (
        distanceKm: 0,
        elevationGain: 0,
        elevationLoss: 0,
        profileData: [],
      );
    }

    final first = points.first;
    profile.add((distanceKm: 0, elevation: first.elevation, lat: first.lat, lon: first.lon));
    double? lastSignificantElevation =
        points.first.elevation > 0 ? points.first.elevation : null;
    double cumDist = 0;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final distance =
          _distanceKm(prev.lat, prev.lon, curr.lat, curr.lon);

      if (distance < maxJumpKm) {
        totalDistance += distance;
        cumDist += distance;

        final currElevation = curr.elevation > 0 ? curr.elevation : null;

        if (currElevation != null && lastSignificantElevation != null) {
          final elevDiff = currElevation - lastSignificantElevation;
          if (elevDiff.abs() >= elevationThreshold) {
            if (elevDiff > 0) {
              elevationGain += elevDiff;
            } else {
              elevationLoss += elevDiff.abs();
            }
            lastSignificantElevation = currElevation;
          }
        } else if (currElevation != null) {
          lastSignificantElevation = currElevation;
        }

        profile.add((distanceKm: cumDist, elevation: curr.elevation, lat: curr.lat, lon: curr.lon));
      }
    }

    return (
      distanceKm: totalDistance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      profileData: profile,
    );
  }

  /// 計算兩點距離（公里，Haversine）
  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // 地球半徑 km
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// 依使用者位置排序（有 GPS 時依距離，無則依 id）
  static void sortByDistance(
    List<SearchItem> items, {
    double? userLat,
    double? userLon,
  }) {
    if (userLat != null && userLon != null) {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (item.lat != null && item.lon != null) {
          items[i] = item.copyWith(
            distanceFromUser: _distanceKm(
              userLat,
              userLon,
              item.lat!,
              item.lon!,
            ),
          );
        }
      }
      items.sort((a, b) {
        final da = a.distanceFromUser ?? double.infinity;
        final db = b.distanceFromUser ?? double.infinity;
        return da.compareTo(db);
      });
    } else {
      items.sort((a, b) => a.id.compareTo(b.id));
    }
  }
}
