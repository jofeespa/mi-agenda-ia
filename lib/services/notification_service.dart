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
      // Si el dispositivo no entrega una zona válida, timezone usa UTC.
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

  Future<void> schedule(AgendaItem item) async {
    final dateTime = item.dateTime;
    if (dateTime == null || !dateTime.isAfter(DateTime.now())) {
      return;
    }

    await init();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'agenda_reminders',
        'Recordatorios',
        channelDescription:
            'Avisos de tareas y recordatorios de Mi Agenda IA',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

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

  int _notificationId(String source) {
    // FNV-1a de 32 bits: estable entre ejecuciones y positivo para Android.
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
        AgendaItemType.event => 'Evento de agenda',
      };
}
