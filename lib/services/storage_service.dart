import 'package:shared_preferences/shared_preferences.dart';

import '../models/agenda_item.dart';
import '../models/app_settings.dart';

class StorageService {
  static const _itemsKey = 'agenda_items_v1';
  static const _nameKey = 'user_name_v1';
  static const _settingsKey = 'app_settings_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<AgendaItem>> loadItems() async {
    final rows = await _preferences.getStringList(_itemsKey) ?? <String>[];
    final items = <AgendaItem>[];
    for (final row in rows) {
      try {
        items.add(AgendaItem.fromJson(row));
      } on FormatException {
        // Ignora registros dañados.
      } on TypeError {
        // Ignora registros incompatibles.
      }
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> saveItems(List<AgendaItem> items) =>
      _preferences.setStringList(
        _itemsKey,
        items.map((item) => item.toJson()).toList(growable: false),
      );

  Future<String?> loadUserName() => _preferences.getString(_nameKey);

  Future<void> saveUserName(String name) =>
      _preferences.setString(_nameKey, name.trim());

  Future<AppSettings> loadSettings() async {
    final raw = await _preferences.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(raw);
    } on FormatException {
      return const AppSettings();
    } on TypeError {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) =>
      _preferences.setString(_settingsKey, settings.toJson());
}
