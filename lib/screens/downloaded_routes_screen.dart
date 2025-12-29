import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/map_provider.dart';
import '../services/gpx_service.dart';
import '../services/route_service.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'gpx_detail_screen.dart';

class DownloadedRoutesScreen extends StatefulWidget {
  const DownloadedRoutesScreen({super.key});

  @override
  State<DownloadedRoutesScreen> createState() => _DownloadedRoutesScreenState();
}

class _DownloadedRoutesScreenState extends State<DownloadedRoutesScreen> {
  List<RouteFile> _routes = [];
  bool _isLoading = true;
  final Map<String, double> _swipeOffsets = {}; // 記錄每個項目的滑動偏移量

  @override
  void initState() {
    super.initState();
    _loadRouteStats();
  }

  Future<void> _loadRouteStats() async {
    setState(() {
      _isLoading = true;
    });
    
    final routes = await RouteService.getAllRoutes();
    
    setState(() {
      _routes = routes;
      _isLoading = false;
    });
  }

  Future<void> _importGpxFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        
        // 顯示加載對話框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        try {
          // 匯入 GPX 檔案
          final savedPath = await RouteService.importGpxFile(filePath);
          
          if (mounted) {
            Navigator.pop(context); // 關閉加載對話框
            
            if (savedPath != null) {
              // 重新載入路線列表
              await _loadRouteStats();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已匯入「${result.files.single.name}」'),
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('匯入失敗'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('匯入時發生錯誤: $e'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選擇檔案時發生錯誤: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('已下載路線'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _importGpxFile,
            tooltip: '匯入 GPX 檔案',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _routes.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                return _buildRouteCard(_routes[index], index);
              },
            ),
    );
  }

  Widget _buildRouteCard(RouteFile route, int index) {
    final offset = _swipeOffsets[route.filePath] ?? 0.0;
    final showDelete = offset <= -80.0; // 滑動到 80px 顯示刪除按鈕
    
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < 0) {
          // 右滑（向左移動）
          setState(() {
            _swipeOffsets[route.filePath] = 
                (_swipeOffsets[route.filePath] ?? 0.0) + details.delta.dx;
            // 限制最大滑動距離為 80px
            if (_swipeOffsets[route.filePath]! < -80) {
              _swipeOffsets[route.filePath] = -80.0;
            }
            if (_swipeOffsets[route.filePath]! > 0) {
              _swipeOffsets[route.filePath] = 0.0;
            }
          });
        } else if (details.delta.dx > 0 && offset < 0) {
          // 左滑恢復（向右移動）
          setState(() {
            _swipeOffsets[route.filePath] = 
                (_swipeOffsets[route.filePath] ?? 0.0) + details.delta.dx;
            if (_swipeOffsets[route.filePath]! > 0) {
              _swipeOffsets[route.filePath] = 0.0;
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        // 滑動結束時，如果滑動距離不夠，自動恢復
        final currentOffset = _swipeOffsets[route.filePath] ?? 0.0;
        if (currentOffset > -80) {
          setState(() {
            _swipeOffsets[route.filePath] = 0.0;
          });
        } else {
          // 如果超過一半，自動滑動到 80px
          setState(() {
            _swipeOffsets[route.filePath] = -80.0;
          });
        }
      },
      child: Stack(
        children: [
          // 刪除按鈕背景（固定在右側 80px）
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 80,
            child: Container(
              color: Colors.red.shade400,
              alignment: Alignment.center,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _showDeleteConfirmDialog(route, index);
                  },
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          // 內容卡片
          Transform.translate(
            offset: Offset(offset, 0),
            child: InkWell(
              onTap: () {
                // 如果正在顯示刪除按鈕，先恢復
                if (showDelete) {
                  setState(() {
                    _swipeOffsets[route.filePath] = 0.0;
                  });
                } else {
                  _navigateToDetail(route);
                }
              },
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    // 路線圖標
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.terrain,
                        size: 24,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // 路線信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                route.distance ?? '計算中...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                route.duration ?? '--',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_upward,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                route.elevation,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // 箭頭圖標
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(RouteFile route, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除路線'),
        content: Text('確定要刪除「${route.name}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRoute(route, index);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoute(RouteFile route, int index) async {
    // 刪除檔案
    final success = await RouteService.deleteRoute(route.filePath);
    
    if (success) {
      // 恢復滑動位置並從列表中移除
      setState(() {
        _swipeOffsets.remove(route.filePath);
        _routes.removeAt(index);
      });
      
      // 顯示刪除提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已刪除「${route.name}」'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // 刪除失敗
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刪除「${route.name}」失敗'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _navigateToDetail(RouteFile route) async {
    // 轉換為 RouteItem 格式
    final routeItem = RouteItem(
      name: route.name,
      filename: route.filePath,
      distance: route.distance,
      duration: route.duration,
      elevation: route.elevation,
    );
    
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => GpxDetailScreen(route: routeItem),
      ),
    );
    
    // 如果返回 true，表示需要切換到旅程 tab，將結果傳遞回上一頁
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
    
    // 重新載入路線列表（以防有更新）
    if (mounted) {
      await _loadRouteStats();
    }
  }

  Future<void> _loadAndDisplayRoute(RouteFile route) async {
    // 顯示加載對話框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 加載 GPX 文件
      final gpx = await GpxService.loadGpxFromFile(route.filePath);
      
      if (gpx == null) {
        if (mounted) {
          Navigator.pop(context); // 關閉加載對話框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法加載路線文件')),
          );
        }
        return;
      }

      // 獲取路線點
      final points = GpxService.getAllPoints(gpx);
      
      if (points.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('路線文件中沒有軌跡數據')),
          );
        }
        return;
      }

      // 計算中心點和邊界
      final center = GpxService.getCenter(points);
      final bounds = GpxService.calculateBounds(points);

      if (center == null || bounds == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法計算路線範圍')),
          );
        }
        return;
      }

      // 更新 MapProvider
      if (mounted) {
        final mapProvider = context.read<MapProvider>();
        mapProvider.loadGpxRoute(points, center, bounds);

        // 關閉加載對話框
        Navigator.pop(context);

        // 顯示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已載入路線: ${route.name}')),
        );

        // 返回到"我的"页面，并告知需要切换到旅程 tab
        Navigator.pop(context, true); // 返回 true 表示需要切换 tab
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加載路線時發生錯誤: $e')),
        );
      }
    }
  }
}

class RouteItem {
  final String name;
  final String filename;
  final String? distance;
  final String? duration;
  final String elevation;
  final String? imageUrl;

  RouteItem({
    required this.name,
    required this.filename,
    this.distance,
    this.duration,
    required this.elevation,
    this.imageUrl,
  });
}

