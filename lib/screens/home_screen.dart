import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/agenda_item.dart';
import '../services/intent_parser.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/item_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _speech = stt.SpeechToText();
  final _parser = IntentParser();
  final _storage = StorageService();
  final _notifications = NotificationService();
  final _typedController = TextEditingController();
  List<AgendaItem> _items = [];
  bool _listening = false;
  String _heard = '';

  @override
  void initState() {
    super.initState();
    _load();
    _notifications.init();
  }

  Future<void> _load() async {
    final items = await _storage.loadItems();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available) {
      if (mounted) _showTypedFallback();
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await _speech.listen(
      localeId: 'es_EC',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      ),
      onResult: (result) {
        setState(() => _heard = result.recognizedWords);
        if (result.finalResult && _heard.trim().isNotEmpty) {
          _speech.stop();
          setState(() => _listening = false);
          _confirmIntent(_heard);
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
    if (_heard.trim().isNotEmpty) await _confirmIntent(_heard);
  }

  Future<void> _confirmIntent(String text) async {
    var parsed = _parser.parse(text);
    AgendaItemType selectedType = parsed.type;
    DateTime? selectedDate = parsed.dateTime;

    if (!mounted) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            22,
            22,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('He entendido esto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(parsed.title, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 18),
              DropdownButtonFormField<AgendaItemType>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: AgendaItemType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(_typeName(t))))
                    .toList(),
                onChanged: (v) => setSheetState(() => selectedType = v ?? selectedType),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(selectedDate == null ? 'Sin fecha ni hora' : _formatDate(selectedDate!)),
                subtitle: const Text('Toca para corregir fecha y hora'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    initialDate: selectedDate ?? DateTime.now(),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDate ?? DateTime.now()),
                  );
                  if (time == null) return;
                  setSheetState(() => selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (accepted != true) return;
    final item = AgendaItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: selectedType,
      title: parsed.title,
      rawText: parsed.rawText,
      dateTime: selectedDate,
      createdAt: DateTime.now(),
    );
    setState(() => _items = [item, ..._items]);
    await _storage.saveItems(_items);
    if (item.type != AgendaItemType.note && item.dateTime != null) {
      await _notifications.schedule(item);
    }
  }

  void _showTypedFallback() {
    _typedController.clear();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escribe tu orden'),
        content: TextField(
          controller: _typedController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Ej.: Recuérdame llamar a Juan mañana a las 9',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final text = _typedController.text.trim();
              Navigator.pop(context);
              if (text.isNotEmpty) _confirmIntent(text);
            },
            child: const Text('Interpretar'),
          ),
        ],
      ),
    );
  }

  int _count(AgendaItemType type) => _items.where((e) => e.type == type).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverList.list(children: [
                Row(
                  children: [
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¡Hola! 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                        Text('Tu asistente personal', style: TextStyle(color: Color(0xFF64748B))),
                      ],
                    )),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0759D8), Color(0xFF0B78F0)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summary('Recordatorios', _count(AgendaItemType.reminder), Icons.notifications_none),
                      _summary('Tareas', _count(AgendaItemType.task), Icons.task_alt),
                      _summary('Notas', _count(AgendaItemType.note), Icons.sticky_note_2_outlined),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const Text('Dímelo y yo lo organizo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('“Anota una idea…”, “Recuérdame…”, “Agenda…” o “Tengo que…”', style: TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 22),
                Center(
                  child: GestureDetector(
                    onTap: _listening ? _stopListening : _startListening,
                    onLongPress: _showTypedFallback,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _listening ? 148 : 132,
                      height: _listening ? 148 : 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF075FE4),
                        boxShadow: [BoxShadow(color: const Color(0xFF075FE4).withValues(alpha: .28), blurRadius: 30, spreadRadius: 8)],
                      ),
                      child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 58),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(child: Text(_listening ? (_heard.isEmpty ? 'Te escucho…' : _heard) : 'Toca para hablar · Mantén para escribir', textAlign: TextAlign.center)),
                const SizedBox(height: 30),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Reciente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  TextButton(onPressed: _showTypedFallback, child: const Text('Añadir manual')),
                ]),
              ]),
            ),
            if (_items.isEmpty)
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('Todavía no hay elementos. Prueba diciendo:\n“Recuérdame revisar el informe mañana a las 9”', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B)))),
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: _items.length > 8 ? 8 : _items.length,
                  itemBuilder: (context, index) => ItemCard(item: _items[index]),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Calendario'),
          NavigationDestination(icon: Icon(Icons.sticky_note_2_outlined), label: 'Notas'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _summary(String label, int value, IconData icon) => Column(
    children: [
      Icon(icon, color: Colors.white),
      const SizedBox(height: 6),
      Text('$value', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ],
  );

  String _typeName(AgendaItemType type) => switch (type) {
    AgendaItemType.note => 'Nota',
    AgendaItemType.task => 'Tarea',
    AgendaItemType.reminder => 'Recordatorio',
    AgendaItemType.event => 'Calendario',
  };

  String _formatDate(DateTime dt) {
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} · ${dt.hour}:$minute';
  }
}
