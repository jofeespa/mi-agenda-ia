import 'package:flutter/material.dart';

import '../models/agenda_item.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    this.onTap,
  });

  final AgendaItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final data = _visual(item.type);

    return Card(
      elevation: 0,
      color: const Color(0xFFF7F9FD),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: data.$2.withValues(alpha: 0.12),
          child: Icon(data.$1, color: data.$2),
        ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.dateTime == null
            ? Text(data.$3)
            : Text('${data.$3} · ${_format(item.dateTime!)}'),
        trailing: item.completed
            ? const Icon(
                Icons.check_circle,
                color: Color(0xFF0B66E4),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  (IconData, Color, String) _visual(AgendaItemType type) => switch (type) {
        AgendaItemType.note => (
            Icons.sticky_note_2_outlined,
            const Color(0xFF4A78C2),
            'Nota',
          ),
        AgendaItemType.task => (
            Icons.task_alt,
            const Color(0xFF1769E0),
            'Tarea',
          ),
        AgendaItemType.reminder => (
            Icons.notifications_none,
            const Color(0xFF0057D9),
            'Recordatorio',
          ),
        AgendaItemType.event => (
            Icons.calendar_month_outlined,
            const Color(0xFF164A9A),
            'Calendario',
          ),
      };

  String _format(DateTime dateTime) {
    const months = <String>[
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];

    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} ${months[dateTime.month - 1]}, $hour:$minute';
  }
}
