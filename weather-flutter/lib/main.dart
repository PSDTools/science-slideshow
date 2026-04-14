import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/weather_display.dart';
import 'widgets/dev_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: 'assets/.env');

  // Immersive fullscreen: hide status bar and navigation bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Lock to landscape orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Keep screen awake
  WakelockPlus.enable();

  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0f1a2a),
      ),
      home: const WeatherDisplay(),
      routes: {
        '/dev': (context) => const DevPage(),
      },
    );
  }
}
