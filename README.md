# Mi Agenda IA — versión 0.1.1

Versión de prueba Android de una agenda personal controlada principalmente por voz.

## Qué cambia respecto de 0.1

- Codemagic usa `mac_mini_m2`.
- Android se genera **dentro del propio proyecto**, no en una carpeta temporal.
- `flutter create` se ejecuta con `--no-pub` para evitar una resolución de dependencias innecesaria.
- Después se aplican permisos de micrófono, notificaciones y ajustes de Android.
- La compilación genera `Mi-Agenda-IA-0.1.1.apk`.

## Flujo de compilación

1. Mostrar versiones de Flutter y Java.
2. Generar la plataforma Android.
3. Descargar dependencias.
4. Ejecutar `flutter analyze`.
5. Ejecutar pruebas.
6. Compilar APK debug instalable.

## Funciones de esta prueba

- Inicio en tonos azules.
- Botón principal de voz.
- Entrada manual como alternativa.
- Clasificación de texto en Nota, Tarea, Recordatorio o Evento.
- Confirmación antes de guardar.
- Persistencia local.
- Notificaciones locales para elementos con fecha y hora.

Esta es una versión MVP de validación; aún no representa la aplicación completa.
