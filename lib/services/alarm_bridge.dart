import 'package:flutter/services.dart';

import '../models/agenda_item.dart';

class RingtoneSelection {
  const RingtoneSelection({required this.uri, required this.title});
  final String uri;
  final String title;
}

class AlarmAction {
  const AlarmAction({required this.action, required this.itemId});
  final String action;
  final String itemId;
}

class AlarmPermissionStatus {
  const AlarmPermissionStatus({
    required this.notifications,
    required this.exactAlarms,
    required this.fullScreenIntent,
  });

  final bool notifications;
  final bool exactAlarms;
  final bool fullScreenIntent;

  factory AlarmPermissionStatus.fromMap(Map<String, dynamic> raw) {
    return AlarmPermissionStatus(
      notifications: raw['notifications'] == true,
      exactAlarms: raw['exactAlarms'] == true,
      fullScreenIntent: raw['fullScreenIntent'] == true,
    );
  }
}

class AlarmBridge {
  static const MethodChannel _channel =
      MethodChannel('com.miagendaia/alarm');

  Future<void> requestPermissions() =>
      _channel.invokeMethod<void>('requestAlarmPermissions');

  Future<AlarmPermissionStatus> getPermissionStatus() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'getAlarmPermissionStatus',
    );
    return AlarmPermissionStatus.fromMap(raw ?? const <String, dynamic>{});
  }

  Future<RingtoneSelection?> pickRingtone(String? currentUri) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'pickRingtone',
      <String, dynamic>{'currentUri': currentUri},
    );
    if (raw == null) return null;
    final uri = raw['uri'] as String?;
    final title = raw['title'] as String?;
    if (uri == null || title == null) return null;
    return RingtoneSelection(uri: uri, title: title);
  }

  Future<void> previewRingtone(String uri) =>
      _channel.invokeMethod<void>(
        'previewRingtone',
        <String, dynamic>{'uri': uri},
      );

  Future<void> stopRingtonePreview() =>
      _channel.invokeMethod<void>('stopRingtonePreview');

  Future<void> cancelItem(String itemId) =>
      _channel.invokeMethod<void>(
        'cancelItem',
        <String, dynamic>{'id': itemId},
      );

  Future<AlarmAction?> consumePendingAction() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'consumePendingAction',
    );
    if (raw == null) return null;
    final action = raw['action'] as String?;
    final itemId = raw['itemId'] as String?;
    if (action == null || itemId == null) return null;
    return AlarmAction(action: action, itemId: itemId);
  }

  Future<void> scheduleItem(AgendaItem item) async {
    await cancelItem(item.id);
    if (item.type == AgendaItemType.note ||
        item.dateTime == null ||
        item.archived) {
      return;
    }

    for (final occurrence in _occurrences(item)) {
      final triggerAt = occurrence.subtract(
        Duration(minutes: item.advanceMinutes),
      );
      if (!triggerAt.isAfter(DateTime.now())) continue;

      await _channel.invokeMethod<void>(
        'scheduleAlarm',
        <String, dynamic>{
          'id': item.id,
          'title': item.title,
          'itemType': item.type.name,
          'timestamp': triggerAt.millisecondsSinceEpoch,
          'alertMode': item.alertMode.name,
          'ringtoneUri': item.ringtoneUri ?? '',
          'alarmDurationSeconds': item.alarmDurationSeconds,
          'repeatMinutes': item.repeatMinutes,
          'occurrenceKey': occurrence.millisecondsSinceEpoch.toString(),
        },
      );
    }
  }

  List<DateTime> _occurrences(AgendaItem item) {
    final start = item.dateTime!;
    if (item.recurrence == RecurrenceType.none) return <DateTime>[start];

    final end = item.recurrenceEnd ?? start.add(const Duration(days: 365));
    final result = <DateTime>[];

    switch (item.recurrence) {
      case RecurrenceType.none:
        result.add(start);
      case RecurrenceType.daily:
        var current = start;
        while (!current.isAfter(end) && result.length < 370) {
          result.add(current);
          current = current.add(const Duration(days: 1));
        }
      case RecurrenceType.weekly:
        final days =
            item.weekdays.isEmpty ? <int>[start.weekday] : item.weekdays;
        var date = DateTime(start.year, start.month, start.day);
        while (!date.isAfter(end) && result.length < 370) {
          if (days.contains(date.weekday)) {
            final occurrence = DateTime(
              date.year,
              date.month,
              date.day,
              start.hour,
              start.minute,
            );
            if (!occurrence.isBefore(start) && !occurrence.isAfter(end)) {
              result.add(occurrence);
            }
          }
          date = date.add(const Duration(days: 1));
        }
      case RecurrenceType.monthly:
        var year = start.year;
        var month = start.month;
        while (result.length < 120) {
          final lastDay = DateTime(year, month + 1, 0).day;
          final day = start.day > lastDay ? lastDay : start.day;
          final occurrence =
              DateTime(year, month, day, start.hour, start.minute);
          if (occurrence.isAfter(end)) break;
          if (!occurrence.isBefore(start)) result.add(occurrence);
          month += 1;
          if (month == 13) {
            month = 1;
            year += 1;
          }
        }
    }
    return result;
  }
}
