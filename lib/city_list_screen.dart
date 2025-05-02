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

  // Map các thành phố với tọa độ của chúng
  final Map<String, List<double>> cityCoordinates = {
    "Hanoi": [21.0285, 105.8544],
    "Moscow": [55.7558, 37.6173],
    "Saint Petersburg": [59.9343, 30.3351],
    "Paris": [48.8566, 2.3522],
    "London": [51.5074, -0.1278],
    "New York": [40.7128, -74.0060],
    "Beijing": [39.9042, 116.4074],
    "Rome": [41.9028, 12.4964],
    "Tokyo": [35.6895, 139.6917],
    "Shanghai": [31.2304, 121.4737],
    "Los Angeles": [34.0522, -118.2437],
    "Dubai": [25.276987, 55.296249],
    "Mumbai": [19.0760, 72.8777],
    "Ho Chi Minh City": [10.8231, 106.6297],
    "Berlin": [52.5200, 13.4050],
    "Sydney": [-33.8688, 151.2093],
    "Cairo": [30.0444, 31.2357],
    "Toronto": [43.6532, -79.3832],
    "Seoul": [37.5665, 126.9780],
    "Singapore": [1.3521, 103.8198],
  };

  @override
  void initState() {
    super.initState();
    _loadCities();
    _getCurrentLocation();
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

  // Hàm tính khoảng cách giữa hai tọa độ (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const int earthRadius = 6371; // Đơn vị km
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

  // Hàm xác định thành phố gần nhất dựa vào vị trí hiện tại
  Future<void> _getCurrentLocation() async {
    setState(() {
      isLoadingLocation = true;
    });

    try {
      // Kiểm tra quyền truy cập vị trí
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

      // Lấy vị trí hiện tại
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );

      // Tìm thành phố gần nhất
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
          // Hiển thị thành phố gần nhất
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
                        ? const Text('Locating you...')
                        : Text(
                      'Location: $nearestCity',
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
                      child: const Text('Watch'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _getCurrentLocation,
                    tooltip: 'Refresh position',
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Search Cities',
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