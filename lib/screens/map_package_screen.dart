import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/map_package.dart';
import '../services/map_tile_service.dart';

class MapPackageScreen extends StatefulWidget {
  const MapPackageScreen({super.key});

  @override
  State<MapPackageScreen> createState() => _MapPackageScreenState();
}

class _MapPackageScreenState extends State<MapPackageScreen> {
  List<MapPackage> _mapPackages = [];
  bool _isLoading = true;
  Map<String, double> _downloadProgress = {}; // 下载进度
  Map<String, bool> _isDownloading = {}; // 是否正在下载

  @override
  void initState() {
    super.initState();
    _loadMapPackages();
  }

  Future<void> _loadMapPackages() async {
    setState(() => _isLoading = true);
    final packages = await MapTileService.getAllMapPackages();
    setState(() {
      _mapPackages = packages;
      _isLoading = false;
    });
  }

  Future<void> _deleteMapPackage(MapPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除地圖包'),
        content: Text('確定要刪除「${package.name}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await MapTileService.deleteMapPackage(package.id);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已刪除地圖包')),
        );
        _loadMapPackages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刪除失敗')),
        );
      }
    }
  }

  void _showDownloadDialog() {
    final nameController = TextEditingController();
    LatLngBounds? selectedBounds;
    int minZoom = 10;
    int maxZoom = 14;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('下載地圖包'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '地圖包名稱',
                    hintText: '例如：台灣北部山區',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('地圖範圍（預設：台灣全島）', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '北緯: 25.3°\n南緯: 21.9°\n東經: 122.0°\n西經: 119.3°',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                const Text('縮放級別', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('最小: $minZoom'),
                          Slider(
                            value: minZoom.toDouble(),
                            min: 8,
                            max: 12,
                            divisions: 4,
                            label: minZoom.toString(),
                            onChanged: (value) {
                              setDialogState(() {
                                minZoom = value.toInt();
                                if (minZoom >= maxZoom) {
                                  maxZoom = minZoom + 1;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('最大: $maxZoom'),
                          Slider(
                            value: maxZoom.toDouble(),
                            min: 10,
                            max: 15, // 限制最大缩放级别为 15，避免太多 404 错误
                            divisions: 5,
                            label: maxZoom.toString(),
                            onChanged: (value) {
                              setDialogState(() {
                                maxZoom = value.toInt();
                                if (maxZoom <= minZoom) {
                                  minZoom = maxZoom - 1;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '預估大小: ${_estimateSize(minZoom, maxZoom)}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請輸入地圖包名稱')),
                  );
                  return;
                }

                // 使用台灣全島範圍
                selectedBounds = LatLngBounds(
                  const LatLng(21.9, 119.3), // 西南角
                  const LatLng(25.3, 122.0), // 東北角
                );

                Navigator.pop(context);
                _downloadMapPackage(
                  name: nameController.text.trim(),
                  bounds: selectedBounds!,
                  minZoom: minZoom,
                  maxZoom: maxZoom,
                );
              },
              child: const Text('開始下載'),
            ),
          ],
        ),
      ),
    );
  }

  String _estimateSize(int minZoom, int maxZoom) {
    // 粗略估算：台灣全島範圍，每個磁砖约 20KB
    // 實際計算：台灣範圍約 3.4° x 2.7°
    int totalTiles = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      // 計算台灣範圍的磁砖數量
      // 經度範圍：119.3° - 122.0° = 2.7°
      // 緯度範圍：21.9° - 25.3° = 3.4°
      final n = 1 << z;
      final lonTiles = ((122.0 - 119.3) / 360 * n).ceil();
      final latTiles = ((25.3 - 21.9) / 180 * n).ceil();
      totalTiles += lonTiles * latTiles;
    }
    final sizeMB = (totalTiles * 20 / 1024).toStringAsFixed(1);
    final estimatedTime = (totalTiles * 0.02 / 60).toStringAsFixed(0); // 假設每個磁砖 20ms
    return '約 $sizeMB MB，預估時間 ${estimatedTime} 分鐘';
  }

  Future<void> _downloadMapPackage({
    required String name,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    final downloadId = DateTime.now().millisecondsSinceEpoch.toString();
    
    debugPrint('[MapPackageScreen] 开始下载，downloadId: $downloadId');
    
    setState(() {
      _isDownloading[downloadId] = true;
      _downloadProgress[downloadId] = 0.0;
    });
    
    debugPrint('[MapPackageScreen] setState 完成，_isDownloading: $_isDownloading, _downloadProgress: $_downloadProgress');

    try {
      final package = await MapTileService.downloadMapPackage(
        name: name,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        mapType: MapType.openTrailMap,
        onProgress: (progress) {
          debugPrint('[MapPackageScreen] onProgress 回调被调用: progress=$progress, downloadId=$downloadId, mounted=$mounted');
          
          // 确保在主线程更新 UI
          if (mounted) {
            debugPrint('[MapPackageScreen] Widget mounted，准备更新进度');
            // 直接使用 setState，不使用 addPostFrameCallback（避免延迟）
            setState(() {
              // 确保 _isDownloading 存在
              if (!_isDownloading.containsKey(downloadId)) {
                _isDownloading[downloadId] = true;
                debugPrint('[MapPackageScreen] 恢复 _isDownloading[$downloadId]');
              }
              _downloadProgress[downloadId] = progress;
              debugPrint('[MapPackageScreen] setState 完成，_downloadProgress[$downloadId]=$progress');
              debugPrint('[MapPackageScreen] 当前 _isDownloading: $_isDownloading');
              debugPrint('[MapPackageScreen] 当前 _downloadProgress: $_downloadProgress');
            });
          } else {
            debugPrint('[MapPackageScreen] Widget 未 mounted，跳过更新');
          }
        },
      );

      setState(() {
        _isDownloading.remove(downloadId);
        _downloadProgress.remove(downloadId);
      });

      if (package != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下載地圖包：${package.name}')),
        );
        _loadMapPackages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下載失敗')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading.remove(downloadId);
        _downloadProgress.remove(downloadId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下載錯誤：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('地圖包管理'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showDownloadDialog,
            tooltip: '下載地圖包',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mapPackages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '尚未下載任何地圖包',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _showDownloadDialog,
                        icon: const Icon(Icons.download),
                        label: const Text('下載地圖包'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 下载进度显示
                    Builder(
                      builder: (context) {
                        debugPrint('[MapPackageScreen] build 进度条区域，_isDownloading.isEmpty: ${_isDownloading.isEmpty}');
                        debugPrint('[MapPackageScreen] _isDownloading keys: ${_isDownloading.keys.toList()}');
                        debugPrint('[MapPackageScreen] _downloadProgress keys: ${_downloadProgress.keys.toList()}');
                        
                        if (_isDownloading.isNotEmpty) {
                          debugPrint('[MapPackageScreen] 显示进度条');
                          return Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.blue.shade50,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _isDownloading.keys.map((id) {
                                final progress = _downloadProgress[id] ?? 0.0;
                                debugPrint('[MapPackageScreen] 渲染进度条，id=$id, progress=$progress');
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          '下載中...',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          '${(progress * 100).toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.grey.shade300,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade700),
                                      minHeight: 8,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '請保持 App 在前台，下載可能需要較長時間',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          );
                        } else {
                          debugPrint('[MapPackageScreen] 不显示进度条（_isDownloading 为空）');
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                    
                    // 地图包列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _mapPackages.length,
                        itemBuilder: (context, index) {
                          final package = _mapPackages[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.map,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              title: Text(
                                package.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('範圍: ${package.bounds.south.toStringAsFixed(2)}° - ${package.bounds.north.toStringAsFixed(2)}°'),
                                  Text('縮放: ${package.minZoom} - ${package.maxZoom}'),
                                  Text('大小: ${package.formattedSize}'),
                                  Text(
                                    '下載時間: ${package.downloadedAt.toString().substring(0, 16)}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteMapPackage(package),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

