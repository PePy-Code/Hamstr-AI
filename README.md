# AI---AT---Swift-PRELIMINAR-

Entrenador académico en Swift para apoyar a estudiantes con problemas de atención y TDAH.

## ¿Qué es este proyecto?

Este repositorio contiene una **librería Swift Package Manager (SPM)** con la lógica principal de una app de entrenamiento académico:
- gestión de agenda,
- sesiones de estudio tipo Pomodoro,
- chat de apoyo con guardrails,
- entrenamiento mental por trivia,
- motor de racha,
- planificación de notificaciones.

> La UI final de app iOS debe vivir en un proyecto Xcode separado que consuma este paquete.

## Configuración de la API de Groq

La integración de Groq está implementada en:
- `Sources/AI---AT---Swift-PRELIMINAR-/Services/OpenSourceKnowledgeService.swift`

Modelo configurado actualmente:
- `llama-3.3-70b-versatile`

### Opción recomendada: variable de entorno

1. Obtén tu API key en Groq.
2. Define la variable de entorno `GROQ_API_KEY` antes de ejecutar pruebas o la app.

Ejemplo (macOS/Linux):

```bash
export GROQ_API_KEY="tu_api_key"
```

### Opción temporal para desarrollo local

1. Abre este archivo:
   - `Sources/AI---AT---Swift-PRELIMINAR-/Configuration/LocalSecrets.swift`
2. Asigna tu key en `LocalSecrets.groqAPIKey`.

```swift
static let groqAPIKey: String = "tu_api_key"
```

3. No subas keys reales al repositorio.

### Prioridad de credenciales

La resolución de la key sigue este orden:
1. `GROQ_API_KEY` (entorno)
2. `LocalSecrets.groqAPIKey`

Si no hay key, el servicio usa fuentes abiertas (DuckDuckGo/Wikipedia) y fallback local.

## Features principales

- **Agenda académica (CRUD)**
  - crear, listar, actualizar, completar, marcar pendiente y eliminar actividades.
- **Sesión de actividad con apoyo contextual**
  - al iniciar estudio/tarea, intenta obtener fuentes directas para estudiar.
- **Persistencia local de agenda**
  - guardado/carga en JSON (`agenda.json`) con `Codable`.
- **Chat de apoyo académico con guardrails**
  - evita resolver tareas directamente,
  - prioriza orientación y fuentes de estudio.
- **Entrenador mental (trivia)**
  - preguntas de opción múltiple,
  - continúa en tiempo real y termina al primer error.
- **Motor de racha**
  - sube por actividades del día completadas,
  - o por sesión mental válida en día sin agenda.
- **Notificaciones planificadas**
  - recordatorio diario,
  - motivación de entrenamiento mental,
  - finalización de Pomodoro.

## Frameworks, APIs y tecnologías utilizadas

- **Lenguaje:** Swift 6
- **Gestión de paquete:** Swift Package Manager (SPM)
- **Plataformas objetivo:** iOS 17+, macOS 14+
- **Frameworks base:**
  - `Foundation`
  - `FoundationNetworking` (cuando aplica)
- **Concurrencia:** `async/await`, `actor`, `Sendable`
- **Persistencia local:** archivo JSON con `Codable`
- **APIs externas:**
  - **Groq Chat Completions API** (`https://api.groq.com/openai/v1/chat/completions`)
  - **DuckDuckGo Instant Answer API**
  - **Wikipedia OpenSearch API**
- **Testing:** Swift Testing (`import Testing`)

## Cómo usar este paquete

### 1) Compilar y probar

Desde la raíz del repositorio:

```bash
swift build
swift test
```

### 2) Integrarlo en una app iOS (Xcode)

1. Crea una app iOS en Xcode (SwiftUI).
2. En tu proyecto: `File > Add Package Dependencies... > Add Local...`.
3. Selecciona la carpeta de este repositorio.
4. Agrega el producto `AI---AT---Swift-PRELIMINAR-` al target de la app.
5. Importa el módulo `AI___AT___Swift_PRELIMINAR_` en tu app.

## Seguridad

- Nunca hardcodees claves reales en commits.
- Usa `GROQ_API_KEY` para entornos de desarrollo/CI.
- `LocalSecrets.swift` debe mantenerse con valor vacío en el código compartido.
