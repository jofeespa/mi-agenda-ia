import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/agenda_item.dart';
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

    if (!mounted) {
      return;
    }

    setState(() {
      _items = items;
      _userName = name?.trim() ?? '';
    });

    await _consumeAlarmAction();

    if (_userName.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_askName());
        }
      });
    }
  }

  Future<void> _consumeAlarmAction() async {
    final action = await _alarms.consumePendingAction();
    if (action == null || !mounted) {
      return;
    }

    final index = _items.indexWhere((item) => item.id == action.itemId);
    if (index < 0) {
      return;
    }

    final item = _items[index];

    if (action.action == 'ok') {
      final shouldArchive =
          item.recurrence == RecurrenceType.none ||
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
        if (mounted) {
          unawaited(_openEditor(item, isNew: false));
        }
      });
    }
  }

  AgendaItem _copyItem(
    AgendaItem item, {
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
      completed: item.completed,
      progress: item.progress,
      alertMode: item.alertMode,
      ringtoneUri: item.ringtoneUri,
      ringtoneTitle: item.ringtoneTitle,
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
    var draftName = _userName;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: _userName.isNotEmpty,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _userName.isEmpty ? '¿Cómo te llamas?' : 'Editar nombre',
          ),
          content: TextFormField(
            initialValue: _userName,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tu nombre',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => draftName = value,
            onFieldSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
          ),
          actions: [
            if (_userName.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
            FilledButton(
              onPressed: () {
                final trimmed = draftName.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

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
        const preferredLocales = <String>[
          'es_EC',
          'es-EC',
          'es_ES',
          'es-ES',
        ];

        for (final preferred in preferredLocales) {
          for (final locale in locales) {
            if (locale.localeId.toLowerCase() ==
                preferred.toLowerCase()) {
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

      if (mounted) {
        setState(() {
          _speechReady = available;
          _speechLocaleId = localeId;
        });
      }
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
      if (mounted) {
        setState(() => _listening = false);
        _showTypedFallback();
      }
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
      builder: (dialogContext) {
        return AlertDialog(
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
        );
      },
    );
  }

  Future<void> _createFromText(String text) async {
    final parsed = _parser.parse(text);
    final now = DateTime.now();

    final item = AgendaItem(
      id: now.microsecondsSinceEpoch.toString(),
      type: parsed.type,
      title: parsed.title,
      rawText: parsed.rawText,
      dateTime: parsed.dateTime,
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
    var dateTime = item.dateTime;
    var alertMode = item.alertMode;
    var ringtoneUri = item.ringtoneUri;
    var ringtoneTitle = item.ringtoneTitle;
    var recurrence = item.recurrence;
    var recurrenceEnd = item.recurrenceEnd;
    var weekdays = List<int>.from(item.weekdays);
    var progress =
        item.type == AgendaItemType.task ? item.progress : 0;
    var deleteRequested = false;

    final result = await showModalBottomSheet<AgendaItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final requiresSchedule = type != AgendaItemType.note;
            final usesSound =
                alertMode == AlertMode.soundAndVibration ||
                alertMode == AlertMode.strong ||
                alertMode == AlertMode.soundOnly;

            Future<void> pickDateTime() async {
              final now = DateTime.now();
              final initial =
                  dateTime != null &&
                          dateTime!.isAfter(
                            now.subtract(const Duration(days: 1)),
                          )
                      ? dateTime!
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
                dateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            Future<void> pickRecurrenceEnd() async {
              final start = dateTime ?? DateTime.now();

              final selected = await showDatePicker(
                context: sheetContext,
                firstDate: DateTime(
                  start.year,
                  start.month,
                  start.day,
                ),
                lastDate: DateTime(start.year + 10, 12, 31),
                initialDate:
                    recurrenceEnd ??
                    start.add(const Duration(days: 30)),
              );

              if (selected != null) {
                setSheetState(() {
                  recurrenceEnd = DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    23,
                    59,
                  );
                });
              }
            }

            Future<void> pickTone() async {
              final selected =
                  await _alarms.pickRingtone(ringtoneUri);

              if (selected != null && sheetContext.mounted) {
                setSheetState(() {
                  ringtoneUri = selected.uri;
                  ringtoneTitle = selected.title;
                });
              }
            }

            Future<void> previewTone() async {
              if (ringtoneUri == null) {
                final selected =
                    await _alarms.pickRingtone(ringtoneUri);

                if (selected == null || !sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  ringtoneUri = selected.uri;
                  ringtoneTitle = selected.title;
                });
              }

              final uri = ringtoneUri;
              if (uri != null) {
                await _alarms.previewRingtone(uri);
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
                    isNew
                        ? 'Confirmar actividad'
                        : 'Editar actividad',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    initialValue: item.title,
                    maxLines: 2,
                    textCapitalization:
                        TextCapitalization.sentences,
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
                          (value) =>
                              DropdownMenuItem<AgendaItemType>(
                            value: value,
                            child: Text(_typeName(value)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setSheetState(() {
                        type = value ?? type;
                        if (type == AgendaItemType.note) {
                          dateTime = null;
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
                      title: Text(
                        dateTime == null
                            ? 'Fecha y hora obligatorias'
                            : _formatDate(dateTime!),
                      ),
                      subtitle: const Text(
                        'Toca para seleccionar o cambiar',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: pickDateTime,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<AlertMode>(
                      initialValue: alertMode,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de alarma',
                        border: OutlineInputBorder(),
                      ),
                      items: AlertMode.values
                          .map(
                            (value) =>
                                DropdownMenuItem<AlertMode>(
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
                    if (usesSound) ...[
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
                                leading:
                                    const Icon(Icons.music_note),
                                title: Text(
                                  ringtoneTitle ??
                                      'Elegir tono del teléfono',
                                ),
                                subtitle: const Text(
                                  'Escoge un tono instalado en tu teléfono',
                                ),
                                trailing:
                                    const Icon(Icons.chevron_right),
                                onTap: pickTone,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: previewTone,
                                      icon:
                                          const Icon(Icons.play_arrow),
                                      label:
                                          const Text('Probar tono'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _alarms.stopRingtonePreview,
                                      icon: const Icon(Icons.stop),
                                      label: const Text(
                                        'Detener prueba',
                                      ),
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
                    DropdownButtonFormField<RecurrenceType>(
                      initialValue: recurrence,
                      decoration: const InputDecoration(
                        labelText: 'Repetición',
                        border: OutlineInputBorder(),
                      ),
                      items: RecurrenceType.values
                          .map(
                            (value) =>
                                DropdownMenuItem<RecurrenceType>(
                              value: value,
                              child: Text(
                                _recurrenceName(value),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setSheetState(() {
                          recurrence = value ?? recurrence;
                          if (recurrence ==
                              RecurrenceType.none) {
                            recurrenceEnd = null;
                            weekdays = <int>[];
                          }
                        });
                      },
                    ),
                    if (recurrence ==
                        RecurrenceType.weekly) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Días de la semana',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: List.generate(7, (index) {
                          final weekday = index + 1;
                          return FilterChip(
                            label: Text(
                              _weekdayShort(weekday),
                            ),
                            selected:
                                weekdays.contains(weekday),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  if (!weekdays.contains(
                                    weekday,
                                  )) {
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
                    if (recurrence !=
                        RecurrenceType.none) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.event_repeat),
                        title: Text(
                          recurrenceEnd == null
                              ? 'Fecha final obligatoria'
                              : 'Hasta ${_formatDateOnly(recurrenceEnd!)}',
                        ),
                        trailing:
                            const Icon(Icons.chevron_right),
                        onTap: pickRecurrenceEnd,
                      ),
                    ],
                  ],
                  if (type == AgendaItemType.task) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Avance: $progress%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Slider(
                      value: progress.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$progress%',
                      onChanged: (value) {
                        setSheetState(() {
                          progress = value.round();
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        final trimmedTitle = title.trim();

                        if (trimmedTitle.isEmpty) {
                          _snack(
                            sheetContext,
                            'Escribe un título.',
                          );
                          return;
                        }

                        if (requiresSchedule &&
                            dateTime == null) {
                          _snack(
                            sheetContext,
                            'Debes seleccionar fecha y hora.',
                          );
                          return;
                        }

                        if (recurrence !=
                                RecurrenceType.none &&
                            recurrenceEnd == null) {
                          _snack(
                            sheetContext,
                            'Selecciona hasta qué fecha se repetirá.',
                          );
                          return;
                        }

                        if (recurrence ==
                                RecurrenceType.weekly &&
                            weekdays.isEmpty) {
                          _snack(
                            sheetContext,
                            'Selecciona al menos un día.',
                          );
                          return;
                        }

                        final effectiveProgress =
                            type == AgendaItemType.task
                                ? progress
                                : 0;
                        final completed =
                            type == AgendaItemType.task &&
                            effectiveProgress == 100;

                        Navigator.pop(
                          sheetContext,
                          AgendaItem(
                            id: item.id,
                            type: type,
                            title: trimmedTitle,
                            rawText: item.rawText,
                            dateTime:
                                requiresSchedule ? dateTime : null,
                            completed: completed,
                            progress: effectiveProgress,
                            alertMode: alertMode,
                            ringtoneUri: ringtoneUri,
                            ringtoneTitle: ringtoneTitle,
                            recurrence: recurrence,
                            weekdays: weekdays,
                            recurrenceEnd: recurrenceEnd,
                            archived: completed,
                            archivedAt:
                                completed ? DateTime.now() : null,
                            createdAt: item.createdAt,
                            updatedAt: DateTime.now(),
                          ),
                        );
                      },
                      child: Text(
                        isNew
                            ? 'Guardar'
                            : 'Guardar cambios',
                      ),
                    ),
                  ),
                  if (!isNew) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          final confirmed =
                              await showDialog<bool>(
                            context: sheetContext,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text(
                                  'Eliminar actividad',
                                ),
                                content: const Text(
                                  'Esta acción no se puede deshacer.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                      dialogContext,
                                      false,
                                    ),
                                    child: const Text(
                                      'Cancelar',
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                      dialogContext,
                                      true,
                                    ),
                                    child:
                                        const Text('Eliminar'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (confirmed == true &&
                              sheetContext.mounted) {
                            deleteRequested = true;
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon:
                            const Icon(Icons.delete_outline),
                        label: const Text(
                          'Eliminar actividad',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    await _alarms.stopRingtonePreview();

    if (!mounted) {
      return;
    }

    if (deleteRequested) {
      await _alarms.cancelItem(item.id);
      final updated =
          _items.where((current) => current.id != item.id).toList();
      setState(() => _items = updated);
      await _storage.saveItems(updated);
      return;
    }

    if (result == null) {
      return;
    }

    await _replaceItem(
      result,
      reschedule:
          !result.archived &&
          result.type != AgendaItemType.note,
    );
  }

  Future<void> _exportNotes() async {
    final notes = _items
        .where((item) => item.type == AgendaItemType.note)
        .toList();

    if (notes.isEmpty) {
      if (mounted) {
        _snack(context, 'No tienes notas para exportar.');
      }
      return;
    }

    final buffer = StringBuffer(
      'MIS NOTAS - MI AGENDA IA\n\n',
    );

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

  List<AgendaItem> get _activeItems =>
      _items.where((item) => !item.archived).toList();

  List<AgendaItem> get _historyItems {
    final items =
        _items.where((item) => item.archived).toList();
    items.sort((a, b) {
      final aDate = a.archivedAt ?? a.updatedAt;
      final bDate = b.archivedAt ?? b.updatedAt;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  int _count(AgendaItemType type) {
    return _activeItems
        .where((item) => item.type == type)
        .length;
  }

  List<AgendaItem> get _homeItems {
    switch (_homeFilter) {
      case HomeFilter.all:
        return _activeItems;
      case HomeFilter.tasks:
        return _activeItems
            .where(
              (item) =>
                  item.type == AgendaItemType.task,
            )
            .toList();
      case HomeFilter.reminders:
        return _activeItems
            .where(
              (item) =>
                  item.type == AgendaItemType.reminder,
            )
            .toList();
    }
  }

  List<AgendaItem> _itemsOfType(AgendaItemType type) {
    final items = _activeItems
        .where((item) => item.type == type)
        .toList();

    items.sort((a, b) {
      final aDate = a.dateTime;
      final bDate = b.dateTime;

      if (aDate == null && bDate == null) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
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
        emptyText:
            'Todavía no tienes eventos en el calendario.',
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

  Future<void> _showVoiceHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Qué puedo decir?'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOTA',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text('“Anota revisar la postulación.”'),
                SizedBox(height: 14),
                Text(
                  'TAREA',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '“Tengo que entregar el informe el viernes a las 4.”',
                ),
                SizedBox(height: 14),
                Text(
                  'RECORDATORIO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '“Recuérdame tomar la pastilla mañana a las 8.”',
                ),
                SizedBox(height: 14),
                Text(
                  'CALENDARIO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '“Agenda reunión con el director el jueves a las 3.”',
                ),
                SizedBox(height: 14),
                Text(
                  'Después de hablar puedes corregir el tipo, fecha, tono y repetición.',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHome() {
    final items = _homeItems;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName.isEmpty
                              ? '¡Hola! 👋'
                              : '¡Hola, $_userName! 👋',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Tu asistente personal',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _tabIndex = 3);
                    },
                    icon:
                        const Icon(Icons.settings_outlined),
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
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,
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
                    icon:
                        const Icon(Icons.help_outline),
                    label:
                        const Text('¿Qué puedo decir?'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Habla de forma natural. Tú confirmas antes de guardar.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  onTap: _listening
                      ? _stopListening
                      : _startListening,
                  onLongPress: _showTypedFallback,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF075FE4),
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
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _listening
                      ? (_heard.isEmpty
                          ? 'Te escucho…'
                          : _heard)
                      : 'Toca para hablar · Mantén para escribir',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
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
                    selected:
                        _homeFilter == HomeFilter.all,
                    onSelected: (_) {
                      setState(
                        () =>
                            _homeFilter = HomeFilter.all,
                      );
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tareas'),
                    selected:
                        _homeFilter == HomeFilter.tasks,
                    onSelected: (_) {
                      setState(
                        () =>
                            _homeFilter = HomeFilter.tasks,
                      );
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Recordatorios'),
                    selected:
                        _homeFilter ==
                        HomeFilter.reminders,
                    onSelected: (_) {
                      setState(
                        () => _homeFilter =
                            HomeFilter.reminders,
                      );
                    },
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
                child: Text(
                  'No hay elementos en esta categoría.',
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding:
                const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ItemCard(
                  item: items[index],
                  onTap: () => _openEditor(
                    items[index],
                    isNew: false,
                  ),
                );
              },
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
            padding:
                const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ItemCard(
                  item: items[index],
                  onTap: () => _openEditor(
                    items[index],
                    isNew: false,
                  ),
                );
              },
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
                    icon:
                        const Icon(Icons.download_outlined),
                    label: const Text('Exportar TXT'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (notes.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Todavía no tienes notas.',
              ),
            ),
          )
        else
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                return ItemCard(
                  item: notes[index],
                  onTap: () => _openEditor(
                    notes[index],
                    isNew: false,
                  ),
                );
              },
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
          title: Text(
            _userName.isEmpty ? 'Sin nombre' : _userName,
          ),
          subtitle: const Text('Editar nombre'),
          onTap: _askName,
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Historial'),
          subtitle: Text(
            '${_historyItems.length} elementos',
          ),
          onTap: _showHistory,
        ),
        ListTile(
          leading: const Icon(Icons.alarm),
          title: const Text('Permisos de alarmas'),
          subtitle: const Text(
            'Activa notificaciones, alarmas exactas y pantalla completa',
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
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return ListView(
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
                  const Text(
                    'Todavía no hay historial.',
                  )
                else
                  ...history.map(
                    (item) => ItemCard(
                      item: item,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          _openEditor(
                            item,
                            isNew: false,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _summary(
    String label,
    int value,
    IconData icon,
  ) {
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

  static void _snack(
    BuildContext context,
    String text,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  static String _typeName(AgendaItemType type) {
    return switch (type) {
      AgendaItemType.note => 'Nota',
      AgendaItemType.task => 'Tarea',
      AgendaItemType.reminder => 'Recordatorio',
      AgendaItemType.event => 'Calendario',
    };
  }

  static String _alertName(AlertMode mode) {
    return switch (mode) {
      AlertMode.soundAndVibration => 'Sonido + vibración',
      AlertMode.strong => 'Alarma fuerte + vibración',
      AlertMode.soundOnly => 'Solo sonido',
      AlertMode.vibrationOnly => 'Solo vibración',
      AlertMode.silent => 'Silencioso',
    };
  }

  static String _recurrenceName(
    RecurrenceType recurrence,
  ) {
    return switch (recurrence) {
      RecurrenceType.none => 'No repetir',
      RecurrenceType.daily => 'Todos los días',
      RecurrenceType.weekly => 'Días de la semana',
      RecurrenceType.monthly => 'Cada mes',
    };
  }

  static String _weekdayShort(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mié',
      DateTime.thursday => 'Jue',
      DateTime.friday => 'Vie',
      DateTime.saturday => 'Sáb',
      DateTime.sunday => 'Dom',
      _ => '?',
    };
  }

  static String _formatDate(DateTime dateTime) {
    final hour =
        dateTime.hour.toString().padLeft(2, '0');
    final minute =
        dateTime.minute.toString().padLeft(2, '0');

    return '${dateTime.day}/${dateTime.month}/${dateTime.year} · '
        '$hour:$minute';
  }

  static String _formatDateOnly(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
