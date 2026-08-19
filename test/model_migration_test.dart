import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agenda_ia/models/agenda_item.dart';

void main() {
  test('carga un elemento de la versión anterior con valores por defecto', () {
    final item = AgendaItem.fromMap(<String, dynamic>{
      'id': '1',
      'type': 'task',
      'title': 'Tarea antigua',
      'rawText': 'Tarea antigua',
      'completed': false,
      'createdAt': '2026-08-19T10:00:00.000',
    });

    expect(item.progress, 0);
    expect(item.alertMode, AlertMode.normal);
    expect(item.updatedAt, item.createdAt);
  });

  test('conserva progreso y tipo de alerta', () {
    final original = AgendaItem(
      id: '2',
      type: AgendaItemType.task,
      title: 'Informe',
      rawText: 'Informe',
      dateTime: DateTime(2026, 8, 20, 9),
      progress: 50,
      alertMode: AlertMode.vibration,
      createdAt: DateTime(2026, 8, 19, 10),
      updatedAt: DateTime(2026, 8, 19, 11),
    );

    final decoded = AgendaItem.fromJson(original.toJson());

    expect(decoded.progress, 50);
    expect(decoded.alertMode, AlertMode.vibration);
    expect(decoded.dateTime, DateTime(2026, 8, 20, 9));
  });
}
