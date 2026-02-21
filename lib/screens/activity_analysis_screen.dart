import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

/// 活動分析頁面 - 顯示距離高度表、總時長等資訊
/// 目前使用假資料做 UI
class ActivityAnalysisScreen extends StatelessWidget {
  final String? activityName;
  final DateTime? startTime;
  final Duration? duration;
  final double? distance;
  final double? ascent;
  final double? descent;
  final List<Map<String, double>>? chartData;

  const ActivityAnalysisScreen({
    super.key,
    this.activityName,
    this.startTime,
    this.duration,
    this.distance,
    this.ascent,
    this.descent,
    this.chartData,
  });

  /// 假資料用於 UI 展示
  static List<Map<String, double>> get _dummyChartData => [
        {'distance': 0.0, 'elevation': 350.0},
        {'distance': 0.5, 'elevation': 420.0},
        {'distance': 1.0, 'elevation': 520.0},
        {'distance': 1.5, 'elevation': 680.0},
        {'distance': 2.0, 'elevation': 750.0},
        {'distance': 2.5, 'elevation': 820.0},
        {'distance': 3.0, 'elevation': 950.0},
        {'distance': 3.5, 'elevation': 880.0},
        {'distance': 4.0, 'elevation': 720.0},
        {'distance': 4.5, 'elevation': 650.0},
        {'distance': 5.0, 'elevation': 480.0},
      ];

  String _formatDuration(Duration? d) {
    if (d == null) return '--';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.green.shade700),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartData = this.chartData ?? _dummyChartData;
    final duration = this.duration ?? const Duration(hours: 2, minutes: 35);
    final distance = this.distance ?? 5.0;
    final ascent = this.ascent ?? 820.0;
    final descent = this.descent ?? 680.0;
    final startTime = this.startTime ?? DateTime.now().subtract(duration);
    final activityName = this.activityName ?? '活動記錄';

    final minElev = chartData.isEmpty
        ? 0.0
        : chartData.map((e) => e['elevation']!).reduce((a, b) => a < b ? a : b) - 50;
    final maxElev = chartData.isEmpty
        ? 1000.0
        : chartData.map((e) => e['elevation']!).reduce((a, b) => a > b ? a : b) + 50;
    final maxDist = chartData.isEmpty ? 5.0 : chartData.last['distance']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('活動分析'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 活動名稱
            Text(
              activityName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '開始時間: ${_formatDateTime(startTime)}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),

            // 統計數據
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
                      '總距離',
                      '${distance.toStringAsFixed(2)} km',
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.access_time,
                      '總時長',
                      _formatDuration(duration),
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.arrow_upward,
                      '爬升高度',
                      '${ascent.toStringAsFixed(0)} m',
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      Icons.arrow_downward,
                      '下降高度',
                      '${descent.toStringAsFixed(0)} m',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 距離-高度圖表
            if (chartData.isNotEmpty) ...[
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
                                spots: chartData
                                    .asMap()
                                    .entries
                                    .map((entry) => FlSpot(
                                          entry.value['distance']!,
                                          entry.value['elevation']!,
                                        ))
                                    .toList(),
                                isCurved: true,
                                color: Colors.green.shade700,
                                barWidth: 2,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.green.shade100.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                            minX: 0,
                            maxX: maxDist,
                            minY: minElev,
                            maxY: maxElev,
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
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
