# AI---AT---Swift-PRELIMINAR-
Entrenador académico para iOS con el propósito de apoyar a estudiantes con problemas de atención y TDAH

## Implementación base incluida

- Arquitectura modular con capas de dominio, servicios y UI mínima reemplazable.
- **Agenda** con CRUD básico, inicio de actividad y sesión tipo pomodoro, incluyendo marcado de estado (pendiente / en progreso / realizada).
- Persistencia local de Agenda en JSON (base de datos local de archivo).
- Integración de **Apple Intelligence** abstraída por protocolo con fallback local seguro y soporte opcional para agente local con Foundation Models cuando esté disponible.
- **Entrenador Mental** con trivia de opción múltiple y reglas de game over/reintento.
- **Motor de racha** con reglas:
  - Día con actividades: racha válida solo si todas se completan.
  - Día sin actividades: racha válida con 1 entrenamiento mental válido.
- Notificaciones implementadas para:
  - fin de temporizador Pomodoro,
  - recordatorios diarios según agenda,
  - mensajes motivacionales para impulsar entrenamiento mental.
- Pruebas unitarias para reglas de racha, trivia, agenda y notificaciones.

## Ejecutar en simulador de Xcode

1. Abre el paquete con Xcode (`File > Open...`) apuntando a este repositorio.
2. Selecciona el esquema **AcademicTraineriOS** (target de app iOS con bundle identifier).
3. Elige un simulador iOS (por ejemplo iPhone 16).
4. Ejecuta con `Run` (⌘R).

> Si no aparece `AcademicTraineriOS`, usa `File > Packages > Reset Package Caches` y vuelve a abrir el proyecto.

La app inicia en `HomeView` y desde ahí puedes probar:
- botón rápido `+` del menú principal,
- inicio de actividad con flujo `Finalizar/Pendiente`,
- popups encadenados de finalización,
- Pomodoro trabajo/descanso,
- chatbot con guardrails para no resolver tareas directamente.
