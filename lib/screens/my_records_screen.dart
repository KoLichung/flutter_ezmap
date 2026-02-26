import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/map_provider.dart';
import '../services/gpx_service.dart';
import '../services/route_service.dart';
import 'downloaded_routes_screen.dart';
import 'gpx_detail_screen.dart';

class MyRecordsScreen extends StatefulWidget {
  const MyRecordsScreen({super.key});

  @override
  State<MyRecordsScreen> createState() => _MyRecordsScreenState();
}

class _MyRecordsScreenState extends State<MyRecordsScreen> {
  List<RouteFile> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final records = await RouteService.getMyRecords();
    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  void _navigateToDetail(RouteFile record) async {
    final routeItem = RouteItem(
      name: record.name,
      filename: record.filePath,
      distance: record.distance,
      duration: record.duration,
      elevation: record.elevation,
    );

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => GpxDetailScreen(route: routeItem),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
    if (mounted) await _loadRecords();
  }

  Future<void> _exportGpx(RouteFile record) async {
    try {
      final file = File(record.filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(record.filePath)],
          text: 'GPX 紀錄: ${record.name}',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('檔案不存在')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出失敗: $e')),
        );
      }
    }
  }

  Future<void> _loadToMap(RouteFile record) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final gpx = await GpxService.loadGpxFromFile(record.filePath);
      if (gpx == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法加載路線文件')),
          );
        }
        return;
      }

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

      if (mounted) {
        final stats = GpxService.getRouteStats(gpx);
        final smoothedPoints =
            stats['smoothedPoints'] as List<Map<String, dynamic>>;
        final routeInfo = GpxRouteInfo(
          name: record.name,
          distanceKm: (stats['distance'] as num).toDouble(),
          ascentM: (stats['ascent'] as num).toDouble(),
          descentM: (stats['descent'] as num).toDouble(),
          duration: stats['duration'] as Duration?,
          chartData: GpxService.getChartDataWithLocation(smoothedPoints),
        );
        context.read<MapProvider>().loadGpxRoute(
          points,
          center,
          bounds,
          routeInfo: routeInfo,
        );
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已載入路線: ${record.name}')),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的紀錄'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        '尚無紀錄',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '開始記錄後，儲存的軌跡會顯示在這裡',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _records.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    return _buildRecordCard(_records[index]);
                  },
                ),
    );
  }

  Widget _buildRecordCard(RouteFile record) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        record.name,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (record.distance != null)
              Text(
                record.distance!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (record.duration != null) ...[
              const SizedBox(width: 12),
              Text(
                record.duration!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(width: 12),
            Text(
              record.elevation,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _exportGpx(record),
            tooltip: 'GPX 匯出',
          ),
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => _loadToMap(record),
            tooltip: '載入地圖',
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.grey.shade400,
          ),
        ],
      ),
      onTap: () => _navigateToDetail(record),
    );
  }
}
