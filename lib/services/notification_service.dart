import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 🟢 Global Key to navigate without BuildContext!
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background handler MUST be a top-level function outside any class
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Background message received: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // 1. Request permissions (Crucial for Android 13+)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');

    // 2. Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Handle app launched from a terminated state (App was closed)
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }

    // 4. Handle taps while the app is running in the background (Minimized)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // 5. Handle messages while the app is OPEN (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      // Note: System notification banners don't show when the app is open.
      // We will handle this later if you want custom in-app popups!
    });

    String? token = await _messaging.getToken();
    debugPrint("📱 DEVICE FCM TOKEN: $token");
  }

  // 🟢 The magic routing function
  // 🟢 Update ONLY this function in your services/notification_service.dart

  static void _handleMessage(RemoteMessage message) {
    if (message.data['screen'] == 'mock_test') {
      final String? testId = message.data['testId'];
      final String? title = message.data['title'];
      final String? duration = message.data['duration'];

      if (testId != null && title != null) {
        // We pass a Map as the argument so main.dart can read everything
        navigatorKey.currentState?.pushNamed(
          '/test_details',
          arguments: {
            'id': testId,
            'title': title,
            'duration': int.tryParse(duration ?? '90') ?? 90,
          },
        );
      }
    }
  }
}