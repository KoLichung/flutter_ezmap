import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import '../models/map_package.dart';

class MBTilesTileProvider extends TileProvider {
  final MapPackage mapPackage;
  Database? _database;

  MBTilesTileProvider({required this.mapPackage});

  Future<Database> getDatabase() async {
    if (_database != null) return _database!;
    
    final file = File(mapPackage.filePath);
    if (!await file.exists()) {
      debugPrint('[MBTilesTileProvider] MBTiles 文件不存在: ${mapPackage.filePath}');
      throw Exception('MBTiles file not found: ${mapPackage.filePath}');
    }
    
    debugPrint('[MBTilesTileProvider] 打开数据库: ${mapPackage.filePath}');
    _database = await openDatabase(mapPackage.filePath, readOnly: true);
    debugPrint('[MBTilesTileProvider] 数据库打开成功');
    return _database!;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    var z = coordinates.z.round();
    var x = coordinates.x.round();
    var y = coordinates.y.round();
    
    // Zoom level fallback：如果超出範圍，使用最接近的可用 zoom
    if (z > mapPackage.maxZoom) {
      // 超過最大 zoom，使用最大 zoom 並調整座標
      final zoomDiff = z - mapPackage.maxZoom;
      final scale = 1 << zoomDiff;
      z = mapPackage.maxZoom;
      x = x ~/ scale;
      y = y ~/ scale;
      debugPrint('[MBTilesTileProvider] Zoom fallback: ${coordinates.z.round()} → $z, 縮放座標 (x=$x, y=$y)');
    } else if (z < mapPackage.minZoom) {
      // 低於最小 zoom，使用最小 zoom
      z = mapPackage.minZoom;
      debugPrint('[MBTilesTileProvider] Zoom fallback: ${coordinates.z.round()} → $z');
    }
    
    debugPrint('[MBTilesTileProvider] 请求磁砖: z=$z, x=$x, y=$y');
    
    // 返回一个自定义的 ImageProvider
    return MBTilesImageProvider(
      mapPackage: mapPackage,
      tileProvider: this,
      x: x,
      y: y,
      z: z,
    );
  }
  
  // 将磁砖坐标转换为经纬度边界
  LatLngBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = 1 << z;
    final west = (x / n * 360) - 180;
    final east = ((x + 1) / n * 360) - 180;
    
    // 使用双曲正弦函数：sinh(x) = (e^x - e^(-x)) / 2
    double sinh(double x) {
      final expX = math.exp(x);
      final expNegX = math.exp(-x);
      return (expX - expNegX) / 2;
    }
    
    final north = (math.atan(sinh(math.pi * (1 - 2 * y / n))) * 180) / math.pi;
    final south = (math.atan(sinh(math.pi * (1 - 2 * (y + 1) / n))) * 180) / math.pi;
    
    return LatLngBounds(
      LatLng(south, west),
      LatLng(north, east),
    );
  }

  void dispose() {
    _database?.close();
    _database = null;
  }
}

// 自定义 ImageProvider 用于从 MBTiles 读取图片
class MBTilesImageProvider extends ImageProvider<MBTilesImageProvider> {
  final MapPackage mapPackage;
  final MBTilesTileProvider tileProvider; // 使用共享的 tile provider
  final int x;
  final int y;
  final int z;

  MBTilesImageProvider({
    required this.mapPackage,
    required this.tileProvider,
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  Future<MBTilesImageProvider> obtainKey(ImageConfiguration configuration) async {
    return this;
  }

  @override
  ImageStreamCompleter loadImage(MBTilesImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadTile() async {
    try {
      // 使用共享的数据库连接
      final db = await tileProvider.getDatabase();
      
      // MBTiles 使用 TMS 格式（Y 轴翻转）
      final tmsY = (1 << z) - 1 - y;
      
      debugPrint('[MBTilesTileProvider] 查询磁砖: z=$z, x=$x, y=$y (TMS y=$tmsY)');
      
      final result = await db.query(
        'tiles',
        where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [z, x, tmsY],
      );

      if (result.isEmpty) {
        debugPrint('[MBTilesTileProvider] 磁砖不存在: z=$z, x=$x, y=$y (TMS y=$tmsY)');
        throw Exception('Tile not found in MBTiles');
      }

      final tileData = result.first['tile_data'] as Uint8List;
      debugPrint('[MBTilesTileProvider] 成功加载磁砖: z=$z, x=$x, y=$y, 大小=${tileData.length} bytes');
      
      // 验证图片数据
      if (tileData.isEmpty) {
        debugPrint('[MBTilesTileProvider] 磁砖数据为空');
        throw Exception('Tile data is empty');
      }
      
      return await ui.instantiateImageCodec(tileData);
    } catch (e, stackTrace) {
      debugPrint('[MBTilesTileProvider] 加载磁砖错误: z=$z, x=$x, y=$y, 错误: $e');
      debugPrint('[MBTilesTileProvider] 堆栈: $stackTrace');
      // 重新抛出异常，让 flutter_map 处理
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MBTilesImageProvider &&
          runtimeType == other.runtimeType &&
          mapPackage.id == other.mapPackage.id &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(mapPackage.id, x, y, z);
}

