import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/agenda_item.dart';
import '../models/app_settings.dart';
import '../services/alarm_bridge.dart';
import '../services/intent_parser.dart';
import '../services/storage_service.dart';
import '../widgets/item_card.dart';

enum HomeFilter { all, tasks, reminders }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final IntentParser _parser = IntentParser();
  final StorageService _storage = StorageService();
  final AlarmBridge _alarms = AlarmBridge();
  final TextEditingController _typedController = TextEditingController();

  List<AgendaItem> _items = <AgendaItem>[];
  AppSettings _settings = const AppSettings();
  bool _listening = false;
  bool _startingListening = false;
  bool _speechReady = false;
  String? _speechLocaleId;
  String _heard = '';
  String _userName = '';
  int _tabIndex = 0;
  HomeFilter _homeFilter = HomeFilter.all;

  static const Map<int, String> _durationOptions = <int, String>{
    20: '20 segundos',
    30: '30 segundos',
    60: '1 minuto',
    0: 'Hasta responder',
  };

  static const Map<int, String> _repeatOptions = <int, String>{
    0: 'No repetir',
    5: 'Cada 5 minutos',
    10: 'Cada 10 minutos',
    15: 'Cada 15 minutos',
  };

  static const Map<int, String> _advanceOptions = <int, String>{
    0: 'A la hora programada',
    10: '10 minutos antes',
    30: '30 minutos antes',
    60: '1 hora antes',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    unawaited(_initializeSpeech());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    unawaited(_alarms.stopRingtonePreview());
    _typedController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumeAlarmAction());
    }
  }

  Future<void> _load() async {
    final items = await _storage.loadItems();
    final name = await _storage.loadUserName();
    final settings = await _storage.loadSettings();

    if (!mounted) return;

    setState(() {
      _items = items;
      _userName = name?.trim() ?? '';
      _settings = settings;
    });

    await _consumeAlarmAction();

    if (_userName.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askName());
      });
    }
  }

  Future<void> _consumeAlarmAction() async {
    final action = await _alarms.consumePendingAction();
    if (action == null || !mounted) return;

    final index = _items.indexWhere((item) => item.id == action.itemId);
    if (index < 0) return;

    final item = _items[index];

    if (action.action == 'complete' && item.type == AgendaItemType.task) {
      await _replaceItem(
        _copyItem(
          item,
          completed: true,
          progress: 100,
          archived: true,
          archivedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        reschedule: false,
      );
      return;
    }

    if (action.action == 'ok') {
      final shouldArchive = item.recurrence == RecurrenceType.none ||
          (item.recurrenceEnd != null &&
              item.recurrenceEnd!.isBefore(DateTime.now()));

      if (shouldArchive &&
          (item.type == AgendaItemType.reminder ||
              item.type == AgendaItemType.event)) {
        await _replaceItem(
          _copyItem(
            item,
            archived: true,
            archivedAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          reschedule: false,
        );
      }
      return;
    }

    if (action.action == 'reprogram') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openEditor(item, isNew: false));
      });
    }
  }

  AgendaItem _copyItem(
    AgendaItem item, {
    bool? completed,
    int? progress,
    bool? archived,
    DateTime? archivedAt,
    DateTime? updatedAt,
  }) {
    return AgendaItem(
      id: item.id,
      type: item.type,
      title: item.title,
      rawText: item.rawText,
      dateTime: item.dateTime,
      completed: completed ?? item.completed,
      progress: progress ?? item.progress,
      alertMode: item.alertMode,
      ringtoneUri: item.ringtoneUri,
      ringtoneTitle: item.ringtoneTitle,
      alarmDurationSeconds: item.alarmDurationSeconds,
      repeatMinutes: item.repeatMinutes,
      advanceMinutes: item.advanceMinutes,
      recurrence: item.recurrence,
      weekdays: item.weekdays,
      recurrenceEnd: item.recurrenceEnd,
      archived: archived ?? item.archived,
      archivedAt: archivedAt ?? item.archivedAt,
      createdAt: item.createdAt,
      updatedAt: updatedAt ?? item.updatedAt,
    );
  }

  Future<void> _replaceItem(
    AgendaItem item, {
    required bool reschedule,
  }) async {
    final updated = <AgendaItem>[
      item,
      ..._items.where((current) => current.id != item.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    setState(() => _items = updated);
    await _storage.saveItems(updated);

    if (reschedule) {
      await _alarms.scheduleItem(item);
    } else {
      await _alarms.cancelItem(item.id);
    }
  }

  Future<void> _askName() async {
    var draft = _userName;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: _userName.isNotEmpty,
      builder: (dialogContext) => AlertDialog(
        title: Text(_userName.isEmpty ? '¿Cómo te llamas?' : 'Editar nombre'),
        content: TextFormField(
          initialValue: _userName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Tu nombre',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => draft = value,
        ),
        actions: [
          if (_userName.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    await _storage.saveUserName(result);
    if (mounted) setState(() => _userName = result);
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize();
      String? localeId;
      if (available) {
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('es')) {
            localeId = locale.localeId;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _speechReady = available;
          _speechLocaleId = localeId;
        });
      }
    } on Exception {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _startListening() async {
    if (_startingListening || _listening) return;
    if (!_speechReady) {
      _showTypedFallback();
      return;
    }

    _startingListening = true;
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
          if (!mounted) return;
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
      if (mounted) {
        setState(() => _listening = false);
        _showTypedFallback();
      }
    } finally {
      _startingListening = false;
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;

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
              if (text.isNotEmpty) unawaited(_createFromText(text));
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
    final proposed = now.add(const Duration(hours: 1));

    final item = AgendaItem(
      id: now.microsecondsSinceEpoch.toString(),
      type: parsed.type,
      title: parsed.title,
      rawText: parsed.rawText,
      dateTime: parsed.type == AgendaItemType.note
          ? null
          : parsed.dateTime ?? proposed,
      alertMode: _settings.defaultAlertMode,
      ringtoneUri: _settings.defaultRingtoneUri,
      ringtoneTitle: _settings.defaultRingtoneTitle,
      alarmDurationSeconds: _settings.defaultAlarmDurationSeconds,
      repeatMinutes: _settings.defaultRepeatMinutes,
      advanceMinutes: _settings.defaultAdvanceMinutes,
      createdAt: now,
      updatedAt: now,
    );

    await _openEditor(item, isNew: true);
  }

  Future<void> _openEditor(
    AgendaItem item, {
    required bool isNew,
  }) async {
    var title = item.title;
    var type = item.type;
    var dateTime = item.dateTime ?? DateTime.now().add(const Duration(hours: 1));
    var alertMode = item.alertMode;
    var ringtoneUri = item.ringtoneUri;
    var ringtoneTitle = item.ringtoneTitle;
    var alarmDurationSeconds = item.alarmDurationSeconds;
    var repeatMinutes = item.repeatMinutes;
    var advanceMinutes = item.advanceMinutes;
    var recurrence = item.recurrence;
    var recurrenceEnd = item.recurrenceEnd;
    var weekdays = List<int>.from(item.weekdays);
    var progress = item.type == AgendaItemType.task ? item.progress : 0;
    var deleteRequested = false;

    final result = await showModalBottomSheet<AgendaItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final requiresSchedule = type != AgendaItemType.note;
          final usesTone = alertMode == AlertMode.soundAndVibration ||
              alertMode == AlertMode.strong ||
              alertMode == AlertMode.soundOnly ||
              alertMode == AlertMode.toneAndVoice;

          Future<void> pickDateTime() async {
            final now = DateTime.now();
            final date = await showDatePicker(
              context: sheetContext,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 10, 12, 31),
              initialDate: dateTime,
            );
            if (date == null || !sheetContext.mounted) return;

            final time = await showTimePicker(
              context: sheetContext,
              initialTime: TimeOfDay.fromDateTime(dateTime),
            );
            if (time == null) return;

            setSheetState(() {
              dateTime = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
            });
          }

          Future<void> pickTone() async {
            final selected = await _alarms.pickRingtone(ringtoneUri);
            if (selected != null && sheetContext.mounted) {
              setSheetState(() {
                ringtoneUri = selected.uri;
                ringtoneTitle = selected.title;
              });
            }
          }

          Future<void> previewTone() async {
            if (ringtoneUri == null) await pickTone();
            if (ringtoneUri != null) {
              await _alarms.previewRingtone(ringtoneUri!);
            }
          }

          Future<void> pickRecurrenceEnd() async {
            final chosen = await showDatePicker(
              context: sheetContext,
              firstDate: DateTime(dateTime.year, dateTime.month, dateTime.day),
              lastDate: DateTime(dateTime.year + 10, 12, 31),
              initialDate:
                  recurrenceEnd ?? dateTime.add(const Duration(days: 30)),
            );
            if (chosen != null) {
              setSheetState(() {
                recurrenceEnd = DateTime(
                  chosen.year,
                  chosen.month,
                  chosen.day,
                  23,
                  59,
                );
              });
            }
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
                TextFormField(
                  initialValue: item.title,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => title = value,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<AgendaItemType>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: AgendaItemType.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_typeName(value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setSheetState(() {
                      type = value ?? type;
                      if (type == AgendaItemType.note) {
                        progress = 0;
                        recurrence = RecurrenceType.none;
                        recurrenceEnd = null;
                        weekdays = <int>[];
                      }
                    });
                  },
                ),
                if (requiresSchedule) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(_formatDate(dateTime)),
                    subtitle: const Text(
                      'Fecha y hora propuestas. Toca para cambiar.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: pickDateTime,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AlertMode>(
                    initialValue: alertMode,
                    decoration: const InputDecoration(
                      labelText: 'Cómo quieres que te avise',
                      border: OutlineInputBorder(),
                    ),
                    items: AlertMode.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_alertName(value)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setSheetState(() {
                        alertMode = value ?? alertMode;
                      });
                    },
                  ),
                  if (usesTone) ...[
                    const SizedBox(height: 10),
                    Card(
                      elevation: 0,
                      color: const Color(0xFFF6F8FC),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.music_note),
                              title: Text(
                                ringtoneTitle ??
                                    'Tono predeterminado de Android',
                              ),
                              subtitle: const Text(
                                'Puedes escoger cualquier tono instalado.',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: pickTone,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: previewTone,
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Probar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _alarms.stopRingtonePreview,
                                    icon: const Icon(Icons.stop),
                                    label: const Text('Detener'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: alarmDurationSeconds,
                    decoration: const InputDecoration(
                      labelText: 'Duración del sonido / voz',
                      border: OutlineInputBorder(),
                    ),
                    items: _durationOptions.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setSheetState(() {
                        alarmDurationSeconds =
                            value ?? alarmDurationSeconds;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: repeatMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Repetir si no respondo',
                      border: OutlineInputBorder(),
                    ),
                    items: _repeatOptions.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setSheetState(() {
                        repeatMinutes = value ?? repeatMinutes;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: advanceMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Avisarme antes',
                      border: OutlineInputBorder(),
                    ),
                    items: _advanceOptions.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setSheetState(() {
                        advanceMinutes = value ?? advanceMinutes;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: recurrence,
                    decoration: const InputDecoration(
                      labelText: 'Repetición',
                      border: OutlineInputBorder(),
                    ),
                    items: RecurrenceType.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_recurrenceName(value)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setSheetState(() {
                        recurrence = value ?? recurrence;
                        if (recurrence == RecurrenceType.none) {
                          recurrenceEnd = null;
                          weekdays = <int>[];
                        }
                      });
                    },
                  ),
                  if (recurrence == RecurrenceType.weekly) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: List.generate(7, (index) {
                        final weekday = index + 1;
                        return FilterChip(
                          label: Text(_weekdayShort(weekday)),
                          selected: weekdays.contains(weekday),
                          onSelected: (selected) {
                            setSheetState(() {
                              if (selected) {
                                if (!weekdays.contains(weekday)) {
                                  weekdays.add(weekday);
                                }
                              } else {
                                weekdays.remove(weekday);
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                  if (recurrence != RecurrenceType.none)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_repeat),
                      title: Text(
                        recurrenceEnd == null
                            ? 'Fecha final obligatoria'
                            : 'Hasta ${_formatDateOnly(recurrenceEnd!)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: pickRecurrenceEnd,
                    ),
                ],
                if (type == AgendaItemType.task) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Avance: $progress%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                      final cleanTitle = title.trim();
                      if (cleanTitle.isEmpty) {
                        _snack(sheetContext, 'Escribe un título.');
                        return;
                      }

                      if (recurrence != RecurrenceType.none &&
                          recurrenceEnd == null) {
                        _snack(
                          sheetContext,
                          'Selecciona hasta qué fecha se repetirá.',
                        );
                        return;
                      }

                      if (recurrence == RecurrenceType.weekly &&
                          weekdays.isEmpty) {
                        _snack(
                          sheetContext,
                          'Selecciona al menos un día.',
                        );
                        return;
                      }

                      final effectiveProgress =
                          type == AgendaItemType.task ? progress : 0;
                      final completed = type == AgendaItemType.task &&
                          effectiveProgress == 100;

                      Navigator.pop(
                        sheetContext,
                        AgendaItem(
                          id: item.id,
                          type: type,
                          title: cleanTitle,
                          rawText: item.rawText,
                          dateTime: requiresSchedule ? dateTime : null,
                          completed: completed,
                          progress: effectiveProgress,
                          alertMode: alertMode,
                          ringtoneUri: ringtoneUri,
                          ringtoneTitle: ringtoneTitle,
                          alarmDurationSeconds: alarmDurationSeconds,
                          repeatMinutes: repeatMinutes,
                          advanceMinutes: advanceMinutes,
                          recurrence: recurrence,
                          weekdays: weekdays,
                          recurrenceEnd: recurrenceEnd,
                          archived: completed,
                          archivedAt: completed ? DateTime.now() : null,
                          createdAt: item.createdAt,
                          updatedAt: DateTime.now(),
                        ),
                      );
                    },
                    child: Text(isNew ? 'Guardar' : 'Guardar cambios'),
                  ),
                ),
                if (!isNew)
                  TextButton.icon(
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
              ],
            ),
          );
        },
      ),
    );

    await _alarms.stopRingtonePreview();

    if (!mounted) return;

    if (deleteRequested) {
      await _alarms.cancelItem(item.id);
      final updated =
          _items.where((current) => current.id != item.id).toList();
      setState(() => _items = updated);
      await _storage.saveItems(updated);
      return;
    }

    if (result == null) return;

    await _replaceItem(
      result,
      reschedule:
          !result.archived && result.type != AgendaItemType.note,
    );
  }

  Future<void> _exportNotes() async {
    final notes =
        _items.where((item) => item.type == AgendaItemType.note).toList();

    if (notes.isEmpty) {
      _snack(context, 'No tienes notas para exportar.');
      return;
    }

    final buffer = StringBuffer('MIS NOTAS - MI AGENDA IA\n\n');
    for (final note in notes) {
      buffer
        ..writeln(note.title)
        ..writeln('Creada: ${_formatDate(note.createdAt)}')
        ..writeln(note.rawText)
        ..writeln('----------------------------------------');
    }

    final file = XFile.fromData(
      utf8.encode(buffer.toString()),
      mimeType: 'text/plain',
    );

    await SharePlus.instance.share(
      ShareParams(
        title: 'Exportar notas',
        text: 'Notas exportadas desde Mi Agenda IA',
        files: <XFile>[file],
        fileNameOverrides: const <String>[
          'mis_notas_mi_agenda.txt',
        ],
      ),
    );
  }

  Future<void> _showVoiceHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Qué puedo decir?'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NOTA', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('“Anota revisar la postulación.”'),
              SizedBox(height: 12),
              Text('TAREA', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '“Tengo que entregar el informe el viernes a las 4.”',
              ),
              SizedBox(height: 12),
              Text(
                'RECORDATORIO',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '“Recuérdame tomar la pastilla mañana a las 8.”',
              ),
              SizedBox(height: 12),
              Text(
                'CALENDARIO',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '“Agenda reunión con el director el jueves a las 3.”',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDefaultAlertSettings() async {
    var mode = _settings.defaultAlertMode;
    var ringtoneUri = _settings.defaultRingtoneUri;
    var ringtoneTitle = _settings.defaultRingtoneTitle;
    var duration = _settings.defaultAlarmDurationSeconds;
    var repeat = _settings.defaultRepeatMinutes;
    var advance = _settings.defaultAdvanceMinutes;

    final result = await showModalBottomSheet<AppSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final usesTone = mode == AlertMode.soundAndVibration ||
              mode == AlertMode.strong ||
              mode == AlertMode.soundOnly ||
              mode == AlertMode.toneAndVoice;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Avisos predeterminados',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AlertMode>(
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Modo de aviso',
                    border: OutlineInputBorder(),
                  ),
                  items: AlertMode.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_alertName(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() => mode = value ?? mode);
                  },
                ),
                if (usesTone) ...[
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(
                      ringtoneTitle ?? 'Tono predeterminado de Android',
                    ),
                    subtitle: const Text('Toca para elegir otro tono'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selected =
                          await _alarms.pickRingtone(ringtoneUri);
                      if (selected != null && sheetContext.mounted) {
                        setSheetState(() {
                          ringtoneUri = selected.uri;
                          ringtoneTitle = selected.title;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: duration,
                  decoration: const InputDecoration(
                    labelText: 'Duración del aviso',
                    border: OutlineInputBorder(),
                  ),
                  items: _durationOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() => duration = value ?? duration);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: repeat,
                  decoration: const InputDecoration(
                    labelText: 'Repetir si no respondo',
                    border: OutlineInputBorder(),
                  ),
                  items: _repeatOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() => repeat = value ?? repeat);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: advance,
                  decoration: const InputDecoration(
                    labelText: 'Avisarme antes',
                    border: OutlineInputBorder(),
                  ),
                  items: _advanceOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() => advance = value ?? advance);
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(
                        sheetContext,
                        AppSettings(
                          defaultAlertMode: mode,
                          defaultRingtoneUri: ringtoneUri,
                          defaultRingtoneTitle: ringtoneTitle,
                          defaultAlarmDurationSeconds: duration,
                          defaultRepeatMinutes: repeat,
                          defaultAdvanceMinutes: advance,
                        ),
                      );
                    },
                    child: const Text('Guardar preferencias'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result != null && mounted) {
      await _storage.saveSettings(result);
      setState(() => _settings = result);
    }
  }

  List<AgendaItem> get _activeItems =>
      _items.where((item) => !item.archived).toList();

  List<AgendaItem> get _historyItems {
    final items = _items.where((item) => item.archived).toList();
    items.sort((a, b) {
      final aDate = a.archivedAt ?? a.updatedAt;
      final bDate = b.archivedAt ?? b.updatedAt;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  List<AgendaItem> get _homeItems {
    switch (_homeFilter) {
      case HomeFilter.all:
        return _activeItems;
      case HomeFilter.tasks:
        return _activeItems
            .where((item) => item.type == AgendaItemType.task)
            .toList();
      case HomeFilter.reminders:
        return _activeItems
            .where((item) => item.type == AgendaItemType.reminder)
            .toList();
    }
  }

  int _count(AgendaItemType type) =>
      _activeItems.where((item) => item.type == type).length;

  List<AgendaItem> _itemsOfType(AgendaItemType type) {
    final items =
        _activeItems.where((item) => item.type == type).toList();
    items.sort((a, b) {
      final aDate = a.dateTime;
      final bDate = b.dateTime;
      if (aDate == null && bDate == null) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHome(),
      _buildCategoryPage(
        title: 'Calendario',
        subtitle: 'Tus eventos programados',
        type: AgendaItemType.event,
        emptyText: 'Todavía no tienes eventos.',
      ),
      _buildNotesPage(),
      _buildProfilePage(),
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
    final items = _homeItems;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverList.list(
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
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Dímelo y yo lo organizo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showVoiceHelp,
                    icon: const Icon(Icons.help_outline),
                    label: const Text('¿Qué puedo decir?'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _listening ? _stopListening : _startListening,
                  onLongPress: _showTypedFallback,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF075FE4),
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Colors.white,
                      size: 58,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _listening
                      ? (_heard.isEmpty ? 'Te escucho…' : _heard)
                      : 'Toca para hablar · Mantén para escribir',
                  textAlign: TextAlign.center,
                ),
              ),
              if (_listening) ...[
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _stopListening,
                    icon: const Icon(Icons.check),
                    label: const Text('Terminar dictado'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Organizador',
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
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('No hay elementos en esta categoría.'),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => ItemCard(
                item: items[index],
                onTap: () => _openEditor(
                  items[index],
                  isNew: false,
                ),
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
          padding: const EdgeInsets.all(20),
          sliver: SliverList.list(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(subtitle),
            ],
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Center(child: Text(emptyText)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => ItemCard(
                item: items[index],
                onTap: () => _openEditor(
                  items[index],
                  isNew: false,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNotesPage() {
    final notes = _itemsOfType(AgendaItemType.note);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mis notas',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _exportNotes,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Exportar TXT'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (notes.isEmpty)
          const SliverToBoxAdapter(
            child: Center(child: Text('Todavía no tienes notas.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) => ItemCard(
                item: notes[index],
                onTap: () => _openEditor(
                  notes[index],
                  isNew: false,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfilePage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Perfil',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(_userName.isEmpty ? 'Sin nombre' : _userName),
          subtitle: const Text('Editar nombre'),
          onTap: _askName,
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active),
          title: const Text('Avisos predeterminados'),
          subtitle: Text(
            '${_alertName(_settings.defaultAlertMode)} · '
            '${_durationOptions[_settings.defaultAlarmDurationSeconds]}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editDefaultAlertSettings,
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Historial'),
          subtitle: Text('${_historyItems.length} elementos'),
          onTap: _showHistory,
        ),
        ListTile(
          leading: const Icon(Icons.alarm),
          title: const Text('Permisos de alarmas'),
          subtitle: const Text(
            'Activa alarmas exactas y pantalla completa.',
          ),
          onTap: _alarms.requestPermissions,
        ),
      ],
    );
  }

  Future<void> _showHistory() async {
    final history = _historyItems;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Historial',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Text('Todavía no hay historial.')
            else
              ...history.map(
                (item) => ItemCard(
                  item: item,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_openEditor(item, isNew: false));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
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
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  static String _typeName(AgendaItemType type) => switch (type) {
        AgendaItemType.note => 'Nota',
        AgendaItemType.task => 'Tarea',
        AgendaItemType.reminder => 'Recordatorio',
        AgendaItemType.event => 'Calendario',
      };

  static String _alertName(AlertMode mode) => switch (mode) {
        AlertMode.soundAndVibration => 'Tono + vibración',
        AlertMode.strong => 'Alarma fuerte + vibración',
        AlertMode.soundOnly => 'Solo tono',
        AlertMode.voice => 'Leer actividad con voz',
        AlertMode.toneAndVoice => 'Tono + voz',
        AlertMode.vibrationOnly => 'Solo vibración',
        AlertMode.silent => 'Silencioso',
      };

  static String _recurrenceName(RecurrenceType recurrence) =>
      switch (recurrence) {
        RecurrenceType.none => 'No repetir',
        RecurrenceType.daily => 'Todos los días',
        RecurrenceType.weekly => 'Días de la semana',
        RecurrenceType.monthly => 'Cada mes',
      };

  static String _weekdayShort(int weekday) => switch (weekday) {
        DateTime.monday => 'Lun',
        DateTime.tuesday => 'Mar',
        DateTime.wednesday => 'Mié',
        DateTime.thursday => 'Jue',
        DateTime.friday => 'Vie',
        DateTime.saturday => 'Sáb',
        DateTime.sunday => 'Dom',
        _ => '?',
      };

  static String _formatDate(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} · '
        '$hour:$minute';
  }

  static String _formatDateOnly(DateTime dateTime) =>
      '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
