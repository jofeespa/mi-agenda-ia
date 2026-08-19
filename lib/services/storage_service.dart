import 'package:shared_preferences/shared_preferences.dart';
import '../models/agenda_item.dart';

class StorageService {
  static const _key = 'agenda_items_v1';

  Future<List<AgendaItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_key) ?? <String>[];
    return rows.map(AgendaItem.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveItems(List<AgendaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, items.map((e) => e.toJson()).toList());
  }
}
