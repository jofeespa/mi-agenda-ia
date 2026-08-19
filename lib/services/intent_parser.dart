import '../models/agenda_item.dart';

class ParsedIntent {
  final AgendaItemType type;
  final String title;
  final DateTime? dateTime;
  final String rawText;

  const ParsedIntent({
    required this.type,
    required this.title,
    required this.rawText,
    this.dateTime,
  });
}

class IntentParser {
  ParsedIntent parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final text = input.trim();
    final lower = _normalize(text);

    final dateTime = _extractDateTime(lower, reference);
    final type = _inferType(lower, dateTime);
    final title = _cleanTitle(text);

    return ParsedIntent(
      type: type,
      title: title.isEmpty ? text : title,
      rawText: text,
      dateTime: dateTime,
    );
  }

  AgendaItemType _inferType(String text, DateTime? dt) {
    if (_containsAny(text, ['anota', 'nota', 'guardar idea', 'apunta', 'escribe'])) {
      return AgendaItemType.note;
    }
    if (_containsAny(text, ['agenda', 'agendar', 'reunion', 'cita', 'evento'])) {
      return AgendaItemType.event;
    }
    if (_containsAny(text, ['recuerdame', 'recordatorio', 'avisame', 'notificame'])) {
      return AgendaItemType.reminder;
    }
    if (_containsAny(text, ['tarea', 'tengo que', 'debo', 'pendiente', 'entregar'])) {
      return AgendaItemType.task;
    }
    return dt != null ? AgendaItemType.reminder : AgendaItemType.note;
  }

  DateTime? _extractDateTime(String text, DateTime now) {
    DateTime? day;
    if (text.contains('hoy')) {
      day = DateTime(now.year, now.month, now.day);
    } else if (text.contains('manana')) {
      final d = now.add(const Duration(days: 1));
      day = DateTime(d.year, d.month, d.day);
    } else {
      const weekdays = {
        'lunes': DateTime.monday,
        'martes': DateTime.tuesday,
        'miercoles': DateTime.wednesday,
        'jueves': DateTime.thursday,
        'viernes': DateTime.friday,
        'sabado': DateTime.saturday,
        'domingo': DateTime.sunday,
      };
      for (final entry in weekdays.entries) {
        if (text.contains(entry.key)) {
          var delta = (entry.value - now.weekday) % 7;
          if (delta == 0) delta = 7;
          final d = now.add(Duration(days: delta));
          day = DateTime(d.year, d.month, d.day);
          break;
        }
      }
    }

    final timeRegex = RegExp(r'(?:a las|alas|a la)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
    final matches = timeRegex.allMatches(text).toList();
    RegExpMatch? timeMatch;
    for (final m in matches.reversed) {
      final hour = int.tryParse(m.group(1) ?? '');
      if (hour != null && hour <= 23) {
        timeMatch = m;
        break;
      }
    }

    if (day == null && timeMatch == null) return null;
    day ??= DateTime(now.year, now.month, now.day);

    var hour = timeMatch == null ? 9 : int.parse(timeMatch.group(1)!);
    final minute = timeMatch?.group(2) == null ? 0 : int.parse(timeMatch!.group(2)!);
    final meridiem = timeMatch?.group(3);

    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    if (meridiem == null) {
      if (text.contains('de la tarde') && hour < 12) hour += 12;
      if (text.contains('de la noche') && hour < 12) hour += 12;
    }

    var result = DateTime(day.year, day.month, day.day, hour, minute);
    if (!text.contains('hoy') && !text.contains('manana') && result.isBefore(now)) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  String _cleanTitle(String text) {
    var cleaned = text.trim();
    final prefixes = [
      RegExp(r'^recu[eé]rdame\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^av[ií]same\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^anota\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^apunta\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^agenda\s+', caseSensitive: false),
      RegExp(r'^programa\s+', caseSensitive: false),
      RegExp(r'^tengo que\s+', caseSensitive: false),
    ];
    for (final pattern in prefixes) {
      cleaned = cleaned.replaceFirst(pattern, '');
    }
    return cleaned.trim();
  }

  bool _containsAny(String source, List<String> values) =>
      values.any(source.contains);

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');
}
