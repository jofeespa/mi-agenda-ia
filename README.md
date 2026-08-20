# Mi Agenda IA — versión 0.4.0

La 0.4 convierte los avisos en una experiencia tipo despertador.

## Funciones nuevas

- Tono predeterminado configurable desde Perfil.
- Botón `Terminar dictado` durante la grabación; también sigue funcionando
  el cierre automático por silencio o tiempo.
- Fecha/hora sugerida para nuevas tareas, recordatorios y calendario:
  hora actual + 1 hora.
- Modos de aviso:
  - Tono + vibración
  - Alarma fuerte + vibración
  - Solo tono
  - Leer actividad con voz
  - Tono + voz
  - Solo vibración
  - Silencioso
- Aviso anticipado: al momento, 10 min, 30 min o 1 hora antes.
- Duración del sonido/voz/vibración: 20 s, 30 s, 1 min o Hasta responder.
- Repetición si no se responde: desactivada, 5, 10 o 15 minutos.
- Pantalla nativa de alarma tipo despertador:
  - se muestra sobre pantalla bloqueada;
  - enciende la pantalla;
  - solicita retirar keyguard cuando Android lo permite;
  - nunca salta PIN, patrón, contraseña o biometría;
  - no se cierra con el botón Atrás;
  - queda pendiente hasta elegir una acción.
- Acciones grandes:
  - OK / Terminar
  - Completar tarea
  - Posponer 10 minutos
  - Posponer 30 minutos
  - Posponer 1 hora
  - Reprogramar
- Historial, recurrencias, exportación TXT, ayuda de voz y selector de tonos
  continúan disponibles.

## Android

La implementación usa AlarmManager, foreground service, TextToSpeech,
full-screen intent, setShowWhenLocked, setTurnScreenOn y
requestDismissKeyguard.

En Android moderno, el usuario puede tener que conceder expresamente permisos
de notificación, alarmas exactas y pantalla completa. La app expone
`Perfil > Permisos de alarmas` para abrir esas autorizaciones.

Workflow Codemagic:
`Mi Agenda IA 0.4.0 - APK de prueba`

APK:
`Mi-Agenda-IA-0.4.0.apk`
