import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/agenda_item.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final current = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(current.identifier));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> schedule(AgendaItem item) async {
    final dt = item.dateTime;
    if (dt == null || dt.isBefore(DateTime.now())) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'agenda_reminders',
        'Recordatorios',
        channelDescription: 'Avisos de tareas y recordatorios de Mi Agenda IA',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id: item.id.hashCode & 0x7fffffff,
      title: _notificationTitle(item.type),
      body: item.title,
      scheduledDate: tz.TZDateTime.from(dt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: item.id,
    );
  }

  String _notificationTitle(AgendaItemType type) {
    switch (type) {
      case AgendaItemType.note:
        return 'Nota';
      case AgendaItemType.task:
        return 'Tarea pendiente';
      case AgendaItemType.reminder:
        return 'Recordatorio';
      case AgendaItemType.event:
        return 'Evento de agenda';
    }
  }
}
