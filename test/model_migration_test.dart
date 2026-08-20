import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agenda_ia/models/agenda_item.dart';
import 'package:mi_agenda_ia/models/app_settings.dart';

void main() {
  test('migra elementos antiguos con valores seguros', () {
    final item = AgendaItem.fromMap(<String, dynamic>{
      'id': '1',
      'type': 'task',
      'title': 'Tarea antigua',
      'rawText': 'Tarea antigua',
      'completed': false,
      'createdAt': '2026-08-19T10:00:00.000',
    });

    expect(item.progress, 0);
    expect(item.alertMode, AlertMode.soundAndVibration);
    expect(item.alarmDurationSeconds, 30);
    expect(item.repeatMinutes, 0);
    expect(item.advanceMinutes, 0);
    expect(item.archived, false);
  });

  test('conserva voz y opciones de alarma', () {
    final original = AgendaItem(
      id: '2',
      type: AgendaItemType.reminder,
      title: 'Pastilla',
      rawText: 'Tomar pastilla',
      dateTime: DateTime(2026, 8, 24, 8),
      alertMode: AlertMode.voice,
      alarmDurationSeconds: 20,
      repeatMinutes: 10,
      advanceMinutes: 30,
      createdAt: DateTime(2026, 8, 19, 10),
      updatedAt: DateTime(2026, 8, 19, 11),
    );

    final decoded = AgendaItem.fromJson(original.toJson());

    expect(decoded.alertMode, AlertMode.voice);
    expect(decoded.alarmDurationSeconds, 20);
    expect(decoded.repeatMinutes, 10);
    expect(decoded.advanceMinutes, 30);
  });

  test('preferencias usan treinta segundos por defecto', () {
    const settings = AppSettings();

    expect(settings.defaultAlarmDurationSeconds, 30);
    expect(settings.defaultRepeatMinutes, 0);
    expect(settings.defaultAdvanceMinutes, 0);
  });
}
