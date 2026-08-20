import 'package:flutter/services.dart';

import '../models/agenda_item.dart';

class RingtoneSelection {
  const RingtoneSelection({
    required this.uri,
    required this.title,
  });

  final String uri;
  final String title;
}

class AlarmAction {
  const AlarmAction({
    required this.action,
    required this.itemId,
  });

  final String action;
  final String itemId;
}

class AlarmBridge {
  static const MethodChannel _channel =
      MethodChannel('com.miagendaia/alarm');

  Future<void> requestPermissions() {
    return _channel.invokeMethod<void>(
      'requestAlarmPermissions',
    );
  }

  Future<RingtoneSelection?> pickRingtone(
    String? currentUri,
  ) async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>(
      'pickRingtone',
      <String, dynamic>{
        'currentUri': currentUri,
      },
    );

    if (result == null) {
      return null;
    }

    final uri = result['uri'] as String?;
    final title = result['title'] as String?;

    if (uri == null || title == null) {
      return null;
    }

    return RingtoneSelection(
      uri: uri,
      title: title,
    );
  }

  Future<void> previewRingtone(String uri) {
    return _channel.invokeMethod<void>(
      'previewRingtone',
      <String, dynamic>{'uri': uri},
    );
  }

  Future<void> stopRingtonePreview() {
    return _channel.invokeMethod<void>(
      'stopRingtonePreview',
    );
  }

  Future<void> cancelItem(String itemId) {
    return _channel.invokeMethod<void>(
      'cancelItem',
      <String, dynamic>{'id': itemId},
    );
  }

  Future<AlarmAction?> consumePendingAction() async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>(
      'consumePendingAction',
    );

    if (result == null) {
      return null;
    }

    final action = result['action'] as String?;
    final itemId = result['itemId'] as String?;

    if (action == null || itemId == null) {
      return null;
    }

    return AlarmAction(
      action: action,
      itemId: itemId,
    );
  }

  Future<void> scheduleItem(AgendaItem item) async {
    await cancelItem(item.id);

    if (item.type == AgendaItemType.note ||
        item.dateTime == null ||
        item.archived) {
      return;
    }

    await requestPermissions();

    for (final occurrence in _occurrences(item)) {
      if (!occurrence.isAfter(DateTime.now())) {
        continue;
      }

      await _channel.invokeMethod<void>(
        'scheduleAlarm',
        <String, dynamic>{
          'id': item.id,
          'title': item.title,
          'timestamp': occurrence.millisecondsSinceEpoch,
          'alertMode': item.alertMode.name,
          'ringtoneUri': item.ringtoneUri ?? '',
          'occurrenceKey':
              occurrence.millisecondsSinceEpoch.toString(),
        },
      );
    }
  }

  List<DateTime> _occurrences(AgendaItem item) {
    final start = item.dateTime!;

    if (item.recurrence == RecurrenceType.none) {
      return <DateTime>[start];
    }

    final end =
        item.recurrenceEnd ??
        start.add(const Duration(days: 365));
    final result = <DateTime>[];

    switch (item.recurrence) {
      case RecurrenceType.none:
        result.add(start);
      case RecurrenceType.daily:
        var current = start;
        while (!current.isAfter(end) &&
            result.length < 370) {
          result.add(current);
          current =
              current.add(const Duration(days: 1));
        }
      case RecurrenceType.weekly:
        final days = item.weekdays.isEmpty
            ? <int>[start.weekday]
            : item.weekdays;

        var date =
            DateTime(start.year, start.month, start.day);

        while (!date.isAfter(end) &&
            result.length < 370) {
          if (days.contains(date.weekday)) {
            final occurrence = DateTime(
              date.year,
              date.month,
              date.day,
              start.hour,
              start.minute,
            );

            if (!occurrence.isBefore(start) &&
                !occurrence.isAfter(end)) {
              result.add(occurrence);
            }
          }

          date = date.add(const Duration(days: 1));
        }
      case RecurrenceType.monthly:
        var year = start.year;
        var month = start.month;

        while (result.length < 120) {
          final lastDay =
              DateTime(year, month + 1, 0).day;
          final day = start.day > lastDay
              ? lastDay
              : start.day;

          final occurrence = DateTime(
            year,
            month,
            day,
            start.hour,
            start.minute,
          );

          if (occurrence.isAfter(end)) {
            break;
          }

          if (!occurrence.isBefore(start)) {
            result.add(occurrence);
          }

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
