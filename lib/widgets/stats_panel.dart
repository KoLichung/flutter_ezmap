import 'package:flutter/material.dart';

class StatsPanel extends StatelessWidget {
  final double distance;
  final double ascent;
  final double descent;
  final double speed;
  final String duration;

  const StatsPanel({
    super.key,
    required this.distance,
    required this.ascent,
    required this.descent,
    required this.speed,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('距離', '${distance.toStringAsFixed(2)} km'),
              _buildStat('時間', duration),
              _buildStat('速度', '${speed.toStringAsFixed(1)} km/h'),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('爬升', '${ascent.toStringAsFixed(0)} m', Colors.green),
              _buildStat('下降', '${descent.toStringAsFixed(0)} m', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, [Color? valueColor]) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}

