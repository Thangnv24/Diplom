import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// delete
class ChartWidget extends StatelessWidget {
  final List<double> data;
  final Color color;
  final List<String> labels;

  const ChartWidget({Key? key, required this.data, required this.color, required this.labels}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: const EdgeInsets.only(right: 16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(labels[value.toInt()] ?? ''),
              reservedSize: 30,
            )),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: data.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value)).toList(),
              isCurved: true,
              color: color,
              barWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
