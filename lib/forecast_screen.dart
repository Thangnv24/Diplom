import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'prediction_service.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class ForecastScreen extends StatefulWidget {
  final String cityName;
  const ForecastScreen({Key? key, required this.cityName}) : super(key: key);

  @override
  _ForecastScreenState createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  bool isLoading = true;
  bool isLoadingACF = false;
  List<double> temperatureData = [];
  List<double> humidityData = [];
  List<double> windSpeedData = [];
  List<String> dateLabels = [];

  // ACF data
  List<double> acfData = [];
  String selectedParameter = 'temperature';
  bool showACF = false;

  // Historical data for ACF calculation
  List<double> historicalTemperatureData = [];
  List<double> historicalHumidityData = [];
  List<double> historicalWindSpeedData = [];

  @override
  void initState() {
    super.initState();
    _loadForecast();
    _loadHistoricalData();
  }

  Future<void> _loadHistoricalData() async {
    try {
      // Load historical data from CSV file
      // Use city name directly as filename
      String fileName = widget.cityName;
      String csvData = await rootBundle.loadString('assets/or_cities/$fileName.csv');

      List<String> lines = csvData.split('\n');

      // Skip header line (date,temperature_avg,humidity_avg,wind_speed_max)
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim().isEmpty) continue;

        List<String> values = lines[i].split(',');
        if (values.length >= 4) {
          // CSV format: date, temperature_avg, humidity_avg, wind_speed_max
          historicalTemperatureData.add(double.tryParse(values[1]) ?? 0.0);
          historicalHumidityData.add(double.tryParse(values[2]) ?? 0.0);
          historicalWindSpeedData.add(double.tryParse(values[3]) ?? 0.0);
        }
      }

      print('Loaded historical data for ${widget.cityName}:');
      print('Temperature records: ${historicalTemperatureData.length}');
      print('Humidity records: ${historicalHumidityData.length}');
      print('Wind speed records: ${historicalWindSpeedData.length}');

    } catch (e) {
      print('Error loading historical data: $e');
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load historical data for ${widget.cityName}. ACF analysis will not be available.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
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

  Future<void> _generateACF() async {
    setState(() {
      isLoadingACF = true;
    });

    try {
      List<double> dataForACF;

      switch (selectedParameter) {
        case 'temperature':
          dataForACF = historicalTemperatureData;
          break;
        case 'humidity':
          dataForACF = historicalHumidityData;
          break;
        case 'wind_speed':
          dataForACF = historicalWindSpeedData;
          break;
        default:
          dataForACF = historicalTemperatureData;
      }

      if (dataForACF.isEmpty) {
        throw Exception('No historical data available for ${selectedParameter.replaceAll('_', ' ')}. Please ensure the CSV file for ${widget.cityName} exists in assets/or_cities/');
      }

      if (dataForACF.length < 10) {
        throw Exception('Insufficient data points (${dataForACF.length}) for ACF calculation. At least 10 data points are required.');
      }

      if (dataForACF.isNotEmpty) {
        // Limit lags to reasonable number based on data size
        int maxLags = min(40, (dataForACF.length / 4).floor());
        // maxLags = max(10, maxLags); // Ensure minimum 10 lags

        acfData = _calculateACF(dataForACF, maxLags);
        setState(() {
          showACF = true;
          isLoadingACF = false;
        });
      } else {
        throw Exception('No historical data available for ACF calculation');
      }
    } catch (e) {
      print('Error generating ACF: $e');
      setState(() {
        isLoadingACF = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate ACF plot. Please try again.')),
      );
    }
  }

  List<double> _calculateACF(List<double> data, int maxLags) {
    if (data.length <= maxLags) {
      maxLags = data.length - 1;
    }

    List<double> acf = [];
    double mean = data.reduce((a, b) => a + b) / data.length;

    // Calculate variance (lag 0)
    double variance = 0;
    for (double value in data) {
      variance += pow(value - mean, 2);
    }
    variance /= data.length;

    // Calculate ACF for each lag
    for (int lag = 0; lag <= maxLags; lag++) {
      double covariance = 0;
      int count = data.length - lag;

      for (int i = 0; i < count; i++) {
        covariance += (data[i] - mean) * (data[i + lag] - mean);
      }
      covariance /= data.length;

      double correlation = variance > 0 ? covariance / variance : 0;
      acf.add(correlation);
    }

    return acf;
  }

  Widget _buildACFParameterSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACF Analysis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Select parameter for AutoCorrelation Function analysis:',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedParameter,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 'temperature', child: Text('Temperature Avg (°C)')),
              DropdownMenuItem(value: 'humidity', child: Text('Humidity Avg (%)')),
              DropdownMenuItem(value: 'wind_speed', child: Text('Wind Speed Max (km/h)')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() {
                  selectedParameter = value;
                  showACF = false; // Hide previous ACF plot
                });
              }
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoadingACF ? null : _generateACF,
              icon: isLoadingACF
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.analytics),
              label: Text(isLoadingACF ? 'Generating...' : 'Generate ACF Plot'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getParameterDisplayName(String parameter) {
    switch (parameter) {
      case 'temperature':
        return 'TEMPERATURE AVG (°C)';
      case 'humidity':
        return 'HUMIDITY AVG (%)';
      case 'wind_speed':
        return 'WIND SPEED MAX (km/h)';
      default:
        return parameter.toUpperCase();
    }
  }

  Widget _buildACFChart() {
    if (!showACF || acfData.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACF Plot - ${_getParameterDisplayName(selectedParameter)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ACFChartWidget(
            data: acfData,
            parameter: selectedParameter,
          ),
        ],
      ),
    );
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

            // ACF Parameter Selector
            _buildACFParameterSelector(),

            // ACF Chart
            _buildACFChart(),

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

class ACFChartWidget extends StatelessWidget {
  final List<double> data;
  final String parameter;

  const ACFChartWidget({
    Key? key,
    required this.data,
    required this.parameter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final minChartWidth = max(screenWidth - 32, 600);

    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.shade50,
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
      padding: const EdgeInsets.only(top: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: minChartWidth + 60,
          padding: const EdgeInsets.only(left: 20, right: 60, bottom: 10),
          child: CustomPaint(
            size: Size(minChartWidth, 260),
            painter: ACFChartPainter(data: data, parameter: parameter),
          ),
        ),
      ),
    );
  }
}

