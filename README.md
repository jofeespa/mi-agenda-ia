# Mi Agenda IA — versión 0.1

Primera versión de prueba para Android de una agenda personal controlada principalmente por voz.

## Qué incluye esta versión

- Interfaz principal en tonos azules.
- Botón central de micrófono.
- Reconocimiento de voz en español de Ecuador (`es_EC`).
- Clasificación local de órdenes como nota, tarea, recordatorio o evento.
- Interpretación básica de expresiones como `hoy`, `mañana`, días de la semana y horas.
- Confirmación antes de guardar lo interpretado.
- Corrección manual de tipo, fecha y hora.
- Almacenamiento local de los elementos.
- Notificaciones locales para tareas, recordatorios y eventos con fecha/hora.
- Entrada escrita manteniendo presionado el botón del micrófono.

## Ejemplos para probar

- `Anota una idea para mi tesis.`
- `Recuérdame llamar a Juan mañana a las 9.`
- `Tengo que entregar el informe viernes a las 4 de la tarde.`
- `Agenda reunión con el director el jueves a las 3 de la tarde.`

## Compilación en Codemagic

El repositorio incluye `codemagic.yaml`. El flujo `android-debug` hace lo siguiente automáticamente:

1. Usa Flutter estable en la nube.
2. Genera el host Android compatible con esa versión de Flutter.
3. Añade los permisos de micrófono, reconocimiento de voz y notificaciones.
4. Configura Android para notificaciones programadas.
5. Ejecuta `flutter pub get`.
6. Ejecuta `flutter analyze` y `flutter test`.
7. Genera `Mi-Agenda-IA-0.1.apk`.

La carpeta `android/` se genera durante la compilación. Esto es intencional: evita guardar una plantilla Gradle que pueda quedar desactualizada respecto a la versión de Flutter disponible en Codemagic.

## Alcance de 0.1

Esta versión usa reglas locales simples para interpretar las frases; todavía no integra un modelo de IA remoto. El objetivo es validar primero el flujo real en tu teléfono: abrir, hablar, interpretar, confirmar, guardar y recibir una notificación.
