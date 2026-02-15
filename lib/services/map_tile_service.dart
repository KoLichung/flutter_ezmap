import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/map_package.dart';

// 日志辅助函数，添加时间戳
void _log(String message) {
  final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
  debugPrint('[$timestamp] $message');
}

class MapTileService {
  static const String _mapsFolderName = 'offline_maps';
  static const String _dbFileName = 'map_packages.db';
  static const String _tableName = 'map_packages';
  
  static Database? _database;
  
  // 地图磁砖 URL
  // 使用两层地图：
  // 1. OpenStreetMap (底图): https://tile.openstreetmap.org/{z}/{x}/{y}.png
  // 2. Waymarked Trails (步道): https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png
  static const String _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _trailsUrl = 'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png';
  
  // 获取数据库实例
  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDocDir.path}/$_dbFileName';
    
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) {
        db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            north REAL NOT NULL,
            south REAL NOT NULL,
            east REAL NOT NULL,
            west REAL NOT NULL,
            minZoom INTEGER NOT NULL,
            maxZoom INTEGER NOT NULL,
            filePath TEXT NOT NULL,
            fileSize INTEGER NOT NULL,
            downloadedAt INTEGER NOT NULL,
            mapType TEXT NOT NULL
          )
        ''');
      },
    );
    
    return _database!;
  }
  
  // 获取地图包存储目录
  static Future<Directory> _getMapsDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final mapsDir = Directory('${appDocDir.path}/$_mapsFolderName');
    
    if (!await mapsDir.exists()) {
      await mapsDir.create(recursive: true);
    }
    
    return mapsDir;
  }
  
  // 获取所有已下载的地图包
  static Future<List<MapPackage>> getAllMapPackages() async {
    try {
      final db = await database;
      final maps = await db.query(_tableName, orderBy: 'downloadedAt DESC');
      
      _log('[MapTileService] 从数据库读取到 ${maps.length} 个地图包记录');
      
      // 获取当前应用的文档目录（用于修复路径）
      final currentMapsDir = await _getMapsDirectory();
      _log('[MapTileService] 当前地图包目录: ${currentMapsDir.path}');
      
      final packages = <MapPackage>[];
      for (var map in maps) {
        try {
          var package = MapPackage.fromMap(map);
          
          // 检查文件是否存在，如果不存在，尝试修复路径
          final file = File(package.filePath);
          if (!await file.exists()) {
            // 从原始路径提取文件名（例如：1767159401069.mbtiles）
            final fileName = package.filePath.split('/').last;
            final newPath = '${currentMapsDir.path}/$fileName';
            _log('[MapTileService] 地图包 "${package.name}" 原始路径不存在: ${package.filePath}');
            _log('[MapTileService] 尝试新路径: $newPath');
            
            final newFile = File(newPath);
            if (await newFile.exists()) {
              _log('[MapTileService] 在新路径找到文件，更新地图包路径');
              
              // 更新数据库中的路径
              try {
                await db.update(
                  _tableName,
                  {'filePath': newPath},
                  where: 'id = ?',
                  whereArgs: [package.id],
                );
                _log('[MapTileService] 已更新数据库中的文件路径');
              } catch (e) {
                _log('[MapTileService] 更新数据库路径失败: $e');
              }
              
              // 创建更新后的地图包对象
              package = MapPackage(
                id: package.id,
                name: package.name,
                bounds: package.bounds,
                minZoom: package.minZoom,
                maxZoom: package.maxZoom,
                filePath: newPath,
                fileSize: package.fileSize,
                downloadedAt: package.downloadedAt,
                mapType: package.mapType,
              );
            } else {
              _log('[MapTileService] 新路径也不存在，跳过此地图包');
              continue; // 跳过不存在的文件
            }
          }
          
          packages.add(package);
          _log('[MapTileService] 解析地图包: ${package.name}, 范围: ${package.bounds.south}°-${package.bounds.north}°N, ${package.bounds.west}°-${package.bounds.east}°E');
        } catch (e) {
          _log('[MapTileService] 解析地图包失败: $e, 数据: $map');
        }
      }
      
      return packages;
    } catch (e, stackTrace) {
      _log('[MapTileService] 获取地图包列表错误: $e');
      _log('[MapTileService] 堆栈: $stackTrace');
      return [];
    }
  }
  
  // 获取指定位置的地图包（检查是否有覆盖该位置的地图包）
  static Future<MapPackage?> getMapPackageForLocation(LatLng location) async {
    _log('[MapTileService] 查找位置的地图包: ${location.latitude}°, ${location.longitude}°');
    
    final packages = await getAllMapPackages();
    _log('[MapTileService] 找到 ${packages.length} 个地图包');
    
    // 获取当前应用的文档目录（用于修复路径）
    final currentMapsDir = await _getMapsDirectory();
    _log('[MapTileService] 当前地图包目录: ${currentMapsDir.path}');
    
    for (var i = 0; i < packages.length; i++) {
      final package = packages[i];
      _log('[MapTileService] 检查地图包 $i: ${package.name}');
      _log('[MapTileService]   范围: ${package.bounds.south}°-${package.bounds.north}°N, ${package.bounds.west}°-${package.bounds.east}°E');
      _log('[MapTileService]   原始文件路径: ${package.filePath}');
      
      // 检查文件是否存在（先检查原始路径）
      File file = File(package.filePath);
      bool fileExists = await file.exists();
      
      // 如果文件不存在，尝试使用当前应用的文档目录重新构建路径
      if (!fileExists) {
        // 从原始路径提取文件名（例如：1767159401069.mbtiles）
        final fileName = package.filePath.split('/').last;
        final newPath = '${currentMapsDir.path}/$fileName';
        _log('[MapTileService]   原始路径不存在，尝试新路径: $newPath');
        
        final newFile = File(newPath);
        if (await newFile.exists()) {
          _log('[MapTileService]   在新路径找到文件，更新地图包路径');
          file = newFile;
          fileExists = true;
          
          // 更新数据库中的路径
          try {
            final db = await database;
            await db.update(
              _tableName,
              {'filePath': newPath},
              where: 'id = ?',
              whereArgs: [package.id],
            );
            _log('[MapTileService]   已更新数据库中的文件路径');
          } catch (e) {
            _log('[MapTileService]   更新数据库路径失败: $e');
          }
        }
      }
      
      _log('[MapTileService]   文件存在: $fileExists');
      
      if (!fileExists) {
        _log('[MapTileService]   文件不存在，跳过');
        continue;
      }
      
      // 检查点是否在范围内
      final contains = package.containsPoint(location);
      _log('[MapTileService]   位置 ${location.latitude}°, ${location.longitude}° 在范围内: $contains');
      
      if (contains) {
        _log('[MapTileService]   找到匹配的地图包: ${package.name}');
        
        // 如果路径已更新，返回更新后的地图包对象
        if (file.path != package.filePath) {
          final updatedPackage = MapPackage(
            id: package.id,
            name: package.name,
            bounds: package.bounds,
            minZoom: package.minZoom,
            maxZoom: package.maxZoom,
            filePath: file.path,
            fileSize: package.fileSize,
            downloadedAt: package.downloadedAt,
            mapType: package.mapType,
          );
          return updatedPackage;
        }
        
        return package;
      } else {
        _log('[MapTileService]   位置不在范围内，继续查找');
      }
    }
    
    _log('[MapTileService] 未找到匹配的地图包');
    return null;
  }
  
  // 删除地图包
  static Future<bool> deleteMapPackage(String id) async {
    try {
      final db = await database;
      final packages = await getAllMapPackages();
      final package = packages.firstWhere((p) => p.id == id);
      
      // 删除文件
      final file = File(package.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // 删除数据库记录
      await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
      
      return true;
    } catch (e) {
      debugPrint('Error deleting map package: $e');
      return false;
    }
  }
  
  // 下载地图包（创建 MBTiles）
  static Future<MapPackage?> downloadMapPackage({
    required String name,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required MapType mapType,
    required Function(double progress) onProgress,
  }) async {
    try {
      _log('[MapTileService] 开始下载地图包: $name');
      _log('[MapTileService] 范围: ${bounds.south}°-${bounds.north}°N, ${bounds.west}°-${bounds.east}°E');
      _log('[MapTileService] 缩放级别: $minZoom - $maxZoom');
      
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final mapsDir = await _getMapsDirectory();
      final filePath = '${mapsDir.path}/$id.mbtiles';
      
      _log('[MapTileService] 文件路径: $filePath');
      
      // 创建 MBTiles 数据库
      final mbtilesDb = await openDatabase(filePath, version: 1, onCreate: (db, version) {
        _log('[MapTileService] 创建 MBTiles 数据库表结构');
        db.execute('''
          CREATE TABLE tiles (
            zoom_level INTEGER NOT NULL,
            tile_column INTEGER NOT NULL,
            tile_row INTEGER NOT NULL,
            tile_data BLOB NOT NULL,
            PRIMARY KEY (zoom_level, tile_column, tile_row)
          )
        ''');
        
        db.execute('''
          CREATE TABLE metadata (
            name TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        
        // 插入元数据
        db.insert('metadata', {'name': 'name', 'value': name});
        db.insert('metadata', {'name': 'format', 'value': 'png'});
        db.insert('metadata', {'name': 'bounds', 'value': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}'});
        db.insert('metadata', {'name': 'minzoom', 'value': minZoom.toString()});
        db.insert('metadata', {'name': 'maxzoom', 'value': maxZoom.toString()});
      });
      
      // 计算需要下载的磁砖数量
      int totalTiles = 0;
      _log('[MapTileService] 计算磁砖数量...');
      for (int z = minZoom; z <= maxZoom; z++) {
        final tileBounds = _getTileBounds(bounds, z);
        final tilesAtZoom = (tileBounds['maxX']! - tileBounds['minX']! + 1) *
                           (tileBounds['maxY']! - tileBounds['minY']! + 1);
        totalTiles += tilesAtZoom;
        _log('[MapTileService] Zoom $z: ${tileBounds['minX']}-${tileBounds['maxX']}, ${tileBounds['minY']}-${tileBounds['maxY']} = $tilesAtZoom 个磁砖');
      }
      _log('[MapTileService] 总磁砖数量: $totalTiles');
      
      if (totalTiles == 0) {
        _log('[MapTileService] 错误: 磁砖数量为 0');
        await mbtilesDb.close();
        return null;
      }
      
      int downloadedTiles = 0;
      int successTiles = 0;
      int failedTiles = 0;
      int retryTiles = 0;
      final startTime = DateTime.now();
      int concurrency = 6; // 并发数量（降低以避免503错误）
      const int maxRetries = 3; // 最大重试次数
      const Duration retryDelay = Duration(milliseconds: 100); // 请求间隔
      
      // 收集所有需要下载的磁砖任务
      final List<Map<String, dynamic>> tileTasks = [];
      for (int z = minZoom; z <= maxZoom; z++) {
        final tileBounds = _getTileBounds(bounds, z);
        final minX = tileBounds['minX']!;
        final maxX = tileBounds['maxX']!;
        final minY = tileBounds['minY']!;
        final maxY = tileBounds['maxY']!;
        
        for (int x = minX; x <= maxX; x++) {
          for (int y = minY; y <= maxY; y++) {
            tileTasks.add({
              'z': z,
              'x': x,
              'y': y,
            });
          }
        }
      }
      
      _log('[MapTileService] 准备下载 ${tileTasks.length} 个磁砖，使用 $concurrency 个并发连接');
      
      // 并发下载函数（带重试机制）
      Future<void> downloadTile(Map<String, dynamic> task) async {
        final z = task['z'] as int;
        final x = task['x'] as int;
        final y = task['y'] as int;
        
        // 使用 OpenStreetMap URL（底图）
        final tmsY = (1 << z) - 1 - y;
        final url = _osmUrl
            .replaceAll('{z}', z.toString())
            .replaceAll('{x}', x.toString())
            .replaceAll('{y}', y.toString());  // OSM 使用标准 Y 坐标
        
        // 重试机制
        int retryCount = 0;
        bool success = false;
        
        while (retryCount <= maxRetries && !success) {
          try {
            // 添加请求间隔（避免请求过于密集）
            if (retryCount > 0) {
              // 指数退避：1秒、2秒、4秒
              final delay = Duration(milliseconds: 1000 * (1 << (retryCount - 1)));
              await Future.delayed(delay);
              retryTiles++;
            } else {
              // 首次请求也添加小延迟
              await Future.delayed(retryDelay);
            }
            
            final response = await http.get(Uri.parse(url));
            
            if (response.statusCode == 200) {
              await mbtilesDb.insert(
                'tiles',
                {
                  'zoom_level': z,
                  'tile_column': x,
                  'tile_row': y,
                  'tile_data': response.bodyBytes,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              successTiles++;
              success = true;
            } else if (response.statusCode == 404) {
              // 404 表示该磁砖不存在（可能是高缩放级别或边界区域）
              // 静默跳过，不记录为失败
              success = true; // 标记为成功，避免重试
            } else if (response.statusCode == 503) {
              // 503 错误：服务器过载，需要重试
              if (retryCount < maxRetries) {
                _log('[MapTileService] HTTP $z/$x/$y 503错误，重试 ${retryCount + 1}/$maxRetries');
                retryCount++;
                // 继续重试循环
              } else {
                _log('[MapTileService] HTTP $z/$x/$y 503错误，重试失败');
                failedTiles++;
                success = true; // 标记为完成（虽然失败），避免无限重试
              }
            } else {
              // 其他HTTP错误
              _log('[MapTileService] HTTP $z/$x/$y 失败: ${response.statusCode}');
              failedTiles++;
              success = true; // 不重试其他错误
            }
          } catch (e) {
            // 网络错误或其他异常
            if (retryCount < maxRetries) {
              _log('[MapTileService] 下载磁砖 $z/$x/$y 错误，重试 ${retryCount + 1}/$maxRetries: $e');
              retryCount++;
            } else {
              _log('[MapTileService] 下载磁砖 $z/$x/$y 错误，重试失败: $e');
              failedTiles++;
              success = true; // 标记为完成，避免无限重试
            }
          }
        }
        
        downloadedTiles++;
        // 每下载一个磁砖就更新进度
        final currentProgress = downloadedTiles / totalTiles;
        onProgress(currentProgress);
        
        // 每 50 个磁砖或完成时打印日志
        if (downloadedTiles % 50 == 0 || downloadedTiles == totalTiles) {
          final elapsed = DateTime.now().difference(startTime);
          final elapsedSeconds = elapsed.inSeconds;
          if (downloadedTiles > 0 && elapsedSeconds > 0) {
            final speed = downloadedTiles / elapsedSeconds;
            final remainingTiles = totalTiles - downloadedTiles;
            final estimatedSeconds = (remainingTiles / speed).toInt();
            final estimatedMinutes = estimatedSeconds ~/ 60;
            _log('[MapTileService] 进度: $downloadedTiles/$totalTiles (${(currentProgress * 100).toStringAsFixed(1)}%) | 已用时: ${elapsedSeconds}s | 速度: ${speed.toStringAsFixed(1)} tiles/s | 成功: $successTiles | 失败: $failedTiles | 重试: $retryTiles | 预估剩余: ${estimatedMinutes}分${estimatedSeconds % 60}秒');
          }
        }
      }
      
      // 并发下载控制
      int currentIndex = 0;
      final List<Future<void>> activeDownloads = [];
      
      while (currentIndex < tileTasks.length || activeDownloads.isNotEmpty) {
        // 启动新的下载任务直到达到并发限制
        while (activeDownloads.length < concurrency && currentIndex < tileTasks.length) {
          final task = tileTasks[currentIndex++];
          final future = downloadTile(task);
          
          // 使用 then 来移除完成的 future
          future.then((_) {
            activeDownloads.remove(future);
          }).catchError((_) {
            activeDownloads.remove(future);
          });
          
          activeDownloads.add(future);
        }
        
        // 等待至少一个任务完成
        if (activeDownloads.isNotEmpty) {
          await Future.any(activeDownloads);
        }
      }
      
      // 等待所有任务完成
      await Future.wait(activeDownloads);
      
      // 按缩放级别打印完成信息
      for (int z = minZoom; z <= maxZoom; z++) {
        final zoomTiles = tileTasks.where((t) => t['z'] == z).length;
        final zoomSuccess = tileTasks.where((t) => t['z'] == z && 
          (tileTasks.indexOf(t) < successTiles + failedTiles)).length;
        _log('[MapTileService] Zoom $z: $zoomSuccess/$zoomTiles 完成');
      }
      
      final totalElapsed = DateTime.now().difference(startTime);
      final successRate = totalTiles > 0 ? (successTiles / totalTiles * 100).toStringAsFixed(1) : '0.0';
      _log('[MapTileService] 下载完成: 成功 $successTiles, 失败 $failedTiles, 重试 $retryTiles, 总计 $downloadedTiles');
      _log('[MapTileService] 成功率: $successRate%');
      _log('[MapTileService] 总用时: ${totalElapsed.inMinutes}分${totalElapsed.inSeconds % 60}秒');
      
      await mbtilesDb.close();
      
      // 获取文件大小
      final file = File(filePath);
      final fileSize = await file.length();
      _log('[MapTileService] 文件大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      
      // 创建地图包对象
      final mapPackage = MapPackage(
        id: id,
        name: name,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        filePath: filePath,
        fileSize: fileSize,
        downloadedAt: DateTime.now(),
        mapType: mapType,
      );
      
      // 保存到数据库
      final db = await database;
      await db.insert(_tableName, mapPackage.toMap());
      
      _log('[MapTileService] 地图包保存完成');
      return mapPackage;
    } catch (e, stackTrace) {
      _log('[MapTileService] 下载地图包错误: $e');
      _log('[MapTileService] 堆栈跟踪: $stackTrace');
      return null;
    }
  }
  
  // 计算指定范围和缩放级别的磁砖边界
  static Map<String, int> _getTileBounds(LatLngBounds bounds, int zoom) {
    final minTile = _latLngToTile(bounds.south, bounds.west, zoom);
    final maxTile = _latLngToTile(bounds.north, bounds.east, zoom);
    
    // 确保 minX <= maxX, minY <= maxY
    final minX = math.min(minTile['x']!, maxTile['x']!);
    final maxX = math.max(minTile['x']!, maxTile['x']!);
    final minY = math.min(minTile['y']!, maxTile['y']!);
    final maxY = math.max(minTile['y']!, maxTile['y']!);
    
      _log('[MapTileService] Zoom $zoom 磁砖边界: X($minX-$maxX), Y($minY-$maxY)');
    
    return {
      'minX': minX,
      'maxX': maxX,
      'minY': minY,
      'maxY': maxY,
    };
  }
  
  // 将经纬度转换为磁砖坐标
  static Map<String, int> _latLngToTile(double lat, double lon, int zoom) {
    final n = 1 << zoom;
    final x = ((lon + 180) / 360 * n).floor();
    final latRad = lat * math.pi / 180;
    final y = ((1 - (math.log(math.tan(latRad) + (1 / math.cos(latRad))) / math.pi)) / 2 * n).floor();
    
    return {'x': x, 'y': y};
  }
}

