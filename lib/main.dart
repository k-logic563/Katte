import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'features/notifications/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final crashlytics = FirebaseCrashlytics.instance;
  try {
    await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
  } on Object catch (error, stackTrace) {
    debugPrint('Crashlytics initialization failed: $error\n$stackTrace');
  }
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(crashlytics.recordError(error, stackTrace, fatal: true));
    return true;
  };
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: KatteApp()));
}
