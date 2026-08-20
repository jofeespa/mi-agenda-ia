import 'dart:convert';

enum AgendaItemType { note, task, reminder, event }

enum AlertMode {
  soundAndVibration,
  strong,
  soundOnly,
  voice,
  toneAndVoice,
  vibrationOnly,
  silent,
}

enum RecurrenceType { none, daily, weekly, monthly }

class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.rawText,
    required this.createdAt,
    required this.updatedAt,
    this.dateTime,
    this.completed = false,
    this.progress = 0,
    this.alertMode = AlertMode.soundAndVibration,
    this.ringtoneUri,
    this.ringtoneTitle,
    this.alarmDurationSeconds = 30,
    this.repeatMinutes = 0,
    this.advanceMinutes = 0,
    this.recurrence = RecurrenceType.none,
    this.weekdays = const <int>[],
    this.recurrenceEnd,
    this.archived = false,
    this.archivedAt,
  });

  final String id;
  final AgendaItemType type;
  final String title;
  final String rawText;
  final DateTime? dateTime;
  final bool completed;
  final int progress;
  final AlertMode alertMode;
  final String? ringtoneUri;
  final String? ringtoneTitle;
  final int alarmDurationSeconds;
  final int repeatMinutes;
  final int advanceMinutes;
  final RecurrenceType recurrence;
  final List<int> weekdays;
  final DateTime? recurrenceEnd;
  final bool archived;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'title': title,
        'rawText': rawText,
        'dateTime': dateTime?.toIso8601String(),
        'completed': completed,
        'progress': progress,
        'alertMode': alertMode.name,
        'ringtoneUri': ringtoneUri,
        'ringtoneTitle': ringtoneTitle,
        'alarmDurationSeconds': alarmDurationSeconds,
        'repeatMinutes': repeatMinutes,
        'advanceMinutes': advanceMinutes,
        'recurrence': recurrence.name,
        'weekdays': weekdays,
        'recurrenceEnd': recurrenceEnd?.toIso8601String(),
        'archived': archived,
        'archivedAt': archivedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgendaItem.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['createdAt'] as String);

    AgendaItemType type;
    try {
      type = AgendaItemType.values.byName(map['type'] as String);
    } on ArgumentError {
      type = AgendaItemType.note;
    }

    AlertMode alertMode;
    try {
      final raw = map['alertMode'] as String?;
      if (raw == 'normal') {
        alertMode = AlertMode.soundAndVibration;
      } else if (raw == 'vibration') {
        alertMode = AlertMode.vibrationOnly;
      } else {
        alertMode = AlertMode.values.byName(
          raw ?? AlertMode.soundAndVibration.name,
        );
      }
    } on ArgumentError {
      alertMode = AlertMode.soundAndVibration;
    }

    RecurrenceType recurrence;
    try {
      recurrence = RecurrenceType.values.byName(
        map['recurrence'] as String? ?? RecurrenceType.none.name,
      );
    } on ArgumentError {
      recurrence = RecurrenceType.none;
    }

    final rawProgress = map['progress'];
    final progress = rawProgress is int ? rawProgress.clamp(0, 100) : 0;
    final rawWeekdays = map['weekdays'];
    final weekdays = rawWeekdays is List
        ? rawWeekdays.whereType<num>().map((e) => e.toInt()).toList()
        : <int>[];

    return AgendaItem(
      id: map['id'] as String,
      type: type,
      title: map['title'] as String,
      rawText: map['rawText'] as String? ?? map['title'] as String,
      dateTime: map['dateTime'] == null
          ? null
          : DateTime.parse(map['dateTime'] as String),
      completed: map['completed'] as bool? ?? false,
      progress: progress,
      alertMode: alertMode,
      ringtoneUri: map['ringtoneUri'] as String?,
      ringtoneTitle: map['ringtoneTitle'] as String?,
      alarmDurationSeconds: map['alarmDurationSeconds'] as int? ?? 30,
      repeatMinutes: map['repeatMinutes'] as int? ?? 0,
      advanceMinutes: map['advanceMinutes'] as int? ?? 0,
      recurrence: recurrence,
      weekdays: weekdays,
      recurrenceEnd: map['recurrenceEnd'] == null
          ? null
          : DateTime.parse(map['recurrenceEnd'] as String),
      archived: map['archived'] as bool? ?? false,
      archivedAt: map['archivedAt'] == null
          ? null
          : DateTime.parse(map['archivedAt'] as String),
      createdAt: createdAt,
      updatedAt: map['updatedAt'] == null
          ? createdAt
          : DateTime.parse(map['updatedAt'] as String),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AgendaItem.fromJson(String source) =>
      AgendaItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
