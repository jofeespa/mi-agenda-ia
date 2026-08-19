import 'package:shared_preferences/shared_preferences.dart';

import '../models/agenda_item.dart';

class StorageService {
  static const String _itemsKey = 'agenda_items_v1';
  static const String _nameKey = 'user_name_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<AgendaItem>> loadItems() async {
    final rows = await _preferences.getStringList(_itemsKey) ?? <String>[];

    final items = <AgendaItem>[];
    for (final row in rows) {
      try {
        items.add(AgendaItem.fromJson(row));
      } on FormatException {
        // Ignora un registro dañado para no impedir que la app abra.
      } on TypeError {
        // Ignora registros antiguos incompatibles.
      }
    }

    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> saveItems(List<AgendaItem> items) async {
    await _preferences.setStringList(
      _itemsKey,
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  Future<String?> loadUserName() => _preferences.getString(_nameKey);

  Future<void> saveUserName(String name) =>
      _preferences.setString(_nameKey, name.trim());
}
