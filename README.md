# Mi Agenda IA — versión 0.2.0

Versión de prueba con las observaciones recibidas después de instalar y usar la
0.1.5 en un teléfono Android.

## Cambios incluidos

### Edición
- Toca cualquier elemento para editarlo.
- Se puede cambiar título, tipo, fecha/hora, alerta y progreso.
- Se puede eliminar un elemento.
- Al editar una actividad programada se cancela el aviso anterior y se programa
  el nuevo.

### Fecha y hora obligatorias
- Tareas, recordatorios y eventos de calendario exigen fecha y hora antes de
  guardar.
- Las notas siguen sin fecha/hora.

### Progreso de tareas
- Las tareas tienen avance de 0 a 100 %.
- El progreso se muestra directamente en la tarjeta.
- 100 % marca la tarea como completada.

### Clasificación
- Inicio incluye filtros: Todos, Tareas y Recordatorios.
- Calendario muestra únicamente eventos.
- Notas muestra únicamente notas.

### Navegación
- Los botones inferiores Inicio / Calendario / Notas / Perfil funcionan mediante
  navegación interna.

### Nombre
- La primera vez que abre la versión 0.2, la app pregunta el nombre.
- El nombre queda guardado localmente y aparece en el saludo.
- Se puede editar desde Perfil.

### Avisos
Para tareas, recordatorios y eventos se puede escoger:
- Sonido + vibración
- Aviso fuerte
- Solo vibración
- Sin sonido ni vibración

Los avisos se programan como notificaciones locales de Android y no requieren
abrir la app en el momento del recordatorio.

## Compatibilidad con datos anteriores
Los elementos guardados por la 0.1.5 se intentan conservar. Los campos nuevos
(progreso y modo de alerta) reciben valores predeterminados.

## Build
Workflow esperado en Codemagic:

`Mi Agenda IA 0.2.0 - APK de prueba`

Artefacto esperado:

`Mi-Agenda-IA-0.2.0.apk`
