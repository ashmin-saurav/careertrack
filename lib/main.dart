import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_update/in_app_update.dart';

import 'screens/home_screen.dart';
import 'screens/language_screen.dart';
import 'firebase_options.dart';

// 🟢 SERVICE & SCREEN IMPORTS
import 'services/notification_service.dart'; // navigatorKey comes from here!
import 'screens/test_instruction_screen.dart';

// 🟢 GlobalKey for SnackBar (Safe Updates from anywhere in the app)
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize AdMob
  await MobileAds.instance.initialize();

  // 2. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🟢 INITIALIZE NOTIFICATIONS
  await NotificationService.initialize();

  // 3. Initialize Hive Database
  await Hive.initFlutter();
  await Hive.openBox('app_metadata');
  await Hive.openLazyBox('app_cache');
  await Hive.openBox('exam_history');
  await Hive.openBox('saved_questions');
  await Hive.openBox('user_data');
  await Hive.openBox('host_prefs');
  await Hive.openBox('support_cache');

  // 4. Check First Time User
  final prefs = await SharedPreferences.getInstance();
  final bool isFirstTime = prefs.getBool('isFirstTime') ?? true;

  runApp(ExamPrepApp(showLanguageScreen: isFirstTime));
}

class ExamPrepApp extends StatefulWidget {
  final bool showLanguageScreen;
  const ExamPrepApp({super.key, required this.showLanguageScreen});

  @override
  State<ExamPrepApp> createState() => _ExamPrepAppState();
}

class _ExamPrepAppState extends State<ExamPrepApp> {

  @override
  void initState() {
    super.initState();
    // Only check for updates if they are already an active user (not on the onboarding screen)
    if (!widget.showLanguageScreen) {
      _checkForUpdate();
    }
  }

  // 🟢 THE FULL, SAFE UPDATE FUNCTION
  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {

        // 1. Start the silent background download
        AppUpdateResult result = await InAppUpdate.startFlexibleUpdate();

        // 2. Show the SnackBar safely using the GlobalKey!
        if (result == AppUpdateResult.success) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: const Text("New update downloaded! Restart to apply."),
              backgroundColor: Colors.green[700],
              behavior: SnackBarBehavior.floating,
              duration: const Duration(days: 1), // Keeps it on screen until they click
              action: SnackBarAction(
                label: "RESTART",
                textColor: Colors.white,
                onPressed: () async {
                  // 3. Restart only when the user is completely ready
                  await InAppUpdate.completeFlexibleUpdate();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Totally normal to fail in VS Code debugging. Only works on real Play Store installs.
      debugPrint("Play Store Update Check Failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RRB NTPC 2026 Prep',

      // 🟢 ATTACH BOTH GLOBAL KEYS HERE
      navigatorKey: navigatorKey, // Allows silent background notifications to open screens
      scaffoldMessengerKey: scaffoldMessengerKey, // Allows background downloads to show banners

      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1A237E),
        scaffoldBackgroundColor: const Color(0xFFF3F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),

      home: widget.showLanguageScreen ? const LanguageScreen() : const HomeScreen(),

      // 🟢 DYNAMIC ROUTE GENERATOR (For Firebase Notifications)
      onGenerateRoute: (settings) {
        if (settings.name == '/test_details') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => TestInstructionScreen(
              testId: args['id'],
              title: args['title'],
              duration: args['duration'],
            ),
          );
        }
        return null;
      },
    );
  }
}