import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agenda_ia/models/agenda_item.dart';
void main(){test('migra valores anteriores',(){final i=AgendaItem.fromMap({'id':'1','type':'task','title':'Tarea','rawText':'Tarea','createdAt':'2026-08-19T10:00:00.000'});expect(i.alertMode,AlertMode.soundAndVibration);expect(i.recurrence,RecurrenceType.none);expect(i.archived,false);});}
