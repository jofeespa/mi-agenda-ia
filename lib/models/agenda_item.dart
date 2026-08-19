import 'dart:convert';

enum AgendaItemType { note, task, reminder, event }

class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.rawText,
    required this.createdAt,
    this.dateTime,
    this.completed = false,
  });

  final String id;
  final AgendaItemType type;
  final String title;
  final String rawText;
  final DateTime? dateTime;
  final bool completed;
  final DateTime createdAt;

  AgendaItem copyWith({bool? completed}) => AgendaItem(
        id: id,
        type: type,
        title: title,
        rawText: rawText,
        dateTime: dateTime,
        createdAt: createdAt,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'title': title,
        'rawText': rawText,
        'dateTime': dateTime?.toIso8601String(),
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AgendaItem.fromMap(Map<String, dynamic> map) => AgendaItem(
        id: map['id'] as String,
        type: AgendaItemType.values.byName(map['type'] as String),
        title: map['title'] as String,
        rawText: map['rawText'] as String,
        dateTime: map['dateTime'] == null
            ? null
            : DateTime.parse(map['dateTime'] as String),
        completed: map['completed'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  String toJson() => jsonEncode(toMap());

  factory AgendaItem.fromJson(String source) =>
      AgendaItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
