import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agenda_ia/models/agenda_item.dart';
import 'package:mi_agenda_ia/services/intent_parser.dart';

void main() {
  final parser = IntentParser();
  final reference = DateTime(2026, 8, 19, 10, 0);

  test('clasifica una nota sin fecha', () {
    final result = parser.parse('Anota una idea para mi tesis', now: reference);
    expect(result.type, AgendaItemType.note);
    expect(result.dateTime, isNull);
  });

  test('clasifica un recordatorio para mañana', () {
    final result = parser.parse(
      'Recuérdame llamar a Juan mañana a las 9',
      now: reference,
    );
    expect(result.type, AgendaItemType.reminder);
    expect(result.dateTime, DateTime(2026, 8, 20, 9));
  });

  test('clasifica un evento de calendario', () {
    final result = parser.parse(
      'Agenda reunión con el director el jueves a las 3 de la tarde',
      now: reference,
    );
    expect(result.type, AgendaItemType.event);
    expect(result.dateTime, DateTime(2026, 8, 20, 15));
  });

  test('clasifica una tarea', () {
    final result = parser.parse(
      'Tengo que entregar el informe viernes a las 4 de la tarde',
      now: reference,
    );
    expect(result.type, AgendaItemType.task);
    expect(result.dateTime, DateTime(2026, 8, 21, 16));
  });
}
