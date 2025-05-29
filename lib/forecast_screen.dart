import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'prediction_service.dart';
import 'dart:ui' as ui;
import 'dart:math';

class ForecastScreen extends StatefulWidget {
  final String cityName;
  const ForecastScreen({Key? key, required this.cityName}) : super(key: key);

  @override
  _ForecastScreenState createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  bool isLoading = true;
  List<double> temperatureData = [];
  List<double> humidityData = [];
  List<double> windSpeedData = [];
  List<String> dateLabels = [];

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    setState(() {
      isLoading = true;
    });

    try {
      final now = DateTime.now();
      // Format date with space between day and month
      // Форматировать дату с пробелом между днем и месяцем
      dateLabels = List.generate(
          7, (index) => DateFormat('dd/MM').format(now.add(Duration(days: index))));

          // Call prediction function from TFLite model
          // Вызвать функцию прогнозирования из модели TFLite
          final predictions = await predictWeather(widget.cityName);

      setState(() {
        temperatureData = predictions['temperature'] ?? [];
        humidityData = predictions['humidity'] ?? [];
        windSpeedData = predictions['wind_speed'] ?? [];
        isLoading = false;
      });
    } catch (e) {
      print('Forecast loading error: $e');
      setState(() {
        isLoading = false;
      });

      // Show error message to user if needed
      // При необходимости показать сообщение об ошибке пользователю
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load weather forecast. Please try again later.')),
      );
    }
  }
  Widget _buildForecastTable() {
    // Determine actual number of rows to display, take min between 7 and data length
    // Определить фактическое количество отображаемых строк, взять минимум между 7 и длиной данных
    final int actualRowCount = min(7, min(temperatureData.length, min(humidityData.length, windSpeedData.length)));

    if (actualRowCount == 0 && !isLoading) {
      // Handle case of no data after loading
      // Обработать случай отсутствия данных после загрузки
      return const Center(child: Text('No forecast data available.', style: TextStyle(fontSize: 16)));
    }

    // Wrap DataTable in horizontal SingleChildScrollView to avoid overflow
    // Обернуть DataTable в горизонтальный SingleChildScrollView для предотвращения переполнения
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Temp (°C)')),
          DataColumn(label: Text('Humidity (%)')),
          DataColumn(label: Text('Wind (km/h)')),
        ],
        rows: List.generate(
          actualRowCount,
              (index) => DataRow(cells: [
            DataCell(Text(dateLabels[index])),
            // Can reduce decimal places
            // Можно уменьшить количество знаков после запятой
            DataCell(Text(temperatureData[index].toStringAsFixed(2))),
            DataCell(Text(humidityData[index].toStringAsFixed(2))),
            DataCell(Text(windSpeedData[index].toStringAsFixed(2))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.cityName} 7-Day Forecast')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detailed Forecast',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildForecastTable(),
            const SizedBox(height: 20),
            const Text('Temperature (°C)',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            OptimizedChartWidget(
                data: temperatureData,
                color: Colors.red,
                labels: dateLabels),
            const SizedBox(height: 24),
            const Text('Humidity (%)',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            OptimizedChartWidget(
                data: humidityData,
                color: Colors.blue,
                labels: dateLabels),
            const SizedBox(height: 24),
            const Text('Wind Speed (km/h)',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            OptimizedChartWidget(
                data: windSpeedData,
                color: Colors.green,
                labels: dateLabels),
          ],
        ),
      ),
    );
  }
}

class OptimizedChartWidget extends StatelessWidget {
  final List<double> data;
  final Color color;
  final List<String> labels;

