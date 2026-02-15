import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

enum MapType {
  openTrailMap, // OpenTrailMap (步道地图)
}

class MapPackage {
  final String id;
  final String name;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String filePath;
  final int fileSize; // bytes
  final DateTime downloadedAt;
  final MapType mapType;

  MapPackage({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.filePath,
    required this.fileSize,
    required this.downloadedAt,
    required this.mapType,
  });

  // 转换为 Map（用于存储到数据库）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'north': bounds.north,
      'south': bounds.south,
      'east': bounds.east,
      'west': bounds.west,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'filePath': filePath,
      'fileSize': fileSize,
      'downloadedAt': downloadedAt.millisecondsSinceEpoch,
      'mapType': mapType.name,
    };
  }

  // 从 Map 创建（从数据库读取）
  factory MapPackage.fromMap(Map<String, dynamic> map) {
    return MapPackage(
      id: map['id'] as String,
      name: map['name'] as String,
      bounds: LatLngBounds(
        LatLng(map['south'] as double, map['west'] as double),
        LatLng(map['north'] as double, map['east'] as double),
      ),
      minZoom: map['minZoom'] as int,
      maxZoom: map['maxZoom'] as int,
      filePath: map['filePath'] as String,
      fileSize: map['fileSize'] as int,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(map['downloadedAt'] as int),
      mapType: MapType.values.firstWhere(
        (e) => e.name == map['mapType'],
        orElse: () => MapType.openTrailMap,
      ),
    );
  }

  // 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  // 检查点是否在地图包范围内
  bool containsPoint(LatLng point) {
    // 手动检查范围（更可靠）
    final latInRange = point.latitude >= bounds.south && point.latitude <= bounds.north;
    final lonInRange = point.longitude >= bounds.west && point.longitude <= bounds.east;
    final result = latInRange && lonInRange;
    
    debugPrint('[MapPackage] 检查点: ${point.latitude}°, ${point.longitude}°');
    debugPrint('[MapPackage]   地图包: $name');
    debugPrint('[MapPackage]   范围: ${bounds.south}°-${bounds.north}°N, ${bounds.west}°-${bounds.east}°E');
    debugPrint('[MapPackage]   纬度检查: ${point.latitude} >= ${bounds.south} && ${point.latitude} <= ${bounds.north} = $latInRange');
    debugPrint('[MapPackage]   经度检查: ${point.longitude} >= ${bounds.west} && ${point.longitude} <= ${bounds.east} = $lonInRange');
    debugPrint('[MapPackage]   结果: $result');
    
    return result;
  }
}

