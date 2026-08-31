import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

enum KatteAnalyticsEvent {
  login('login'),
  groupCreated('group_created'),
  groupJoined('group_joined'),
  shoppingItemAdded('shopping_item_added'),
  shoppingItemPurchased('shopping_item_purchased'),
  shoppingItemUndo('shopping_item_undo'),
  groupLeft('group_left'),
  groupDeleted('group_deleted');

  const KatteAnalyticsEvent(this.eventName);

  final String eventName;
}

abstract interface class AnalyticsService {
  NavigatorObserver get navigatorObserver;

  Future<void> log(KatteAnalyticsEvent event);
}

class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  @override
  late final NavigatorObserver navigatorObserver = FirebaseAnalyticsObserver(
    analytics: _analytics,
  );

  @override
  Future<void> log(KatteAnalyticsEvent event) async {
    try {
      await _analytics.logEvent(name: event.eventName);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Analytics event failed [${event.eventName}]: $error\n$stackTrace',
      );
    }
  }
}

abstract interface class CrashReportingService {
  Future<void> setUserIdentifier(String? userId);
}

class FirebaseCrashReportingService implements CrashReportingService {
  FirebaseCrashReportingService({FirebaseCrashlytics? crashlytics})
    : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> setUserIdentifier(String? userId) async {
    try {
      await _crashlytics.setUserIdentifier(userId ?? '');
    } on Object catch (error, stackTrace) {
      debugPrint('Crash user sync failed: $error\n$stackTrace');
    }
  }
}
