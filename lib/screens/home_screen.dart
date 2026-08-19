import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/agenda_item.dart';
import '../services/intent_parser.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/item_card.dart';

enum HomeFilter { all, tasks, reminders }

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
  String _userName = '';
  int _tabIndex = 0;
  HomeFilter _homeFilter = HomeFilter.all;

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
    final name = await _storage.loadUserName();

    if (!mounted) {
      return;
    }

    setState(() {
      _items = items;
      _userName = name?.trim() ?? '';
    });

    if (_userName.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_askName());
        }
      });
    }
  }

  Future<void> _askName() async {
    final controller = TextEditingController(text: _userName);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: _userName.isNotEmpty,
      builder: (dialogContext) => AlertDialog(
        title: Text(_userName.isEmpty ? '¿Cómo te llamas?' : 'Editar nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Tu nombre',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (_userName.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || !mounted) {
      return;
    }

    await _storage.saveUserName(result);
    if (mounted) {
      setState(() => _userName = result);
    }
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
      if (mounted) {
        setState(() => _speechReady = false);
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechReady) {
      _showTypedFallback();
      return;
    }

    setState(() {
      _listening = true;
      _heard = '';
    });

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
            unawaited(_createFromText(recognized));
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
      await _createFromText(text);
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
            hintText: 'Ej.: Recuérdame llamar mañana a las 9',
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
                unawaited(_createFromText(text));
              }
            },
            child: const Text('Interpretar'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFromText(String text) async {
    final parsed = _parser.parse(text);
    final now = DateTime.now();
    final draft = AgendaItem(
      id: now.microsecondsSinceEpoch.toString(),
      type: parsed.type,
      title: parsed.title,
      rawText: parsed.rawText,
      dateTime: parsed.dateTime,
      progress: 0,
      alertMode: AlertMode.normal,
      createdAt: now,
      updatedAt: now,
    );

    await _openEditor(draft, isNew: true);
  }

  Future<void> _openEditor(
    AgendaItem item, {
    required bool isNew,
  }) async {
    final titleController = TextEditingController(text: item.title);
    var selectedType = item.type;
    var selectedDate = item.dateTime;
    var selectedAlert = item.alertMode;
    var progress = item.type == AgendaItemType.task ? item.progress : 0;
    var deleteRequested = false;

    if (!mounted) {
      titleController.dispose();
      return;
    }

    final result = await showModalBottomSheet<AgendaItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final requiresSchedule = selectedType != AgendaItemType.note;

          Future<void> chooseDateTime() async {
            final now = DateTime.now();
            final initial = selectedDate != null &&
                    selectedDate!.isAfter(
                      now.subtract(const Duration(days: 1)),
                    )
                ? selectedDate!
                : now.add(const Duration(hours: 1));

            final date = await showDatePicker(
              context: sheetContext,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 10, 12, 31),
              initialDate: initial,
            );

            if (date == null || !sheetContext.mounted) {
              return;
            }

            final time = await showTimePicker(
              context: sheetContext,
              initialTime: TimeOfDay.fromDateTime(initial),
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
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              22,
              22,
              MediaQuery.of(sheetContext).viewInsets.bottom + 26,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? 'Confirmar actividad' : 'Editar actividad',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
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
                      if (selectedType == AgendaItemType.note) {
                        selectedDate = null;
                        progress = 0;
                      }
                    });
                  },
                ),
                if (requiresSchedule) ...[
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    leading: const Icon(Icons.event_outlined),
                    title: Text(
                      selectedDate == null
                          ? 'Fecha y hora obligatorias'
                          : _formatDate(selectedDate!),
                    ),
                    subtitle: Text(
                      selectedDate == null
                          ? 'Toca para seleccionar cuándo debe avisarte'
                          : 'Toca para cambiar fecha y hora',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseDateTime,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AlertMode>(
                    initialValue: selectedAlert,
                    decoration: const InputDecoration(
                      labelText: 'Cómo quieres que te avise',
                      border: OutlineInputBorder(),
                    ),
                    items: AlertMode.values
                        .map(
                          (mode) => DropdownMenuItem<AlertMode>(
                            value: mode,
                            child: Text(_alertName(mode)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setSheetState(() {
                        selectedAlert = value ?? selectedAlert;
                      });
                    },
                  ),
                ],
                if (selectedType == AgendaItemType.task) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Avance: $progress%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Slider(
                    value: progress.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$progress%',
                    onChanged: (value) {
                      setSheetState(() => progress = value.round());
                    },
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('Escribe un título.'),
                          ),
                        );
                        return;
                      }

                      if (requiresSchedule && selectedDate == null) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Debes seleccionar fecha y hora antes de guardar.',
                            ),
                          ),
                        );
                        return;
                      }

                      final effectiveProgress =
                          selectedType == AgendaItemType.task ? progress : 0;

                      Navigator.pop(
                        sheetContext,
                        AgendaItem(
                          id: item.id,
                          type: selectedType,
                          title: title,
                          rawText: item.rawText,
                          dateTime: requiresSchedule ? selectedDate : null,
                          completed: effectiveProgress == 100,
                          progress: effectiveProgress,
                          alertMode: selectedAlert,
                          createdAt: item.createdAt,
                          updatedAt: DateTime.now(),
                        ),
                      );
                    },
                    child: Text(isNew ? 'Guardar' : 'Guardar cambios'),
                  ),
                ),
                if (!isNew) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Eliminar actividad'),
                            content: const Text(
                              'Esta acción no se puede deshacer.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true && sheetContext.mounted) {
                          deleteRequested = true;
                          Navigator.pop(sheetContext);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar actividad'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    titleController.dispose();

    if (!mounted) {
      return;
    }

    if (deleteRequested) {
      await _notifications.cancel(item.id);
      final updated = _items.where((current) => current.id != item.id).toList();
      setState(() => _items = updated);
      await _storage.saveItems(updated);
      return;
    }

    if (result == null) {
      return;
    }

    final updated = <AgendaItem>[
      result,
      ..._items.where((current) => current.id != result.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    setState(() => _items = updated);
    await _storage.saveItems(updated);

    await _notifications.cancel(result.id);
    if (result.type != AgendaItemType.note && result.dateTime != null) {
      await _notifications.schedule(result);
    }
  }

  int _count(AgendaItemType type) =>
      _items.where((item) => item.type == type).length;

  List<AgendaItem> get _homeItems {
    switch (_homeFilter) {
      case HomeFilter.all:
        return _items;
      case HomeFilter.tasks:
        return _items.where((item) => item.type == AgendaItemType.task).toList();
      case HomeFilter.reminders:
        return _items
            .where((item) => item.type == AgendaItemType.reminder)
            .toList();
    }
  }

  List<AgendaItem> _itemsOfType(AgendaItemType type) =>
      _items.where((item) => item.type == type).toList()
        ..sort((a, b) {
          final ad = a.dateTime;
          final bd = b.dateTime;
          if (ad == null && bd == null) {
            return b.updatedAt.compareTo(a.updatedAt);
          }
          if (ad == null) {
            return 1;
          }
          if (bd == null) {
            return -1;
          }
          return ad.compareTo(bd);
        });

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHome(),
      _buildCategoryPage(
        title: 'Calendario',
        subtitle: 'Tus eventos programados',
        type: AgendaItemType.event,
        emptyText: 'Todavía no tienes eventos en el calendario.',
      ),
      _buildCategoryPage(
        title: 'Mis notas',
        subtitle: 'Ideas y anotaciones guardadas',
        type: AgendaItemType.note,
        emptyText: 'Todavía no tienes notas guardadas.',
      ),
      _buildProfile(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    final filtered = _homeItems;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName.isEmpty ? '¡Hola! 👋' : '¡Hola, $_userName! 👋',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Tu asistente personal',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _tabIndex = 3),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0759D8), Color(0xFF0B78F0)],
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '“Anota…”, “Recuérdame…”, “Agenda…” o “Tengo que…”',
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
                          color: const Color(0xFF075FE4).withValues(alpha: 0.28),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
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
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Organizador',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  TextButton(
                    onPressed: _showTypedFallback,
                    child: const Text('Añadir manual'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _homeFilter == HomeFilter.all,
                    onSelected: (_) =>
                        setState(() => _homeFilter = HomeFilter.all),
                  ),
                  ChoiceChip(
                    label: const Text('Tareas'),
                    selected: _homeFilter == HomeFilter.tasks,
                    onSelected: (_) =>
                        setState(() => _homeFilter = HomeFilter.tasks),
                  ),
                  ChoiceChip(
                    label: const Text('Recordatorios'),
                    selected: _homeFilter == HomeFilter.reminders,
                    onSelected: (_) =>
                        setState(() => _homeFilter = HomeFilter.reminders),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  _homeFilter == HomeFilter.all
                      ? 'Todavía no hay actividades.'
                      : 'No hay elementos en esta categoría.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) => ItemCard(
                item: filtered[index],
                onTap: () => _openEditor(filtered[index], isNew: false),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryPage({
    required String title,
    required String subtitle,
    required AgendaItemType type,
    required String emptyText,
  }) {
    final items = _itemsOfType(type);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          sliver: SliverList.list(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => ItemCard(
                item: items[index],
                onTap: () => _openEditor(items[index], isNew: false),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfile() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Text(
          'Perfil',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        Card(
          elevation: 0,
          color: const Color(0xFFF6F8FC),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFDCEAFF),
              child: Icon(Icons.person, color: Color(0xFF075FE4)),
            ),
            title: Text(
              _userName.isEmpty ? 'Sin nombre' : _userName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Nombre que aparece en el saludo'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _askName,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Resumen',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _profileCount('Tareas', _count(AgendaItemType.task)),
        _profileCount('Recordatorios', _count(AgendaItemType.reminder)),
        _profileCount('Eventos', _count(AgendaItemType.event)),
        _profileCount('Notas', _count(AgendaItemType.note)),
        const SizedBox(height: 20),
        const Card(
          elevation: 0,
          color: Color(0xFFF6F8FC),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Los avisos de tareas, recordatorios y calendario se programan '
              'en Android. Puedes elegir sonido normal, aviso fuerte, solo '
              'vibración o silencio al crear o editar cada elemento.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileCount(String label, int count) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(
          '$count',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF075FE4),
          ),
        ),
      );

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
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      );

  static String _typeName(AgendaItemType type) => switch (type) {
        AgendaItemType.note => 'Nota',
        AgendaItemType.task => 'Tarea',
        AgendaItemType.reminder => 'Recordatorio',
        AgendaItemType.event => 'Calendario',
      };

  static String _alertName(AlertMode mode) => switch (mode) {
        AlertMode.normal => 'Sonido + vibración',
        AlertMode.strong => 'Aviso fuerte',
        AlertMode.vibration => 'Solo vibración',
        AlertMode.silent => 'Sin sonido ni vibración',
      };

  static String _formatDate(DateTime dateTime) {
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} · $hour:$minute';
  }
}
