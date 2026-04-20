# Hamstr AI 🐹
<div align="center">
<img width="350" height="350" alt="hamlet" src="https://github.com/user-attachments/assets/db7bf850-5d55-405d-9cdf-e0af7fda1f9a" /> 
  
</div>
Un entrenador académico en Swift pensado para estudiantes con problemas de atención y TDAH.

La idea del proyecto es ayudarte a **estudiar con estructura**, mantener la motivación y recibir apoyo sin caer en respuestas automáticas que te resuelvan todo.

Es la solucion ideal para aquello sestudiantes que necesitan estructura y concentracion para sus actividades diarias.

## Screenshots

<div align="center" style="display: flex; justify-content: center; gap: 10px; flex-wrap: nowrap;">
  <img src="https://github.com/user-attachments/assets/a7fe7919-5119-4477-accb-f60bd3090aed" width="220"/>
  <img src="https://github.com/user-attachments/assets/aedec5bd-f952-42da-a1a3-ac3cb2ad02e5" width="220"/>
  <img src="https://github.com/user-attachments/assets/b036a26a-9da1-4efe-bcd2-a55032377567" width="220"/>
</div>

## ¿Qué incluye?

Este repositorio contiene una librería en **Swift Package Manager (SPM)** con la lógica principal de la app:

- Agenda académica (crear, editar, completar actividades)
- Sesiones tipo Pomodoro con apoyo contextual
- Chat de apoyo con guardrails
- Entrenador mental tipo trivia
- Sistema de racha (streak)
- Planificación de notificaciones

> La interfaz final de iOS vive en un proyecto Xcode separado que consume este paquete.

## Características más llamativas ✨

- **Chat que orienta en lugar de resolver tareas**: prioriza guía y fuentes útiles.
- **Modo estudio con contexto**: al iniciar una actividad, intenta traer material de apoyo.
- **Entrenador mental dinámico**: trivia de opción múltiple, avance en tiempo real y fin al primer error.
- **Racha inteligente**: recompensa constancia diaria (agenda o sesión válida de entrenamiento).
- **Persistencia local simple y robusta**: datos guardados en JSON con `Codable`.

## Frameworks y tecnologías usadas

- **Lenguaje:** Swift 6 (modo Swift 6)
- **Gestión del proyecto:** Swift Package Manager (SPM)
- **Plataformas objetivo:** iOS 17+ y macOS 14+
- **Frameworks principales:**
  - `Foundation`
  - `FoundationNetworking` (cuando aplica)
  - `SwiftUI`
  - `UserNotifications`
  - `PhotosUI`
  - `AudioToolbox`
  - `UIKit` / `AppKit` (según plataforma)
- **Concurrencia moderna:** `async/await`, `actor`, `Sendable`
- **Persistencia:** JSON + `Codable`
- **APIs externas:**
  - Groq Chat Completions API
  - DuckDuckGo Instant Answer API
  - Wikipedia OpenSearch API
- **Testing:** Swift Testing (`import Testing`)

## Configuración de la API de Groq

Integración principal:

- `Sources/AI---AT---Swift-PRELIMINAR-/Services/OpenSourceKnowledgeService.swift`

Modelo configurado actualmente:

- `llama-3.3-70b-versatile`

### Opción recomendada (variable de entorno)

1. Consigue tu API key en Groq.
2. Define la variable `GROQ_API_KEY` antes de ejecutar pruebas o la app.

```bash
export GROQ_API_KEY="tu_api_key"
```

### Opción temporal para desarrollo local

1. Abre:
   - `Sources/AI---AT---Swift-PRELIMINAR-/Configuration/LocalSecrets.swift`
2. Asigna tu key en `LocalSecrets.groqAPIKey`.

```swift
static let groqAPIKey: String = "tu_api_key"
```

3. No subas claves reales al repositorio.

### Prioridad de credenciales

1. `GROQ_API_KEY` (entorno)
2. `LocalSecrets.groqAPIKey`

Si no hay key, el servicio usa fuentes abiertas (DuckDuckGo/Wikipedia) y fallback local.

## Cómo usar el paquete

Desde la raíz del repositorio:

```bash
swift build
swift test
```

## Integración en app iOS (Xcode)

1. Crea tu app iOS en Xcode.
2. Ve a `File > Add Package Dependencies... > Add Local...`.
3. Selecciona la carpeta de este repositorio.
4. Agrega el producto `AI---AT---Swift-PRELIMINAR-` a tu target.
5. Importa el módulo `AI___AT___Swift_PRELIMINAR_`.

## Recursos de diseño

### App icon

- Imagen base: `UIDesignConcept/hamlet.jpg`
- Set listo: `UIDesignConcept/AppIcon.appiconset`

Script opcional de instalación:

```bash
./Scripts/install_app_icon.sh /ruta/a/TuApp/Assets.xcassets
```

### UI Concept Art

La carpeta `UIDesignConceptArt/` conserva referencias visuales para:

- menú principal / chat
- actividad / Pomodoro
- agenda
- entrenador
- ajustes

## Seguridad

- Nunca hardcodees claves reales en commits.
- Usa `GROQ_API_KEY` en desarrollo/CI.
- Mantén `LocalSecrets.swift` con valores vacíos en código compartido.
