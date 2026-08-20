import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agenda_ia/models/agenda_item.dart';
import 'package:mi_agenda_ia/services/alarm_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.miagendaia/alarm');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getAlarmPermissionStatus') {
        return <String, bool>{
          'notifications': true,
          'exactAlarms': false,
          'fullScreenIntent': true,
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('programar una actividad no abre la configuración de permisos', () async {
    final now = DateTime.now();
    final item = AgendaItem(
      id: 'recordatorio-1',
      type: AgendaItemType.reminder,
      title: 'Tomar medicina',
      rawText: 'Recuérdame tomar medicina',
      dateTime: now.add(const Duration(hours: 2)),
      createdAt: now,
      updatedAt: now,
    );

    await AlarmBridge().scheduleItem(item);

    expect(
      calls.map((call) => call.method),
      containsAllInOrder(<String>['cancelItem', 'scheduleAlarm']),
    );
    expect(
      calls.where((call) => call.method == 'requestAlarmPermissions'),
      isEmpty,
    );
  });

  test('una nota no solicita permisos ni programa alarmas', () async {
    final now = DateTime.now();
    final item = AgendaItem(
      id: 'nota-1',
      type: AgendaItemType.note,
      title: 'Idea',
      rawText: 'Anota una idea',
      createdAt: now,
      updatedAt: now,
    );

    await AlarmBridge().scheduleItem(item);

    expect(calls.map((call) => call.method), <String>['cancelItem']);
  });

  test('lee por separado el estado de los permisos de alarma', () async {
    final status = await AlarmBridge().getPermissionStatus();

    expect(status.notifications, true);
    expect(status.exactAlarms, false);
    expect(status.fullScreenIntent, true);
  });
}
