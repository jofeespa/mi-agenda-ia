import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/agenda_item.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    tz_data.initializeTimeZones();

    try {
      final current = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(current.identifier));
    } on Exception {
      // timezone mantiene UTC si el dispositivo no entrega una zona válida.
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> cancel(String itemId) async {
    await init();
    await _plugin.cancel(id: _notificationId(itemId));
  }

  Future<void> schedule(AgendaItem item) async {
    final dateTime = item.dateTime;
    if (item.type == AgendaItemType.note ||
        dateTime == null ||
        !dateTime.isAfter(DateTime.now())) {
      return;
    }

    await init();
    await cancel(item.id);

    final androidDetails = _androidDetails(item.alertMode);
    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id: _notificationId(item.id),
      title: _notificationTitle(item.type),
      body: item.title,
      scheduledDate: tz.TZDateTime.from(dateTime, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: item.id,
    );
  }

  AndroidNotificationDetails _androidDetails(AlertMode mode) {
    switch (mode) {
      case AlertMode.normal:
        return const AndroidNotificationDetails(
          'agenda_normal_v2',
          'Avisos normales',
          channelDescription: 'Sonido y vibración para Mi Agenda IA',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
      case AlertMode.strong:
        return const AndroidNotificationDetails(
          'agenda_fuerte_v2',
          'Avisos fuertes',
          channelDescription: 'Avisos prioritarios con sonido y vibración',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          ticker: 'Mi Agenda IA',
        );
      case AlertMode.vibration:
        return const AndroidNotificationDetails(
          'agenda_vibracion_v2',
          'Solo vibración',
          channelDescription: 'Avisos sin sonido, con vibración',
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          enableVibration: true,
        );
      case AlertMode.silent:
        return const AndroidNotificationDetails(
          'agenda_silencioso_v2',
          'Avisos silenciosos',
          channelDescription: 'Avisos visuales sin sonido ni vibración',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
        );
    }
  }

  int _notificationId(String source) {
    var hash = 0x811C9DC5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  String _notificationTitle(AgendaItemType type) => switch (type) {
        AgendaItemType.note => 'Nota',
        AgendaItemType.task => 'Tarea pendiente',
        AgendaItemType.reminder => 'Recordatorio',
        AgendaItemType.event => 'Evento de calendario',
      };
}
