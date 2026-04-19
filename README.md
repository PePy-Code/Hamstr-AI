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

Este repositorio ahora expone **solo la librería SPM**.  
La app iOS debe vivir en un proyecto Xcode separado que consuma este paquete local.

1. Crea un nuevo proyecto Xcode (`File > New > Project... > iOS App`) con SwiftUI.
2. Usa como Bundle Identifier: `com.pepy.academictrainer`.
3. En el proyecto de app: `File > Add Package Dependencies... > Add Local...` y selecciona la carpeta de este repositorio.
4. Agrega el producto `AI---AT---Swift-PRELIMINAR-` al target de la app.
5. En el `@main` de tu app, importa `AI___AT___Swift_PRELIMINAR_` y presenta `HomeView()`.
6. Selecciona un simulador iOS y ejecuta con `Run` (⌘R).

> SwiftPM por sí solo no genera un `.app` iOS con `bundle identifier`, signing y entitlements completos para simulador/dispositivo.

La app inicia en `HomeView` y desde ahí puedes probar:
- botón rápido `+` del menú principal,
- inicio de actividad con flujo `Finalizar/Pendiente`,
- popups encadenados de finalización,
- Pomodoro trabajo/descanso,
- chatbot con guardrails para no resolver tareas directamente.

## Configuración temporal de API key (Xcode)

Si quieres hardcodear la key temporalmente:

1. Abre el paquete en Xcode.
2. Ve a `Sources/AI---AT---Swift-PRELIMINAR-/Configuration/LocalSecrets.swift`.
3. Reemplaza `LocalSecrets.groqAPIKey` con tu key.

`GROQ_API_KEY` por variable de entorno sigue teniendo prioridad si está definida.
