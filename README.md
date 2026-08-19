# Mi Agenda IA — versión 0.1.4

Versión de validación Android de una agenda personal controlada por voz o texto.

## Auditoría realizada antes de esta entrega

Se revisaron de forma integral:

- `pubspec.yaml` y compatibilidad de dependencias.
- Uso actual de `speech_to_text` 7.4.0.
- Uso actual de `flutter_local_notifications` 22.3.0.
- Migración de almacenamiento a `SharedPreferencesAsync`.
- Inicialización del reconocimiento de voz una sola vez.
- Selección segura de español disponible en el dispositivo.
- Clasificador Nota / Tarea / Recordatorio / Calendario.
- Pruebas del parser, incluyendo números que no deben convertirse en horas.
- Permisos Android de micrófono y reconocimiento de voz.
- Configuración Android para notificaciones programadas.
- Desugaring, Java 17, compileSdk 36, minSdk 24, AGP 8.11.1 y Gradle 8.13.
- Flujo de Codemagic con Flutter 3.38.1 fijado para evitar cambios de versión.
- El análisis no falla por avisos informativos (`--no-fatal-infos`), pero sí
  continúa bloqueando errores y advertencias reales.

## Qué hace la versión 0.1.4

- Pantalla principal azul.
- Botón grande para hablar.
- Entrada manual manteniendo pulsado el botón.
- Convierte voz a texto mediante las capacidades del dispositivo.
- Interpreta Nota, Tarea, Recordatorio o Evento.
- Permite confirmar/corregir el tipo y la fecha antes de guardar.
- Guarda elementos localmente.
- Programa notificaciones locales cuando hay fecha y hora.

## Build

El workflow `Mi Agenda IA 0.1.4 - APK auditado` ejecuta:

1. Validación de estructura y YAML.
2. Generación/validación Android.
3. `flutter pub get`.
4. Verificación de formato.
5. `flutter analyze --no-fatal-infos`.
6. `flutter test`.
7. `flutter build apk --debug`.

El artefacto esperado es:

`Mi-Agenda-IA-0.1.4.apk`


## Corrección 0.1.3

La validación previa de Codemagic ya no importa `yaml`/PyYAML ni ninguna
librería Python externa. Solo usa shell, `grep`, `test` y la biblioteca
estándar de Python. Esto evita fallos del entorno de CI antes de ejecutar
Flutter.


## Corrección 0.1.4

- Eliminado un carácter `\\` accidental al inicio de `intent_parser.dart`.
- El paso de formato ahora aplica `dart format` en vez de fallar por cambios de estilo.
