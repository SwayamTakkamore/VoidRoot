import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'ideabot.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHEild',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LocationScreen(),
    );
  }
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  _LocationScreenState createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  String _riskMessage = "Enter coordinates or press the button to check safety";
  bool _isLoading = false;
  List<dynamic> _crimeData = [];
  Position? _currentPosition;
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Fluttertoast.showToast(msg: "Please enable location services");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Fluttertoast.showToast(msg: "Location permissions are denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      Fluttertoast.showToast(msg: "Location permissions are permanently denied");
      return;
    }
  }

  Future<void> _getCurrentLocation() async {
    await _checkLocationPermission();

    setState(() => _isLoading = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _latController.text = position.latitude.toStringAsFixed(6);
        _lonController.text = position.longitude.toStringAsFixed(6);
      });

      // Show coordinates in toast
      Fluttertoast.showToast(
        msg: "Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}",
        toastLength: Toast.LENGTH_LONG,
      );

      await checkRisk(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _riskMessage = "Could not get location: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _checkManualLocation() async {
    if (_latController.text.isEmpty || _lonController.text.isEmpty) {
      Fluttertoast.showToast(msg: "Please enter both latitude and longitude");
      return;
    }

    try {
      double lat = double.parse(_latController.text);
      double lon = double.parse(_lonController.text);

      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        Fluttertoast.showToast(msg: "Invalid coordinates. Lat: -90 to 90, Lon: -180 to 180");
        return;
      }

      setState(() {
        _isLoading = true;
        _currentPosition = Position(
          latitude: lat,
          longitude: lon,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      });

      await checkRisk(lat, lon);
    } catch (e) {
      setState(() {
        _riskMessage = "Invalid coordinates: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> checkRisk(double lat, double lon) async {
    try {
      final apiUrl = dotenv.env['API_URL'] ?? 'http://localhost:5000/check_risk';
      final url = Uri.parse(apiUrl);

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"latitude": lat, "longitude": lon}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          if (data is Map && data['data'] is List) {
            _crimeData = data['data'];

            // Check for safe zone message
            if (_crimeData.isNotEmpty && _crimeData[0]['message'] != null) {
              _riskMessage = _crimeData[0]['message'];
              _crimeData = []; // Clear crime data for safe zone
            } else {
              _riskMessage = "Safety Alert! ${_crimeData.length} crime(s) nearby";
            }
          } else {
            _crimeData = [];
            _riskMessage = "You are in a safe zone!";
          }
        });
      } else {
        setState(() {
          _riskMessage = "Server error: ${response.statusCode}";
          _crimeData = [];
        });
      }
    } catch (e) {
      setState(() {
        _riskMessage = "Connection error: ${e.toString()}";
        _crimeData = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRiskIndicator() {
    if (_crimeData.isEmpty) {
      return Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 80),
          const SizedBox(height: 10),
          Text(
            "Safe Zone",
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      );
    }

    // Find highest severity crime
    int maxSeverity = _crimeData.fold(0, (prev, crime) =>
    crime['severity'] > prev ? crime['severity'] : prev);

    Color riskColor;
    String riskLevel;
    if (maxSeverity >= 3) {
      riskColor = Colors.red;
      riskLevel = "High Risk Area";
    } else if (maxSeverity == 2) {
      riskColor = Colors.orange;
      riskLevel = "Moderate Risk";
    } else {
      riskColor = Colors.yellow;
      riskLevel = "Low Risk";
    }

    return Column(
      children: [
        Icon(Icons.warning, color: riskColor, size: 80),
        const SizedBox(height: 10),
        Text(
          riskLevel,
          style: TextStyle(
            color: riskColor,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildCrimeList() {
    if (_crimeData.isEmpty) return const SizedBox();

    return Expanded(
      child: ListView.builder(
        itemCount: _crimeData.length,
        itemBuilder: (context, index) {
          final crime = _crimeData[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              leading: Icon(
                Icons.warning,
                color: crime['severity'] >= 3 ? Colors.red :
                crime['severity'] == 2 ? Colors.orange : Colors.yellow,
              ),
              title: Text(
                crime['crime']?.toString() ?? 'Unknown crime',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: crime['severity'] >= 3 ? Colors.red :
                  crime['severity'] == 2 ? Colors.orange : Colors.black,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Severity: ${crime['severity']?.toString() ?? '?'}"),
                  Text("Distance: ${crime['distance']?.toStringAsFixed(2) ?? '?'} km"),
                  if (crime['cluster'] != null)
                    Text("Cluster: ${crime['cluster']}"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Safety Check"),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      hintText: 'e.g. 19.0826',
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lonController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      hintText: 'e.g. 79.1900',
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _checkManualLocation,
              child: const Text("Check Coordinates"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 20),
            if (_currentPosition != null)
              Text(
                "Current Location: ${_currentPosition!.latitude.toStringAsFixed(6)}, "
                    "${_currentPosition!.longitude.toStringAsFixed(6)}",
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 20),
            _buildRiskIndicator(),
            const SizedBox(height: 20),
            Text(
              _riskMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            _buildCrimeList(),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _getCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(_isLoading ? "Checking..." : "Use Current Location"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
            SizedBox(height: 20,),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ideaBot()),
                );
              },
              icon: const Icon(Icons.my_location),
              label: Text(_isLoading ? "Checking..." : "Use Current Location"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}