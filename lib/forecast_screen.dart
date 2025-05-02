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
      // Định dạng ngày tháng với khoảng cách giữa ngày và tháng
      dateLabels = List.generate(
          7, (index) => DateFormat('dd/MM').format(now.add(Duration(days: index))));

      // Gọi hàm dự đoán từ TFLite model
      final predictions = await predictWeather(widget.cityName);

      setState(() {
        temperatureData = predictions['temperature'] ?? [];
        humidityData = predictions['humidity'] ?? [];
        windSpeedData = predictions['wind_speed'] ?? [];
        isLoading = false;
      });
    } catch (e) {
      print('Lỗi khi tải dự báo: $e');
      setState(() {
        isLoading = false;
      });

      // Hiển thị thông báo lỗi cho người dùng nếu cần
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể tải dự báo thời tiết. Vui lòng thử lại sau.')),
      );
    }
  }
  // Future<void> _loadForecast() async {
  //   final now = DateTime.now();
  //   // Định dạng ngày tháng với khoảng cách giữa ngày và tháng
  //   dateLabels = List.generate(
  //       7, (index) => DateFormat('dd/MM').format(now.add(Duration(days: index))));
  //   final predictions = await predictWeather(widget.cityName);
  //   setState(() {
  //     temperatureData = predictions['temperature']!;
  //     humidityData = predictions['humidity']!;
  //     windSpeedData = predictions['wind_speed']!;
  //     isLoading = false;
  //   });
  // }

  // Widget _buildForecastTable() {
  //   // Bọc DataTable trong SingleChildScrollView theo chiều ngang để tránh lỗi overflow.
  //   return SingleChildScrollView(
  //     scrollDirection: Axis.horizontal,
  //     child: DataTable(
  //       columns: const [
  //         DataColumn(label: Text('Date')),
  //         DataColumn(label: Text('Temp (°C)')),
  //         DataColumn(label: Text('Humidity (%)')),
  //         DataColumn(label: Text('Wind (km/h)')),
  //       ],
  //       rows: List.generate(
  //         7,
  //             (index) => DataRow(cells: [
  //           DataCell(Text(dateLabels[index])),
  //           DataCell(Text(temperatureData[index].toStringAsFixed(4))),
  //           DataCell(Text(humidityData[index].toStringAsFixed(4))),
  //           DataCell(Text(windSpeedData[index].toStringAsFixed(4))),
  //         ]),
  //       ),
  //     ),
  //   );
  // }
  Widget _buildForecastTable() {
    // Xác định số lượng dòng thực tế cần hiển thị, lấy giá trị nhỏ nhất giữa 7
    // và độ dài của các danh sách dữ liệu.
    // dateLabels được đảm bảo có 7 phần tử trong _loadForecast.
    final int actualRowCount = min(7, min(temperatureData.length, min(humidityData.length, windSpeedData.length)));

    if (actualRowCount == 0 && !isLoading) {
      // Xử lý trường hợp không có dữ liệu sau khi tải
      return const Center(child: Text('Không có dữ liệu dự báo.', style: TextStyle(fontSize: 16)));
    }


    // Bọc DataTable trong SingleChildScrollView theo chiều ngang để tránh lỗi overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Temp (°C)')),
          DataColumn(label: Text('Humidity (%)')),
          DataColumn(label: Text('Wind (km/h)')),
        ],
        // Sử dụng actualRowCount thay vì cố định 7
        rows: List.generate(
          actualRowCount,
              (index) => DataRow(cells: [
            DataCell(Text(dateLabels[index])),
            DataCell(Text(temperatureData[index].toStringAsFixed(2))), // Có thể giảm số thập phân
            DataCell(Text(humidityData[index].toStringAsFixed(2))),   // Có thể giảm số thập phân
            DataCell(Text(windSpeedData[index].toStringAsFixed(2))),    // Có thể giảm số thập phân
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
            // Thay đổi ChartWidget để hiển thị đồ thị tối ưu
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

// Tạo lớp mới cho chart widget được tối ưu
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
    // Tính toán chiều rộng tối thiểu cần thiết cho biểu đồ
    // Đảm bảo thêm khoảng trống bên phải đủ cho giá trị cuối cùng
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
      padding: const EdgeInsets.only(top: 20), // Bỏ padding bên phải ở container chứa
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          // Thêm padding bên phải để đảm bảo giá trị cuối cùng hiển thị đầy đủ
          width: minChartWidth + 60, // Thêm 60px cho biên phải
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

// Tạo lớp vẽ đồ thị được tối ưu
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
    final double chartHeight = height - 40; // Để lại khoảng cách cho nhãn

    // Vẽ background grid lines
    _drawGridLines(canvas, width, chartHeight);

    // Tìm giá trị min và max
    double minValue = data.reduce((a, b) => a < b ? a : b);
    double maxValue = data.reduce((a, b) => a > b ? a : b);

    // Đảm bảo có khoảng cách trên và dưới
    double padding = (maxValue - minValue) * 0.15;
    maxValue += padding;
    minValue -= padding;
    minValue = minValue < 0 ? 0 : minValue;

    final double dataRange = maxValue - minValue;

    // Vẽ đường đồ thị
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

    // Các điểm trên đồ thị
    Path linePath = Path();
    Path fillPath = Path();
    bool first = true;

    // Điều chỉnh khoảng cách giữa các điểm để tránh chồng chéo và đảm bảo không gian bên phải
    // Chừa không gian bên phải bằng cách chỉ sử dụng tối đa 90% chiều rộng cho các điểm
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

      // Vẽ điểm với hiệu ứng glow
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = color.withOpacity(0.3));
      canvas.drawCircle(Offset(x, y), 4, pointPaint);

      // Vẽ giá trị của điểm
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

      // Vẽ background cho text
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

      // Vẽ nhãn ngày
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

    // Hoàn thành đường fill path
    fillPath.lineTo((data.length - 1) * pointSpacing, chartHeight);
    fillPath.close();

    // Vẽ area fill trước
    canvas.drawPath(fillPath, shadowPaint);

    // Vẽ đường kết nối các điểm sau
    canvas.drawPath(linePath, linePaint);
  }

  void _drawGridLines(Canvas canvas, double width, double height) {
    final Paint gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1.0;

    // Vẽ đường ngang
    for (int i = 1; i < 5; i++) {
      final double y = height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // Vẽ đường dọc
    for (int i = 0; i < data.length; i++) {
      final double x = i * width / (data.length - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// Hàm hỗ trợ
double max(double a, double b) {
  return a > b ? a : b;
}