  const OptimizedChartWidget({
    Key? key,
    required this.data,
    required this.color,
    required this.labels,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Calculate minimum required width for chart
    // Рассчитать минимальную необходимую ширину для диаграммы
    final screenWidth = MediaQuery.of(context).size.width;
    final minChartWidth = max(screenWidth - 32, 600);

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey.shade100,
            Colors.white,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      // Remove right padding in container
      // Убрать правый отступ в контейнере
      padding: const EdgeInsets.only(top: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          // Add right padding to ensure last value displays fully
          // Добавить правый отступ для полного отображения последнего значения
          width: minChartWidth + 60,
          padding: const EdgeInsets.only(left: 20, right: 60, bottom: 10),
          child: CustomPaint(
            size: Size(minChartWidth, 200),
            painter: OptimizedChartPainter(
              data: data,
              color: color,
              labels: labels,
            ),
          ),
        ),
      ),
    );
  }
}

class OptimizedChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final List<String> labels;

  OptimizedChartPainter({
    required this.data,
    required this.color,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double width = size.width;
    final double height = size.height;
    final double chartHeight = height - 40;

    // Draw background grid lines
    // Нарисовать линии сетки фона
    _drawGridLines(canvas, width, chartHeight);

    double minValue = data.reduce((a, b) => a < b ? a : b);
    double maxValue = data.reduce((a, b) => a > b ? a : b);

    // Ensure top/bottom padding
    // Обеспечить отступы сверху/снизу
    double padding = (maxValue - minValue) * 0.15;
    maxValue += padding;
    minValue -= padding;
    minValue = minValue < 0 ? 0 : minValue;

    final double dataRange = maxValue - minValue;

    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final Paint pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint shadowPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final TextStyle labelStyle = TextStyle(
      color: Colors.black87,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    // Graph points
    // Точки графика
    Path linePath = Path();
    Path fillPath = Path();
    bool first = true;

    // Adjust point spacing to avoid overlap and ensure right space
    // Настроить расстояние между точками для предотвращения наложения
    final double actualWidth = width * 0.90;
    final double pointSpacing = actualWidth / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final double x = i * pointSpacing;
      final double normalizedValue = dataRange > 0 ? (data[i] - minValue) / dataRange : 0.5;
      final double y = chartHeight - (normalizedValue * chartHeight);

      if (first) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, chartHeight);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // Draw point with glow effect
      // Нарисовать точку с эффектом свечения
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = color.withOpacity(0.3));
      canvas.drawCircle(Offset(x, y), 4, pointPaint);

      // Draw point value
      // Нарисовать значение точки
      final TextSpan valueSpan = TextSpan(
        text: data[i].toStringAsFixed(4),
        style: labelStyle,
      );
      final TextPainter valuePainter = TextPainter(
        text: valueSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      valuePainter.layout();

      // Draw text background
      // Нарисовать фон текста
      final Rect textRect = Rect.fromCenter(
        center: Offset(x, y - 20),
        width: valuePainter.width + 8,
        height: valuePainter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(4)),
        Paint()..color = Colors.white.withOpacity(0.8),
      );

      valuePainter.paint(
          canvas,
          Offset(x - valuePainter.width / 2, y - 22)
      );

      // Draw date label
      // Нарисовать метку даты
      final TextSpan dateSpan = TextSpan(
        text: labels[i],
        style: labelStyle,
      );
      final TextPainter datePainter = TextPainter(
        text: dateSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      datePainter.layout();
      datePainter.paint(
          canvas,
          Offset(x - datePainter.width / 2, height - datePainter.height - 5)
      );
    }

    // Complete fill path
    // Завершить путь заливки
    fillPath.lineTo((data.length - 1) * pointSpacing, chartHeight);
    fillPath.close();

    // Draw area fill first
    // Сначала нарисовать заливку области
    canvas.drawPath(fillPath, shadowPaint);

    // Draw connecting line afterwards
    // Затем нарисовать соединительную линию
    canvas.drawPath(linePath, linePaint);
  }

  void _drawGridLines(Canvas canvas, double width, double height) {
    final Paint gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1.0;

    // Draw horizontal lines
    // Нарисовать горизонтальные линии
    for (int i = 1; i < 5; i++) {
      final double y = height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // Draw vertical lines
    // Нарисовать вертикальные линии
    for (int i = 0; i < data.length; i++) {
      final double x = i * width / (data.length - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

double max(double a, double b) {
  return a > b ? a : b;
}