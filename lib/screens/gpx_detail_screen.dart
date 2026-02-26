import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/gpx_service.dart';
import '../providers/map_provider.dart';
import 'downloaded_routes_screen.dart';

class GpxDetailScreen extends StatefulWidget {
  final RouteItem route;

  const GpxDetailScreen({super.key, required this.route});

  @override
  State<GpxDetailScreen> createState() => _GpxDetailScreenState();
}

class _GpxDetailScreenState extends State<GpxDetailScreen> {
  Gpx? _gpx;
  Map<String, dynamic>? _allStats;
  Map<String, Duration>? _dayGroups;
  List<Map<String, double>>? _allChartData;
  List<Map<String, dynamic>>? _allSmoothedPoints;
  DateTime? _creationTime;
  bool _isLoading = true;
  final TextEditingController _nameController = TextEditingController();
  double? _selectedDistance;
  double? _selectedElevation;
  
  // 選擇的時間段：null 表示總時間，數字表示第幾天（1-based）
  int? _selectedDayIndex;
  
  // 當前顯示的統計數據和圖表數據
  Map<String, dynamic>? _currentStats;
  List<Map<String, double>>? _currentChartData;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.route.name;
    _loadGpxData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadGpxData() async {
    try {
      // 判斷是從 assets 還是檔案系統讀取
      final gpx = widget.route.filename.startsWith('lib/')
          ? await GpxService.loadGpxFromAssets(widget.route.filename)
          : await GpxService.loadGpxFromFile(widget.route.filename);
      if (gpx == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法加載路線文件')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final stats = GpxService.getRouteStats(gpx);
      final smoothedPoints = stats['smoothedPoints'] as List<Map<String, dynamic>>;
      final dayGroups = GpxService.groupByDays(smoothedPoints);
      final chartData = GpxService.getDistanceElevationData(smoothedPoints);
      
      // 獲取建檔時間
      DateTime? creationTime;
      if (gpx.metadata?.time != null) {
        creationTime = gpx.metadata!.time;
      }

      setState(() {
        _gpx = gpx;
        _allStats = stats;
        _allSmoothedPoints = smoothedPoints;
        _dayGroups = dayGroups;
        _allChartData = chartData;
        _creationTime = creationTime;
        _selectedDayIndex = null; // 默認選擇總時間
        _updateDisplayedData();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加載路線時發生錯誤: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }
  
  // 根據選擇的時間段更新顯示的數據
  void _updateDisplayedData() {
    if (_allSmoothedPoints == null) return;
    
    print('=== _updateDisplayedData 開始 ===');
    print('選擇的時間段: ${_selectedDayIndex == null ? "總時間" : "第 $_selectedDayIndex 天"}');
    print('總點數: ${_allSmoothedPoints!.length}');
    
    List<Map<String, dynamic>> filteredPoints;
    
    if (_selectedDayIndex == null) {
      // 總時間：使用所有數據點
      filteredPoints = _allSmoothedPoints!;
      print('使用所有數據點: ${filteredPoints.length}');
    } else {
      // 選擇特定天：只使用該天的數據點
      filteredPoints = GpxService.getDayPoints(_allSmoothedPoints!, _selectedDayIndex!);
      print('過濾後的點數: ${filteredPoints.length}');
    }
    
    if (filteredPoints.isEmpty) {
      print('過濾後沒有數據點');
      setState(() {
        _currentStats = null;
        _currentChartData = [];
      });
      return;
    }
    
    // 重新計算統計數據
    final distance = GpxService.calculateTotalDistance(filteredPoints);
    final ascent = GpxService.calculateAscentWithThreshold(filteredPoints, 0.5);
    final descent = GpxService.calculateDescentWithThreshold(filteredPoints, 0.5);
    
    Duration? duration;
    if (filteredPoints.isNotEmpty && 
        filteredPoints.first['time'] != null && 
        filteredPoints.last['time'] != null) {
      duration = (filteredPoints.last['time'] as DateTime)
          .difference(filteredPoints.first['time'] as DateTime);
    }
    
    final stats = {
      'distance': distance,
      'ascent': ascent,
      'descent': descent,
      'duration': duration,
    };
    
    // 重新計算圖表數據
    final chartData = GpxService.getDistanceElevationData(filteredPoints);
    
    setState(() {
      _currentStats = stats;
      _currentChartData = chartData;
      _selectedDistance = null;
      _selectedElevation = null;
    });
  }
  
  // 顯示編輯檔名對話框
  void _showEditNameDialog() {
    final editController = TextEditingController(text: _nameController.text);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯檔名'),
        content: TextField(
          controller: editController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '輸入檔名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (editController.text.trim().isNotEmpty) {
                setState(() {
                  _nameController.text = editController.text.trim();
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _onChartTouch(FlTouchEvent event, LineTouchResponse? touchResponse) {
    if (_currentChartData == null || _currentChartData!.isEmpty) return;
    
    if (touchResponse != null && touchResponse.lineBarSpots != null && touchResponse.lineBarSpots!.isNotEmpty) {
      final spot = touchResponse.lineBarSpots!.first;
      // 找到最接近的數據點
      double minDistance = double.infinity;
      int closestIndex = 0;
      for (int i = 0; i < _currentChartData!.length; i++) {
        final distance = (spot.x - _currentChartData![i]['distance']!).abs();
        if (distance < minDistance) {
          minDistance = distance;
          closestIndex = i;
        }
      }
      
      if (closestIndex >= 0 && closestIndex < _currentChartData!.length) {
        setState(() {
          _selectedDistance = _currentChartData![closestIndex]['distance'];
          _selectedElevation = _currentChartData![closestIndex]['elevation'];
        });
      }
    } else {
      // 當手指離開時，清除選中狀態（可選）
      // setState(() {
      //   _selectedDistance = null;
      //   _selectedElevation = null;
      // });
    }
  }

  Future<void> _loadToMap() async {
    if (_gpx == null) return;

    // 顯示加載對話框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 獲取路線點
      final points = GpxService.getAllPoints(_gpx!);
      
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

      // 更新 MapProvider（含路線資訊供地圖顯示資訊面板）
      if (mounted) {
        final mapProvider = context.read<MapProvider>();
        final stats = _allStats!;
        final smoothedPoints =
            stats['smoothedPoints'] as List<Map<String, dynamic>>;
        final routeInfo = GpxRouteInfo(
          name: _nameController.text,
          distanceKm: (stats['distance'] as num).toDouble(),
          ascentM: (stats['ascent'] as num).toDouble(),
          descentM: (stats['descent'] as num).toDouble(),
          duration: stats['duration'] as Duration?,
          chartData: GpxService.getChartDataWithLocation(smoothedPoints),
        );
        mapProvider.loadGpxRoute(points, center, bounds, routeInfo: routeInfo);

        // 關閉加載對話框
        Navigator.pop(context);

        // 顯示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已載入路線: ${_nameController.text}')),
        );

        // 直接回到主地圖畫面
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('路線詳情'),
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_gpx == null || _allStats == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('路線詳情'),
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('無法加載路線數據')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('路線詳情'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 建檔時間
            if (_creationTime != null) ...[
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    '建檔時間: ${_formatDateTime(_creationTime!)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 檔名（完全顯示，尾字加上編輯 icon）
            Row(
              children: [
                Expanded(
                  child: Text(
                    _nameController.text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.visible,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: _showEditNameDialog,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 時間選擇器（只有當有多於一天時才顯示各天選項）
            if (_dayGroups != null && _dayGroups!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '時間選擇',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // 總時間選項
                          _buildTimeChip(
                            label: '總時間',
                            isSelected: _selectedDayIndex == null,
                            onTap: () {
                              print('=== 用戶選擇時間 ===');
                              print('選擇: 總時間');
                              print('總共有 ${_dayGroups!.length} 天');
                              setState(() {
                                _selectedDayIndex = null;
                              });
                              _updateDisplayedData();
                            },
                          ),
                          // 各天選項（只有當有多於一天時才顯示）
                          if (_dayGroups!.length > 1)
                            ..._dayGroups!.keys.toList().asMap().entries.map((entry) {
                              final dayIndex = entry.key + 1;
                              return _buildTimeChip(
                                label: entry.value,
                                isSelected: _selectedDayIndex == dayIndex,
                                onTap: () {
                                  print('=== 用戶選擇時間 ===');
                                  print('選擇: ${entry.value}');
                                  print('dayIndex: $dayIndex');
                                  print('總共有 ${_dayGroups!.length} 天');
                                  setState(() {
                                    _selectedDayIndex = dayIndex;
                                  });
                                  _updateDisplayedData();
                                },
                              );
                            }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 統計數據
            if (_currentStats != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '統計數據',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStatRow(
                        Icons.straighten,
                        '距離',
                        '${_currentStats!['distance'].toStringAsFixed(2)} km',
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        Icons.access_time,
                        '活動時間',
                        _currentStats!['duration'] != null
                            ? _formatDuration(_currentStats!['duration'] as Duration)
                            : '--',
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        Icons.arrow_upward,
                        '爬升高度',
                        '${_currentStats!['ascent'].toStringAsFixed(0)} m',
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        Icons.arrow_downward,
                        '下降高度',
                        '${_currentStats!['descent'].toStringAsFixed(0)} m',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 距離-高度圖表
            if (_currentChartData != null && _currentChartData!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '距離-高度圖表',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 250,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      '${value.toInt()}m',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      '${value.toStringAsFixed(1)}km',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: true),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _currentChartData!.asMap().entries.map((entry) {
                                  return FlSpot(
                                    entry.value['distance']!,
                                    entry.value['elevation']!,
                                  );
                                }).toList(),
                                isCurved: true,
                                color: Colors.green.shade700,
                                barWidth: 2,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.green.shade100.withOpacity(0.3),
                                ),
                              ),
                            ],
                            minX: 0,
                            maxX: _currentChartData!.last['distance']!,
                            minY: _currentChartData!.map((e) => e['elevation']!).reduce((a, b) => a < b ? a : b) - 50,
                            maxY: _currentChartData!.map((e) => e['elevation']!).reduce((a, b) => a > b ? a : b) + 50,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                  return touchedSpots.map((LineBarSpot touchedSpot) {
                                    return LineTooltipItem(
                                      '距離: ${touchedSpot.x.toStringAsFixed(2)} km\n高度: ${touchedSpot.y.toStringAsFixed(0)} m',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                              touchCallback: _onChartTouch,
                              handleBuiltInTouches: true,
                              enabled: true,
                            ),
                            extraLinesData: ExtraLinesData(
                              verticalLines: _selectedDistance != null
                                  ? [
                                      VerticalLine(
                                        x: _selectedDistance!,
                                        color: Colors.red.shade400,
                                        strokeWidth: 2,
                                        dashArray: [5, 5],
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                        ),
                      ),
                      // 顯示選中的距離和高度
                      if (_selectedDistance != null && _selectedElevation != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '距離: ${_selectedDistance!.toStringAsFixed(2)} km',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '高度: ${_selectedElevation!.toStringAsFixed(0)} m',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 顯示於離線地圖按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loadToMap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '顯示於離線地圖',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTimeChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade700 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.green.shade700 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

