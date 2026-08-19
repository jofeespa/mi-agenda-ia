import '../models/agenda_item.dart';

class ParsedIntent {
  const ParsedIntent({
    required this.type,
    required this.title,
    required this.rawText,
    this.dateTime,
  });

  final AgendaItemType type;
  final String title;
  final DateTime? dateTime;
  final String rawText;
}

class IntentParser {
  ParsedIntent parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final text = input.trim();
    final normalized = _normalize(text);

    final dateTime = _extractDateTime(normalized, reference);
    final type = _inferType(normalized, dateTime);
    final title = _cleanTitle(text);

    return ParsedIntent(
      type: type,
      title: title.isEmpty ? text : title,
      rawText: text,
      dateTime: dateTime,
    );
  }

  AgendaItemType _inferType(String text, DateTime? dateTime) {
    if (_containsAny(
      text,
      <String>['anota', 'nota', 'guardar idea', 'guarda esta idea', 'apunta', 'escribe'],
    )) {
      return AgendaItemType.note;
    }

    if (_containsAny(
      text,
      <String>['agenda', 'agendar', 'programa una reunion', 'reunion', 'cita', 'evento'],
    )) {
      return AgendaItemType.event;
    }

    if (_containsAny(
      text,
      <String>['recuerdame', 'recordatorio', 'avisame', 'notificame'],
    )) {
      return AgendaItemType.reminder;
    }

    if (_containsAny(
      text,
      <String>['tarea', 'tengo que', 'debo', 'pendiente', 'entregar'],
    )) {
      return AgendaItemType.task;
    }

    return dateTime == null ? AgendaItemType.note : AgendaItemType.reminder;
  }

  DateTime? _extractDateTime(String text, DateTime now) {
    final day = _extractDay(text, now);
    final time = _extractTime(text);

    // Evita convertir números de una nota ("capítulo 5") en una hora.
    if (day == null && time == null) {
      return null;
    }

    final effectiveDay = day ?? DateTime(now.year, now.month, now.day);
    final effectiveHour = time?.$1 ?? 9;
    final effectiveMinute = time?.$2 ?? 0;

    var result = DateTime(
      effectiveDay.year,
      effectiveDay.month,
      effectiveDay.day,
      effectiveHour,
      effectiveMinute,
    );

    // Si solo se indicó una hora y ya pasó, se interpreta como mañana.
    if (day == null && result.isBefore(now)) {
      result = result.add(const Duration(days: 1));
    }

    return result;
  }

  DateTime? _extractDay(String text, DateTime now) {
    if (text.contains('hoy')) {
      return DateTime(now.year, now.month, now.day);
    }

    if (text.contains('manana')) {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }

    const weekdays = <String, int>{
      'lunes': DateTime.monday,
      'martes': DateTime.tuesday,
      'miercoles': DateTime.wednesday,
      'jueves': DateTime.thursday,
      'viernes': DateTime.friday,
      'sabado': DateTime.saturday,
      'domingo': DateTime.sunday,
    };

    for (final entry in weekdays.entries) {
      if (!text.contains(entry.key)) {
        continue;
      }

      var delta = (entry.value - now.weekday) % 7;
      if (delta == 0) {
        delta = 7;
      }
      final target = now.add(Duration(days: delta));
      return DateTime(target.year, target.month, target.day);
    }

    return null;
  }

  (int, int)? _extractTime(String text) {
    // 08:30 / 8:30, opcionalmente am/pm.
    final colonTime = RegExp(
      r'\b(\d{1,2}):(\d{2})\s*(am|pm)?\b',
    ).firstMatch(text);
    if (colonTime != null) {
      return _normalizeClock(
        int.parse(colonTime.group(1)!),
        int.parse(colonTime.group(2)!),
        colonTime.group(3),
        text,
      );
    }

    // "a las 9", "a la 1", "9 am", "3 de la tarde".
    final spokenTime = RegExp(
      r'(?:\ba\s+las?\s+)?\b(\d{1,2})\s*(am|pm|de la manana|de la tarde|de la noche)\b',
    ).firstMatch(text);
    if (spokenTime != null) {
      final suffix = spokenTime.group(2);
      String? meridiem;
      if (suffix == 'am' || suffix == 'pm') {
        meridiem = suffix;
      }

      return _normalizeClock(
        int.parse(spokenTime.group(1)!),
        0,
        meridiem,
        text,
      );
    }

    // "a las 9" / "a la 1" sin sufijo.
    final explicitHour = RegExp(
      r'\ba\s+las?\s+(\d{1,2})\b',
    ).firstMatch(text);
    if (explicitHour != null) {
      return _normalizeClock(
        int.parse(explicitHour.group(1)!),
        0,
        null,
        text,
      );
    }

    return null;
  }

  (int, int) _normalizeClock(
    int hour,
    int minute,
    String? meridiem,
    String fullText,
  ) {
    if (hour > 23 || minute > 59) {
      return (9, 0);
    }

    var adjustedHour = hour;

    if (meridiem == 'pm' && adjustedHour < 12) {
      adjustedHour += 12;
    } else if (meridiem == 'am' && adjustedHour == 12) {
      adjustedHour = 0;
    } else if (meridiem == null) {
      if ((fullText.contains('de la tarde') ||
              fullText.contains('de la noche')) &&
          adjustedHour < 12) {
        adjustedHour += 12;
      }
    }

    return (adjustedHour, minute);
  }

  String _cleanTitle(String text) {
    var cleaned = text.trim();

    final prefixes = <RegExp>[
      RegExp(r'^recu[eé]rdame\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^av[ií]same\s+(que\s+)?', caseSensitive: false),
      RegExp(r'^notif[ií]came\s+(que\s+)?', caseSensitive: false),
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
