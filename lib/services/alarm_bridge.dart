import 'package:flutter/services.dart';
import '../models/agenda_item.dart';

class AlarmAction {
  const AlarmAction({required this.action, required this.itemId});
  final String action;
  final String itemId;
}

class AlarmBridge {
  static const MethodChannel _channel = MethodChannel('com.miagendaia/alarm');
  Future<void> requestPermissions() => _channel.invokeMethod<void>('requestAlarmPermissions');
  Future<void> cancelItem(String itemId) => _channel.invokeMethod<void>('cancelItem', {'id': itemId});

  Future<AlarmAction?> consumePendingAction() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('consumePendingAction');
    if (raw == null) return null;
    final action = raw['action'] as String?; final itemId = raw['itemId'] as String?;
    if (action == null || itemId == null) return null;
    return AlarmAction(action: action, itemId: itemId);
  }

  Future<void> scheduleItem(AgendaItem item) async {
    await cancelItem(item.id);
    if (item.type == AgendaItemType.note || item.dateTime == null || item.archived) return;
    await requestPermissions();
    for (final occurrence in _occurrences(item)) {
      if (!occurrence.isAfter(DateTime.now())) continue;
      await _channel.invokeMethod<void>('scheduleAlarm', {
        'id': item.id,
        'title': item.title,
        'timestamp': occurrence.millisecondsSinceEpoch,
        'alertMode': item.alertMode.name,
        'occurrenceKey': occurrence.millisecondsSinceEpoch.toString(),
      });
    }
  }

  List<DateTime> _occurrences(AgendaItem item) {
    final start = item.dateTime!;
    if (item.recurrence == RecurrenceType.none) return [start];
    final end = item.recurrenceEnd ?? start.add(const Duration(days: 365));
    final result = <DateTime>[];
    switch (item.recurrence) {
      case RecurrenceType.none:
        result.add(start);
      case RecurrenceType.daily:
        var current = start;
        while (!current.isAfter(end) && result.length < 370) { result.add(current); current = current.add(const Duration(days: 1)); }
      case RecurrenceType.weekly:
        final days = item.weekdays.isEmpty ? <int>[start.weekday] : item.weekdays;
        var date = DateTime(start.year, start.month, start.day);
        while (!date.isAfter(end) && result.length < 370) {
          if (days.contains(date.weekday)) {
            final o = DateTime(date.year,date.month,date.day,start.hour,start.minute);
            if (!o.isBefore(start) && !o.isAfter(end)) result.add(o);
          }
          date = date.add(const Duration(days: 1));
        }
      case RecurrenceType.monthly:
        var year=start.year, month=start.month;
        while (result.length < 120) {
          final lastDay = DateTime(year, month + 1, 0).day;
          final day = start.day > lastDay ? lastDay : start.day;
          final o = DateTime(year,month,day,start.hour,start.minute);
          if (o.isAfter(end)) break;
          if (!o.isBefore(start)) result.add(o);
          month += 1; if (month == 13) { month = 1; year += 1; }
        }
    }
    return result;
  }
}
