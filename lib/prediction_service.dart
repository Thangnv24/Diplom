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
    // Last data date / Последняя дата данных
    final DateTime lastDataDate = DateTime(2025, 5, 29);
    final DateTime now = DateTime.now();

    final int dayOffset = now.difference(lastDataDate).inDays;

    print('Last day: ${DateFormat('dd/MM/yyyy').format(lastDataDate)}');
    print('Today: ${DateFormat('dd/MM/yyyy').format(now)}');
    print('Day_gap: $dayOffset');

    for (String param in parameters) {
      try {
        final String modelPath = 'assets/model/${cityName}_${param}.tflite';
        print('Loading model: $modelPath');

        final interpreter = await Interpreter.fromAsset(modelPath);

        List<double> predictions = [];

        for (int i = 0; i < daysToPredict; i++) {
          final double adjustedDay = (dayOffset + i).toDouble();
          final input = [[adjustedDay]];
          final output = [[0.0]];

          // Predict / Прогнозировать
          interpreter.run(input, output);

          print('Day $i (actual day +$adjustedDay from data): Input=$input, Output=$output');
          predictions.add(output[0][0]);
        }

        // Save / Сохранить
        final outputKey = paramMapping[param] ?? param.split('_')[0];
        results[outputKey] = predictions;

        interpreter.close();
      } catch (e) {
        print('Error processing parameter $param: $e');

        // Insert default data (0.0) on error / Вставить данные по умолчанию при ошибке
        final outputKey = paramMapping[param] ?? param.split('_')[0];
        results[outputKey] = List.generate(daysToPredict, (index) => 0.0);
      }
    }

    return results;
  } catch (e) {
    print('General error in weather prediction: $e');
    return {
      'temperature': List.generate(daysToPredict, (index) => 0.0),
      'humidity': List.generate(daysToPredict, (index) => 0.0),
      'wind_speed': List.generate(daysToPredict, (index) => 0.0),
    };
  }
}