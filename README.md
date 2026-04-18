# AI---AT---Swift-PRELIMINAR-
Entrenador académico para IOS con el propósito de apoyar a estudiantes con problemas de atención y TDAH

## Implementación base incluida

- Arquitectura modular con capas de dominio, servicios y UI mínima reemplazable.
- **Agenda** con CRUD básico, inicio de actividad y sesión tipo pomodoro.
- Integración de **Apple Intelligence** abstraída por protocolo con fallback local seguro.
- **Entrenador Mental** con trivia de opción múltiple y reglas de game over/reintento.
- **Motor de racha** con reglas:
  - Día con actividades: racha válida solo si todas se completan.
  - Día sin actividades: racha válida con 1 entrenamiento mental válido.
- Planificador de notificaciones para día con/sin actividades.
- Pruebas unitarias para reglas de racha, trivia, agenda y notificaciones.
