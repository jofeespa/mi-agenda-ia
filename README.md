# Mi Agenda IA — versión 0.3.1

Incluye alarmas persistentes con sonido propio en bucle y vibración repetida, acciones OK / Posponer 10 min / Reprogramar, historial, tareas al 100% archivadas, recordatorios/eventos atendidos archivados, recurrencias diarias/semanales/mensuales con fecha final y exportación de notas a TXT.

Workflow: `Mi Agenda IA 0.3.1 - APK de prueba`

APK: `Mi-Agenda-IA-0.3.1.apk`


## Corrección 0.3.1

La compilación 0.3.0 falló durante `flutter analyze` porque todavía quedaba
`lib/services/notification_service.dart`, perteneciente al sistema de avisos
anterior. Ese archivo seguía usando `AlertMode.normal` y
`AlertMode.vibration`, nombres que ya no existen desde que la 0.3 migró al
sistema de alarmas persistentes nativo.

La 0.3.1 elimina por completo ese camino antiguo y deja una sola arquitectura
de avisos:

`AlarmBridge (Dart) -> AlarmManager -> AlarmReceiver -> AlarmService (Android)`

También se retiraron las dependencias Flutter que ya no se utilizan
(`flutter_local_notifications`, `timezone`, `flutter_timezone`) y el import
directo de `cross_file`.
