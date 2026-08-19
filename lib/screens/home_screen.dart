import 'dart:async';

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
  final stt.SpeechToText _speech = stt.SpeechToText();
  final IntentParser _parser = IntentParser();
  final StorageService _storage = StorageService();
  final NotificationService _notifications = NotificationService();
  final TextEditingController _typedController = TextEditingController();

  List<AgendaItem> _items = <AgendaItem>[];
  bool _listening = false;
  bool _speechReady = false;
  String? _speechLocaleId;
  String _heard = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_initializeSpeech());
    unawaited(_notifications.init());
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _typedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _storage.loadItems();
    if (!mounted) {
      return;
    }
    setState(() => _items = items);
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize();
      String? localeId;

      if (available) {
        final locales = await _speech.locales();

        for (final preferred in <String>['es_EC', 'es-EC', 'es_ES', 'es-ES']) {
          for (final locale in locales) {
            if (locale.localeId.toLowerCase() == preferred.toLowerCase()) {
              localeId = locale.localeId;
              break;
            }
          }
          if (localeId != null) {
            break;
          }
        }

        if (localeId == null) {
          for (final locale in locales) {
            if (locale.localeId.toLowerCase().startsWith('es')) {
              localeId = locale.localeId;
              break;
            }
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _speechReady = available;
        _speechLocaleId = localeId;
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() => _speechReady = false);
    }
  }

  Future<void> _startListening() async {
    if (!_speechReady) {
      _showTypedFallback();
      return;
    }

    if (mounted) {
      setState(() {
        _listening = true;
        _heard = '';
      });
    }

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _speechLocaleId,
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(seconds: 30),
        ),
        onResult: (result) {
          if (!mounted) {
            return;
          }

          final recognized = result.recognizedWords.trim();
          setState(() => _heard = recognized);

          if (result.finalResult && recognized.isNotEmpty) {
            unawaited(_speech.stop());
            setState(() => _listening = false);
            unawaited(_confirmIntent(recognized));
          }
        },
      );
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() => _listening = false);
      _showTypedFallback();
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();

    if (!mounted) {
      return;
    }

    setState(() => _listening = false);
    final text = _heard.trim();
    if (text.isNotEmpty) {
      await _confirmIntent(text);
    }
  }

  Future<void> _confirmIntent(String text) async {
    final parsed = _parser.parse(text);
    var selectedType = parsed.type;
    var selectedDate = parsed.dateTime;

    if (!mounted) {
      return;
    }

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            22,
            22,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'He entendido esto',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                parsed.title,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<AgendaItemType>(
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: AgendaItemType.values
                    .map(
                      (type) => DropdownMenuItem<AgendaItemType>(
                        value: type,
                        child: Text(_typeName(type)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setSheetState(() {
                    selectedType = value ?? selectedType;
                  });
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(
                  selectedDate == null
                      ? 'Sin fecha ni hora'
                      : _formatDate(selectedDate!),
                ),
                subtitle: const Text('Toca para corregir fecha y hora'),
                onTap: () async {
                  final now = DateTime.now();
                  final initialDate = selectedDate != null &&
                          selectedDate!.isAfter(
                            now.subtract(const Duration(days: 1)),
                          )
                      ? selectedDate!
                      : now;

                  final date = await showDatePicker(
                    context: sheetContext,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: DateTime(now.year + 10, now.month, now.day),
                    initialDate: initialDate,
                  );

                  if (date == null || !sheetContext.mounted) {
                    return;
                  }

                  final time = await showTimePicker(
                    context: sheetContext,
                    initialTime: TimeOfDay.fromDateTime(
                      selectedDate ?? DateTime.now(),
                    ),
                  );

                  if (time == null) {
                    return;
                  }

                  setSheetState(() {
                    selectedDate = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (accepted != true || !mounted) {
      return;
    }

    final item = AgendaItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: selectedType,
      title: parsed.title,
      rawText: parsed.rawText,
      dateTime: selectedDate,
      createdAt: DateTime.now(),
    );

    final updated = <AgendaItem>[item, ..._items];
    setState(() => _items = updated);
    await _storage.saveItems(updated);

    if (item.type != AgendaItemType.note && item.dateTime != null) {
      await _notifications.schedule(item);
    }
  }

  void _showTypedFallback() {
    _typedController.clear();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = _typedController.text.trim();
              Navigator.pop(dialogContext);
              if (text.isNotEmpty) {
                unawaited(_confirmIntent(text));
              }
            },
            child: const Text('Interpretar'),
          ),
        ],
      ),
    );
  }

  int _count(AgendaItemType type) =>
      _items.where((item) => item.type == type).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '¡Hola! 👋',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Tu asistente personal',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0759D8),
                          Color(0xFF0B78F0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summary(
                          'Recordatorios',
                          _count(AgendaItemType.reminder),
                          Icons.notifications_none,
                        ),
                        _summary(
                          'Tareas',
                          _count(AgendaItemType.task),
                          Icons.task_alt,
                        ),
                        _summary(
                          'Notas',
                          _count(AgendaItemType.note),
                          Icons.sticky_note_2_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Dímelo y yo lo organizo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '“Anota una idea…”, “Recuérdame…”, “Agenda…” o “Tengo que…”',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
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
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF075FE4)
                                  .withValues(alpha: 0.28),
                              blurRadius: 30,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(
                          _listening
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: 58,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      _listening
                          ? (_heard.isEmpty ? 'Te escucho…' : _heard)
                          : _speechReady
                              ? 'Toca para hablar · Mantén para escribir'
                              : 'Mantén para escribir · Voz no disponible aún',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Reciente',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextButton(
                        onPressed: _showTypedFallback,
                        child: const Text('Añadir manual'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      'Todavía no hay elementos. Prueba diciendo:\n'
                      '“Recuérdame revisar el informe mañana a las 9”',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: _items.length > 8 ? 8 : _items.length,
                  itemBuilder: (context, index) =>
                      ItemCard(item: _items[index]),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _summary(String label, int value, IconData icon) => Column(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      );

  String _typeName(AgendaItemType type) => switch (type) {
        AgendaItemType.note => 'Nota',
        AgendaItemType.task => 'Tarea',
        AgendaItemType.reminder => 'Recordatorio',
        AgendaItemType.event => 'Calendario',
      };

  String _formatDate(DateTime dateTime) {
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} · '
        '${dateTime.hour}:$minute';
  }
}
