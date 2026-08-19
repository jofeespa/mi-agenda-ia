import 'package:flutter/material.dart';

import '../models/agenda_item.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final AgendaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = _visual(item.type);

    return Card(
      elevation: 0,
      color: const Color(0xFFF6F8FC),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.dateTime == null
                  ? data.$3
                  : '${data.$3} · ${_format(item.dateTime!)}',
            ),
            if (item.type == AgendaItemType.task) ...[
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: item.progress / 100,
                minHeight: 5,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 3),
              Text('${item.progress}% de avance'),
            ],
          ],
        ),
        trailing: const Icon(Icons.edit_outlined),
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
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} ${months[dateTime.month - 1]}, $hour:$minute';
  }
}
