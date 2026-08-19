import 'package:shared_preferences/shared_preferences.dart';

import '../models/agenda_item.dart';

class StorageService {
  static const String _key = 'agenda_items_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<AgendaItem>> loadItems() async {
    final rows = await _preferences.getStringList(_key) ?? <String>[];

    final items = <AgendaItem>[];
    for (final row in rows) {
      try {
        items.add(AgendaItem.fromJson(row));
      } on FormatException {
        // Ignora una fila dañada en vez de impedir que la app abra.
      } on TypeError {
        // Ignora datos antiguos/incompatibles.
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> saveItems(List<AgendaItem> items) async {
    await _preferences.setStringList(
      _key,
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }
}
