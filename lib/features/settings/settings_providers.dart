import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationSettings {
  const NotificationSettings({
    this.itemAdded = true,
    this.shoppingStarted = true,
  });

  final bool itemAdded;
  final bool shoppingStarted;

  NotificationSettings copyWith({bool? itemAdded, bool? shoppingStarted}) {
    return NotificationSettings(
      itemAdded: itemAdded ?? this.itemAdded,
      shoppingStarted: shoppingStarted ?? this.shoppingStarted,
    );
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      NotificationSettingsNotifier.new,
    );

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  @override
  NotificationSettings build() => const NotificationSettings();

  void setItemAdded(bool value) {
    state = state.copyWith(itemAdded: value);
  }

  void setShoppingStarted(bool value) {
    state = state.copyWith(shoppingStarted: value);
  }
}
