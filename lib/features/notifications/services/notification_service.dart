import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_service.dart';
import '../../../firebase_options.dart';

const _deviceIdPreferenceKey = 'katte_notification_device_id';
const _notificationChannelId = 'katte_item_updates';
const _notificationChannelName = '商品追加';

class NotificationTap {
  const NotificationTap({this.groupId});

  final String? groupId;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

abstract interface class NotificationService {
  Stream<NotificationTap> get notificationTaps;

  Future<void> registerForUser(AuthUser user);

  Future<void> unregisterForUser(AuthUser user);

  Future<void> clearAfterAccountDeletion();

  void dispose();
}

class FirebaseNotificationService implements NotificationService {
  FirebaseNotificationService({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final _notificationTaps = StreamController<NotificationTap>.broadcast();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  String? _currentUserId;
  String? _deviceId;
  bool _localNotificationsInitialized = false;
  bool _initialMessageHandled = false;

  @override
  Stream<NotificationTap> get notificationTaps => _notificationTaps.stream;

  @override
  Future<void> registerForUser(AuthUser user) async {
    if (_currentUserId == user.uid) {
      return;
    }

    await _initializeLocalNotifications();
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (kDebugMode) {
      debugPrint(
        'Notification authorization status: ${settings.authorizationStatus.name}',
      );
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('Notification permission not granted.');
      return;
    }

    final deviceId = await _getOrCreateDeviceId();
    _currentUserId = user.uid;
    _deviceId = deviceId;

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) => _handleTokenRefresh(user.uid, deviceId, token),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('FCM token refresh failed: $error\n$stackTrace');
      },
    );

    try {
      final token = await _getInitialToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(userId: user.uid, deviceId: deviceId, token: token);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('FCM token registration failed: $error\n$stackTrace');
    }

    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Foreground message handling failed: $error\n$stackTrace');
      },
    );
    _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );

    if (!_initialMessageHandled) {
      _initialMessageHandled = true;
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
      final localLaunch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp ?? false) {
        _notificationTaps.add(
          NotificationTap(
            groupId: _validGroupId(localLaunch?.notificationResponse?.payload),
          ),
        );
      }
    }
  }

  Future<String?> _getInitialToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      const retryDelay = Duration(milliseconds: 500);
      for (var attempt = 0; attempt < 10; attempt++) {
        if (await _messaging.getAPNSToken() != null) {
          if (kDebugMode) {
            debugPrint('APNs token available.');
          }
          final token = await _messaging.getToken();
          if (kDebugMode && token != null && token.isNotEmpty) {
            debugPrint('FCM token available.');
          }
          return token;
        }
        await Future<void>.delayed(retryDelay);
      }
      debugPrint(
        'APNs token is not available yet; waiting for FCM token refresh.',
      );
      return null;
    }
    return _messaging.getToken();
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) {
      return;
    }
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) => _notificationTaps.add(
        NotificationTap(groupId: _validGroupId(response.payload)),
      ),
    );

    const channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: '同じグループの商品追加をお知らせします。',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _localNotificationsInitialized = true;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      return;
    }
    await _localNotifications.show(
      id:
          message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: notification.title ?? 'Katte',
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          _notificationChannelName,
          channelDescription: '同じグループの商品追加をお知らせします。',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: _validGroupId(message.data['groupId']),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _notificationTaps.add(
      NotificationTap(groupId: _validGroupId(message.data['groupId'])),
    );
  }

  String? _validGroupId(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Future<void> _handleTokenRefresh(
    String userId,
    String deviceId,
    String token,
  ) async {
    if (_currentUserId != userId || token.isEmpty) {
      return;
    }
    try {
      await _saveToken(userId: userId, deviceId: deviceId, token: token);
    } on Object catch (error, stackTrace) {
      debugPrint('FCM token refresh save failed: $error\n$stackTrace');
    }
  }

  Future<void> _saveToken({
    required String userId,
    required String deviceId,
    required String token,
  }) async {
    final reference = _deviceReference(userId, deviceId);
    final snapshot = await reference.get();
    final platform = _platformName();
    final current = snapshot.data();
    if (current?['fcmToken'] == token &&
        current?['platform'] == platform &&
        current?['notificationEnabled'] == true) {
      return;
    }
    await reference.set({
      'fcmToken': token,
      'platform': platform,
      'notificationEnabled': true,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (kDebugMode) {
      debugPrint('FCM device registration updated.');
    }
  }

  @override
  Future<void> unregisterForUser(AuthUser user) async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    final deviceId = _deviceId ?? await _getOrCreateDeviceId();

    try {
      await _deviceReference(user.uid, deviceId).delete();
    } on Object catch (error, stackTrace) {
      debugPrint('Device registration deletion failed: $error\n$stackTrace');
    }
    try {
      await _messaging.deleteToken();
    } on Object catch (error, stackTrace) {
      debugPrint('FCM token deletion failed: $error\n$stackTrace');
    }

    _currentUserId = null;
    _deviceId = null;
  }

  @override
  Future<void> clearAfterAccountDeletion() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    // deleteAccount Cloud Function recursively deletes users/{uid}, including
    // devices. Only device-local notification state remains at this point.
    try {
      await _messaging.deleteToken();
    } on Object catch (error, stackTrace) {
      debugPrint('FCM token deletion failed: $error\n$stackTrace');
    }

    _currentUserId = null;
    _deviceId = null;
  }

  DocumentReference<Map<String, dynamic>> _deviceReference(
    String userId,
    String deviceId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId);
  }

  Future<String> _getOrCreateDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdPreferenceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final deviceId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(_deviceIdPreferenceKey, deviceId);
    return deviceId;
  }

  String _platformName() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => defaultTargetPlatform.name,
    };
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    _notificationTaps.close();
  }
}
