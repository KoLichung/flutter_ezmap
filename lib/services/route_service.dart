import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gpx/gpx.dart';
import 'gpx_service.dart';

class RouteService {
  static const String _routesFolderName = 'downloaded_routes';
  
  // 獲取路線文件夾路徑
  static Future<Directory> _getRoutesDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final routesDir = Directory('${appDocDir.path}/$_routesFolderName');
    
    if (!await routesDir.exists()) {
      await routesDir.create(recursive: true);
    }
    
    return routesDir;
  }
  
  // 獲取所有已下載的路線
  static Future<List<RouteFile>> getAllRoutes() async {
    try {
      final routesDir = await _getRoutesDirectory();
      final files = routesDir.listSync();
      
      final routes = <RouteFile>[];
      
      for (var file in files) {
        if (file is File && file.path.endsWith('.gpx')) {
          try {
            final gpx = await GpxService.loadGpxFromFile(file.path);
            if (gpx != null) {
              final stats = GpxService.getRouteStats(gpx);
              
              // 獲取檔名（不含路徑和副檔名）
              final fileName = file.path.split('/').last;
              final nameWithoutExt = fileName.replaceAll('.gpx', '');
              
              // 格式化時長
              String durationStr = '--';
              if (stats['duration'] != null) {
                final duration = stats['duration'] as Duration;
                final hours = duration.inHours;
                final minutes = duration.inMinutes % 60;
                durationStr = '${hours}h${minutes}m';
              }
              
              routes.add(RouteFile(
                name: nameWithoutExt,
                filePath: file.path,
                distance: '${stats['distance'].toStringAsFixed(2)}km',
                duration: durationStr,
                elevation: '${stats['ascent'].toStringAsFixed(0)}m',
                createdAt: await file.lastModified(),
              ));
            }
          } catch (e) {
            print('Error loading route ${file.path}: $e');
          }
        }
      }
      
      // 按創建時間排序（最新的在前）
      routes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return routes;
    } catch (e) {
      print('Error getting routes: $e');
      return [];
    }
  }
  
  // 保存 GPX 檔案
  static Future<String?> saveGpxFile(String fileName, String gpxContent) async {
    try {
      final routesDir = await _getRoutesDirectory();
      
      // 確保檔名以 .gpx 結尾
      if (!fileName.endsWith('.gpx')) {
        fileName = '$fileName.gpx';
      }
      
      final file = File('${routesDir.path}/$fileName');
      await file.writeAsString(gpxContent);
      
      return file.path;
    } catch (e) {
      print('Error saving GPX file: $e');
      return null;
    }
  }
  
  // 從檔案路徑保存 GPX 檔案
  static Future<String?> importGpxFile(String sourceFilePath) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        print('Source file does not exist: $sourceFilePath');
        return null;
      }
      
      final routesDir = await _getRoutesDirectory();
      final fileName = sourceFilePath.split('/').last;
      final targetFile = File('${routesDir.path}/$fileName');
      
      // 如果檔案已存在，添加時間戳
      if (await targetFile.exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final nameWithoutExt = fileName.replaceAll('.gpx', '');
        final newFileName = '${nameWithoutExt}_$timestamp.gpx';
        final newTargetFile = File('${routesDir.path}/$newFileName');
        await sourceFile.copy(newTargetFile.path);
        return newTargetFile.path;
      } else {
        await sourceFile.copy(targetFile.path);
        return targetFile.path;
      }
    } catch (e) {
      print('Error importing GPX file: $e');
      return null;
    }
  }
  
  // 刪除路線檔案
  static Future<bool> deleteRoute(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting route: $e');
      return false;
    }
  }
  
  // 檢查檔案是否存在
  static Future<bool> routeExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}

class RouteFile {
  final String name;
  final String filePath;
  final String? distance;
  final String? duration;
  final String elevation;
  final DateTime createdAt;

  RouteFile({
    required this.name,
    required this.filePath,
    this.distance,
    this.duration,
    required this.elevation,
    required this.createdAt,
  });
}

