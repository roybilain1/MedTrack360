import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clear stale location prompt flag from previous full-screen version
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('location_prompt_seen') == true &&
      prefs.getBool('location_popup_v2') != true) {
    await prefs.remove('location_prompt_seen');
    await prefs.setBool('location_popup_v2', true);
  }

  runApp(const MedTrack360App());
}

class MedTrack360App extends StatelessWidget {
  const MedTrack360App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'MedTrack360',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
