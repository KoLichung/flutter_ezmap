import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/mountain_db_service.dart';

/// 步道資訊面板：從底部延伸、圓弧頂、拖曳線、X 關閉
class TrailInfoPanel extends StatefulWidget {
  final TrailDetail trail;
  final VoidCallback onClose;
  /// 高度表觸控時回調，傳入對應的 LatLng；鬆開時傳 null
  final void Function(LatLng? point)? onChartTouch;
  /// 強制收縮至最低高度（例如測距模式時）
  final bool collapsed;

  const TrailInfoPanel({
    super.key,
    required this.trail,
    required this.onClose,
    this.onChartTouch,
    this.collapsed = false,
  });

  @override
  State<TrailInfoPanel> createState() => _TrailInfoPanelState();
}

class _TrailInfoPanelState extends State<TrailInfoPanel> {
  static const double _minHeight = 60;
  static const double _maxHeight = 320;

  double _panelHeight = _maxHeight;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onVerticalDragUpdate: widget.collapsed
            ? null
            : (d) {
                setState(() {
                  _panelHeight =
                      (_panelHeight - d.delta.dy).clamp(_minHeight, _maxHeight);
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: widget.collapsed ? _minHeight : _panelHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
              child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: !widget.collapsed && _panelHeight > 100
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStats(),
                            if (widget.trail.profileData.length > 1) ...[
                              const SizedBox(height: 16),
                              _buildChart(),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            top: -5,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final t = widget.trail;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatItem(
          label: '步道長度',
          value: t.distanceKm != null
              ? '${t.distanceKm!.toStringAsFixed(1)} km'
              : '-',
          icon: Icons.straighten,
        ),
        _StatItem(
          label: '爬升',
          value: t.elevationGain != null
              ? '${t.elevationGain!.toStringAsFixed(0)} m'
              : '-',
          icon: Icons.arrow_upward,
        ),
        _StatItem(
          label: '下降',
          value: t.elevationLoss != null
              ? '${t.elevationLoss!.toStringAsFixed(0)} m'
              : '-',
          icon: Icons.arrow_downward,
        ),
      ],
    );
  }

  Widget _buildChart() {
    final data = widget.trail.profileData;
    if (data.isEmpty) return const SizedBox.shrink();

    final spots = data
        .map((e) => FlSpot(e.distanceKm, e.elevation))
        .toList();
    final maxX = data.map((e) => e.distanceKm).reduce((a, b) => a > b ? a : b);
    final minY = data.map((e) => e.elevation).reduce((a, b) => a < b ? a : b);
    final maxY = data.map((e) => e.elevation).reduce((a, b) => a > b ? a : b);
    final padY = (maxY - minY) * 0.15;
    final yMin = (minY - padY).clamp(minY - 50, minY);
    final yMax = (maxY + padY).clamp(maxY, maxY + 50);
    final xRange = maxX > 0 ? maxX : 1.0;
    final bottomInterval = xRange / 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '高度剖面',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 15),
          child: SizedBox(
            height: 120,
            child: LineChart(
            LineChartData(
              minX: 0,
              maxX: xRange,
              minY: yMin,
              maxY: yMax,
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: (yMax - yMin) / 3,
                    getTitlesWidget: (v, _) {
                      final isFirst = (v - yMin).abs() < 0.1;
                      return Text(
                        isFirst ? '${v.toInt()} m' : '${v.toInt()}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade700,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: bottomInterval,
                    getTitlesWidget: (v, _) {
                      final isFirst = v < 0.01;
                      return Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          isFirst ? '${v.toStringAsFixed(1)} km' : v.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300),
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  final cb = widget.onChartTouch;
                  if (cb == null) return;
                  final spots = response?.lineBarSpots;
                  if (spots == null || spots.isEmpty) {
                    cb(null);
                    return;
                  }
                  final spot = spots.first;
                  final touchedDist = spot.x;
                  final profile = widget.trail.profileData;
                  if (profile.isEmpty) return;
                  var best = profile.first;
                  var bestDiff = (best.distanceKm - touchedDist).abs();
                  for (final p in profile) {
                    final d = (p.distanceKm - touchedDist).abs();
                    if (d < bestDiff) {
                      bestDiff = d;
                      best = p;
                    }
                  }
                  cb(LatLng(best.lat, best.lon));
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((LineBarSpot spot) {
                      return LineTooltipItem(
                        '${spot.x.toStringAsFixed(1)} km\n${spot.y.toInt()} m',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                  tooltipBgColor: Colors.black87,
                  tooltipRoundedRadius: 6,
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.green.shade600,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.green.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.green.shade600),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
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
}
