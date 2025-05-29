import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'forecast_screen.dart';

class CityListScreen extends StatefulWidget {
  const CityListScreen({Key? key}) : super(key: key);

  @override
  _CityListScreenState createState() => _CityListScreenState();
}

class _CityListScreenState extends State<CityListScreen> {
  List<String> cities = [];
  bool isLoading = true;
  TextEditingController searchController = TextEditingController();
  List<String> filteredCities = [];
  String? nearestCity;
  bool isLoadingLocation = false;
  Map<String, List<double>> cityCoordinates = {};

  @override
  void initState() {
    super.initState();
    _loadCityCoordinates().then((_) {
      _loadCities();
      _getCurrentLocation();
    });
  }

  // Load city coordinates from JSON file
  // Загрузка координат городов из JSON-файла
  Future<void> _loadCityCoordinates() async {
  final jsonString = await rootBundle.loadString('assets/city_coords.json');
  final Map<String, dynamic> jsonMap = json.decode(jsonString);

  setState(() {
    cityCoordinates = jsonMap.map((key, value) {
      return MapEntry(key, List<double>.from(value));
    });
  });
  }

  Future<void> _loadCities() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final citySet = manifestMap.keys
          .where((key) => key.startsWith('assets/modelzz/'))
          .map((path) => path.split('/').last.split('_').first)
          .toSet();

      setState(() {
        cities = citySet.toList()..sort();
        filteredCities = cities;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading cities: $e');
      setState(() => isLoading = false);
    }
  }

  void filterCities(String query) {
    setState(() {
      filteredCities = cities
          .where((city) => city.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // Calculate distance between two coordinates (Haversine formula)
  // Расчёт расстояния между двумя координатами (формула гаверсинусов)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const int earthRadius = 6371; // km / км
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Determine nearest city based on current location
  // Определение ближайшего города на основе текущего местоположения
  Future<void> _getCurrentLocation() async {
    setState(() {
      isLoadingLocation = true;
    });

    try {
      // Check location permission
      // Проверить разрешение на доступ к местоположению
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            isLoadingLocation = false;
          });
          return;
        }
      }

      // Get current position
      // Получить текущее местоположение
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );

      // Find nearest city
      // Найти ближайший город
      String closest = "";
      double minDistance = double.infinity;

      cityCoordinates.forEach((city, coordinates) {
        double distance = _calculateDistance(
            position.latitude,
            position.longitude,
            coordinates[0],
            coordinates[1]
        );

        if (distance < minDistance) {
          minDistance = distance;
          closest = city;
        }
      });

      setState(() {
        nearestCity = closest;
        isLoadingLocation = false;
      });
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        isLoadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weather Forecast Cities')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Display nearest city
          // Отобразить ближайший город
          if (nearestCity != null || isLoadingLocation)
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.blue.shade100,
              child: Row(
                children: [
                  const Icon(Icons.my_location, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: isLoadingLocation
                        ? const Text('Locating you...') // Идёт определение местоположения...
                        : Text(
                      'Location: $nearestCity', // Местоположение: $nearestCity
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (nearestCity != null && !isLoadingLocation)
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ForecastScreen(cityName: nearestCity!),
                          ),
                        );
                      },
                      child: const Text('Watch'), // Смотреть
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _getCurrentLocation,
                    tooltip: 'Refresh position', // Обновить местоположение
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Search Cities', // Поиск городов
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: filterCities,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredCities.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(filteredCities[index]),
                  leading: const Icon(Icons.location_city),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ForecastScreen(cityName: filteredCities[index]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}