class ACFChartPainter extends CustomPainter {
  final List<double> data;
  final String parameter;

  ACFChartPainter({required this.data, required this.parameter});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double width = size.width * 0.6;
    final double height = size.height;
    final double chartHeight = height - 80;
    final double chartTop = 40;

    // Draw confidence bands (±1.96/sqrt(n) for 95% confidence)
    double confidenceLevel = 1.96 / sqrt(data.length);

    final Paint confidencePaint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Draw confidence lines (chỉ vẽ đường, không vẽ vùng)
    double confLineY1 = chartTop + chartHeight * (1 - confidenceLevel) / 2;
    double confLineY2 = chartTop + chartHeight * (1 + confidenceLevel) / 2;

    canvas.drawLine(Offset(0, confLineY1), Offset(width, confLineY1), confidencePaint);
    canvas.drawLine(Offset(0, confLineY2), Offset(width, confLineY2), confidencePaint);

    // Draw zero line
    final Paint zeroLinePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double zeroY = chartTop + chartHeight / 2;
    canvas.drawLine(Offset(0, zeroY), Offset(width, zeroY), zeroLinePaint);

    // Draw ACF vertical lines (các cột gần nhau hơn)
    final Paint linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5; // Làm mỏng hơn

    // Thu gọn khoảng cách giữa các cột
    final double availableWidth = width * 0.9; // Sử dụng 90% chiều rộng
    final double barSpacing = availableWidth / data.length;
    final double startX = width * 0.05; // Bắt đầu từ 5% chiều rộng

    for (int i = 0; i < data.length; i++) {
      double x = startX + i * barSpacing;
      double acfValue = data[i];

      // Calculate line endpoints
      double lineBottom = zeroY;
      double lineTop = zeroY - (acfValue * chartHeight / 2);

      // Draw vertical line from zero to ACF value
      canvas.drawLine(
        Offset(x, lineBottom),
        Offset(x, lineTop),
        linePaint,
      );

      // Draw small circle at the end of each line for better visibility
      final Paint pointPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, lineTop), 1.5, pointPaint);

      // Draw lag labels every 5 lags to avoid overcrowding
      if (i % 5 == 0 || i == data.length - 1) {
        final TextSpan lagSpan = TextSpan(
          text: i.toString(),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 10,
          ),
        );
        final TextPainter lagPainter = TextPainter(
          text: lagSpan,
          textDirection: ui.TextDirection.ltr,
        );
        lagPainter.layout();
        lagPainter.paint(
          canvas,
          Offset(x - lagPainter.width / 2, height - 20),
        );
      }
    }

    // Draw Y-axis labels
    final TextStyle labelStyle = TextStyle(
      color: Colors.black87,
      fontSize: 10,
    );

    for (double val in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
      double y = chartTop + chartHeight * (1 - val) / 2;

      final TextSpan valueSpan = TextSpan(
        text: val.toStringAsFixed(1),
        style: labelStyle,
      );
      final TextPainter valuePainter = TextPainter(
        text: valueSpan,
        textDirection: ui.TextDirection.ltr,
      );
      valuePainter.layout();
      valuePainter.paint(
        canvas,
        Offset(-valuePainter.width - 5, y - valuePainter.height / 2),
      );
    }

    // Draw title
    final TextSpan titleSpan = TextSpan(
      text: 'Lag',
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final TextPainter titlePainter = TextPainter(
      text: titleSpan,
      textDirection: ui.TextDirection.ltr,
    );
    titlePainter.layout();
    titlePainter.paint(
      canvas,
      Offset(width / 2 - titlePainter.width / 2, height - 10),
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
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