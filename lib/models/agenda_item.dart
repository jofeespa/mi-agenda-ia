import 'dart:convert';

enum AgendaItemType { note, task, reminder, event }

enum AlertMode { normal, strong, vibration, silent }

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
    this.alertMode = AlertMode.normal,
  });

  final String id;
  final AgendaItemType type;
  final String title;
  final String rawText;
  final DateTime? dateTime;
  final bool completed;
  final int progress;
  final AlertMode alertMode;
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
      alertMode = AlertMode.values.byName(
        map['alertMode'] as String? ?? AlertMode.normal.name,
      );
    } on ArgumentError {
      alertMode = AlertMode.normal;
    }

    final rawProgress = map['progress'];
    final progress = rawProgress is int ? rawProgress.clamp(0, 100) : 0;

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
