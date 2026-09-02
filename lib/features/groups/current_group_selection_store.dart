import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CurrentGroupSelectionStore {
  String? read(String userId);

  Future<void> save(String userId, String groupId);

  Future<void> clear(String userId);
}

class InMemoryCurrentGroupSelectionStore implements CurrentGroupSelectionStore {
  final Map<String, String> _groupIds = {};

  @override
  String? read(String userId) => _groupIds[userId];

  @override
  Future<void> save(String userId, String groupId) async {
    _groupIds[userId] = groupId;
  }

  @override
  Future<void> clear(String userId) async {
    _groupIds.remove(userId);
  }
}

class SharedPreferencesCurrentGroupSelectionStore
    implements CurrentGroupSelectionStore {
  SharedPreferencesCurrentGroupSelectionStore(this._preferences);

  static const _keyPrefix = 'current_group_id_';

  final SharedPreferences _preferences;

  @override
  String? read(String userId) => _preferences.getString('$_keyPrefix$userId');

  @override
  Future<void> save(String userId, String groupId) async {
    await _preferences.setString('$_keyPrefix$userId', groupId);
  }

  @override
  Future<void> clear(String userId) async {
    await _preferences.remove('$_keyPrefix$userId');
  }
}
