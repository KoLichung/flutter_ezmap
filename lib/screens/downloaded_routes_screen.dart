import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../services/gpx_service.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

class DownloadedRoutesScreen extends StatefulWidget {
  const DownloadedRoutesScreen({super.key});

  @override
  State<DownloadedRoutesScreen> createState() => _DownloadedRoutesScreenState();
}

class _DownloadedRoutesScreenState extends State<DownloadedRoutesScreen> {
  List<RouteItem> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRouteStats();
  }

  Future<void> _loadRouteStats() async {
    final routes = <RouteItem>[];
    
    // 加载合歡東峰路线统计
    final gpx = await GpxService.loadGpxFromAssets('lib/test_files/合歡東峰.gpx');
    if (gpx != null) {
      final stats = GpxService.getRouteStats(gpx);
      
      // 格式化时长
      String durationStr = '--';
      if (stats['duration'] != null) {
        final duration = stats['duration'] as Duration;
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        durationStr = '${hours}h${minutes}m';
      }
      
      routes.add(RouteItem(
        name: '合歡東峰',
        filename: 'lib/test_files/合歡東峰.gpx',
        distance: '${stats['distance'].toStringAsFixed(2)}km',
        duration: durationStr,
        elevation: '${stats['ascent'].toStringAsFixed(0)}m', // 移除箭头，因为UI已经有箭头图标
        imageUrl: null,
      ));
    }
    
    setState(() {
      _routes = routes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('已下載路線'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _routes.length,
              itemBuilder: (context, index) {
                return _buildRouteCard(_routes[index]);
              },
            ),
    );
  }

  Widget _buildRouteCard(RouteItem route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _loadAndDisplayRoute(route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 路線圖標
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.terrain,
                  size: 40,
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          route.distance ?? '計算中...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          route.duration ?? '--',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.arrow_upward,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          route.elevation,
                          style: TextStyle(
                            fontSize: 14,
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
    );
  }

  Future<void> _loadAndDisplayRoute(RouteItem route) async {
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
      final gpx = await GpxService.loadGpxFromAssets(route.filename);
      
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

