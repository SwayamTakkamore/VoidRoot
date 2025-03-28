import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

void main() async {
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
      home: LocationScreen(),
    );
  }
}

class LocationScreen extends StatefulWidget {
  @override
  _LocationScreenState createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  String _riskMessage = "Press the button to check risk in your area";
  bool _isLoading = false;

  Future<void> checkRisk(double lat, double lon) async {
    setState(() {
      _isLoading = true;
      _riskMessage = "Checking...";
    });

    try {
      final apiUrl = dotenv.env['API_URL']!;
      final url = Uri.parse(apiUrl);

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"latitude": lat, "longitude": lon}),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _riskMessage = data.isNotEmpty
              ? data.map((e) => "${e['crime']} (Severity: ${e['severity']})").join("\n")
              : "You are in a safe zone.";
        });
      } else {
        setState(() {
          _riskMessage = "Error fetching data. Status code: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _riskMessage = "Error: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Crime Risk Detector")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                _riskMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => checkRisk(19.1350, 79.0830), // Replace with real GPS coordinates
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text("Check Safety Status"),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}