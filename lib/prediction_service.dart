import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:intl/intl.dart';

Future<Map<String, List<double>>> predictWeather(String cityName) async {
  final Map<String, List<double>> results = {};
  final List<String> parameters = ['temperature_avg', 'humidity_avg', 'wind_speed_max'];
  final Map<String, String> paramMapping = {
    'temperature_avg': 'temperature',
    'humidity_avg': 'humidity',
    'wind_speed_max': 'wind_speed'
  };
  final int daysToPredict = 7;

  try {
    final DateTime lastDataDate = DateTime(2025, 3, 8); // Ngày dữ liệu cuối cùng
    final DateTime now = DateTime.now();

    final int dayOffset = now.difference(lastDataDate).inDays;

    print('Last day: ${DateFormat('dd/MM/yyyy').format(lastDataDate)}');
    print('Today: ${DateFormat('dd/MM/yyyy').format(now)}');
    print('Day_gap: $dayOffset');

    for (String param in parameters) {
      try {
        final String modelPath = 'assets/modelzz/${cityName}_${param}.tflite';
        print('Loading model: $modelPath');

        final interpreter = await Interpreter.fromAsset(modelPath);

        List<double> predictions = [];

        for (int i = 0; i < daysToPredict; i++) {
          final double adjustedDay = (dayOffset + i).toDouble();
          final input = [[adjustedDay]];
          final output = [[0.0]];

          // Predict
          interpreter.run(input, output);

          print('Day ${i} (thực tế là ngày +$adjustedDay từ dữ liệu): Input=$input, Output=$output');
          predictions.add(output[0][0]);
        }

        // Save
        final outputKey = paramMapping[param] ?? param.split('_')[0];
        results[outputKey] = predictions;

        interpreter.close();
      } catch (e) {
        print('Lỗi khi xử lý tham số $param: $e');

        // Đưa vào dữ liệu mặc định (0.0) khi có lỗi
        final outputKey = paramMapping[param] ?? param.split('_')[0];
        results[outputKey] = List.generate(daysToPredict, (index) => 0.0);
      }
    }

    return results;
  } catch (e) {
    print('Lỗi tổng thể khi dự đoán thời tiết: $e');
    return {
      'temperature': List.generate(daysToPredict, (index) => 0.0),
      'humidity': List.generate(daysToPredict, (index) => 0.0),
      'wind_speed': List.generate(daysToPredict, (index) => 0.0),
    };
  }
}