import 'package:flutter/material.dart';
import '../models/agenda_item.dart';

class ItemCard extends StatelessWidget {
  final AgendaItem item;
  final VoidCallback? onTap;

  const ItemCard({super.key, required this.item, this.onTap});

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
          backgroundColor: data.$2.withValues(alpha: .12),
          child: Icon(data.$1, color: data.$2),
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: item.dateTime == null
            ? Text(data.$3)
            : Text('${data.$3} · ${_format(item.dateTime!)}'),
        trailing: item.completed
            ? const Icon(Icons.check_circle, color: Color(0xFF0B66E4))
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  (IconData, Color, String) _visual(AgendaItemType type) {
    switch (type) {
      case AgendaItemType.note:
        return (Icons.sticky_note_2_outlined, const Color(0xFF4A78C2), 'Nota');
      case AgendaItemType.task:
        return (Icons.task_alt, const Color(0xFF1769E0), 'Tarea');
      case AgendaItemType.reminder:
        return (Icons.notifications_none, const Color(0xFF0057D9), 'Recordatorio');
      case AgendaItemType.event:
        return (Icons.calendar_month_outlined, const Color(0xFF164A9A), 'Calendario');
    }
  }

  String _format(DateTime dt) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }
}
