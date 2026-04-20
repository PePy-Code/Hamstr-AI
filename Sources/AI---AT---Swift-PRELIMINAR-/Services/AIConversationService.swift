import Foundation

public struct AIConversationService: AIConversationProviding {
    private let fallback = LocalFallbackGenerator()
    private let openSourceKnowledge: OpenSourceKnowledgeProviding

    public init(
        openSourceKnowledge: OpenSourceKnowledgeProviding = OpenSourceKnowledgeService()
    ) {
        self.openSourceKnowledge = openSourceKnowledge
    }

    public func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        let safeTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeTopic.isEmpty else { return [friendlyGreeting()] }

        if let openAnswer = await openSourceKnowledge.answer(for: startSupportPrompt(for: safeTopic)) {
            let directSources = extractDirectSources(from: openAnswer)
            if !directSources.isEmpty { return Array(directSources.prefix(3)) }
        }

        if let openAnswer = await openSourceKnowledge.answer(for: safeTopic) {
            let directSources = extractDirectSources(from: openAnswer)
            if !directSources.isEmpty { return Array(directSources.prefix(3)) }
        }

        switch type {
        case .task, .study:
            return [friendlyGreeting()]
        case .other:
            return []
        }
    }

    public func chatReply(
        userMessage: String,
        history: [ConversationTurn],
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        let cleanedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuery = [cleanedTitle, cleanedTopic]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let query = cleanedMessage.isEmpty ? fallbackQuery : cleanedMessage
        let displayContext = query.isEmpty ? "tu actividad actual" : query
        let asksToSolveDirectly = isDirectSolveRequest(cleanedMessage)
        if asksToSolveDirectly {
            let sourceQuery = sourceOnlyPrompt(for: displayContext)
            if let sourceAnswer = await openSourceKnowledge.answer(for: sourceQuery, history: history) {
                let directSources = extractDirectSources(from: sourceAnswer)
                if !directSources.isEmpty {
                    return refusalWithSources(directSources)
                }
                let cleanedSourceAnswer = sourceAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedSourceAnswer.isEmpty {
                    return refusalWithoutSources(context: displayContext) + "\n\n" + cleanedSourceAnswer
                }
            }
            return refusalWithoutSources(context: displayContext)
        }

        let guardedQuery = guidedChatPrompt(for: query, activityTitle: cleanedTitle, topic: cleanedTopic)
        if let openAnswer = await openSourceKnowledge.answer(for: query, history: history),
           !openAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = cleanChatResponse(openAnswer)
            if !cleaned.isEmpty { return cleaned }
        }

        if let guardedOpenAnswer = await openSourceKnowledge.answer(for: guardedQuery, history: history),
           !guardedOpenAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = cleanChatResponse(guardedOpenAnswer)
            if !cleaned.isEmpty { return cleaned }
        }

        return fallbackChatReply(title: cleanedTitle, context: displayContext)
    }

    public func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        let validatedCount = max(1, count)
        let validatedCategories = categories.isEmpty ? TriviaCategory.allCases : categories
        let validatedDifficulty = min(max(difficulty, 1), 5)

        let prompt = triviaGenerationPrompt(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
        if let generated = await openSourceKnowledge.answer(for: prompt) {
            let parsed = LocalAgentResponseParser.parseTriviaQuestions(
                from: generated,
                categories: validatedCategories,
                limit: validatedCount
            )
            if parsed.count == validatedCount {
                return parsed.shuffled()
            }
        }

        return fallback.defaultQuestions(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
    }

    public func mascotSupportMessage(
        todayActivities: [Activity],
        tomorrowActivities: [Activity],
        streakDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> String {
        let upcoming = upcomingActivities(
            todayActivities: todayActivities,
            tomorrowActivities: tomorrowActivities,
            now: now
        )
        let prompt = mascotMessagePrompt(
            todayActivities: todayActivities,
            tomorrowActivities: tomorrowActivities,
            upcomingActivities: upcoming,
            streakDays: streakDays,
            now: now,
            calendar: calendar
        )

        if let aiAnswer = await openSourceKnowledge.answer(for: prompt) {
            let cleaned = sanitizeMascotMessage(aiAnswer)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return fallbackMascotMessage(
            todayActivities: todayActivities,
            tomorrowActivities: tomorrowActivities,
            upcomingActivities: upcoming,
            streakDays: streakDays,
            now: now
        )
    }
}

private extension AIConversationService {
    enum MascotMessageConfig {
        static let upcomingHorizonSeconds: TimeInterval = 6 * 60 * 60
        static let maxMessageLength = 220
        static let urgentActivityThresholdMinutes = 90

        static let mascotMoods: [String] = [
            "entusiasta y lleno de energía",
            "tranquilo y filosófico",
            "travieso con humor sutil",
            "cálido y paternal",
            "inspirador y poético",
            "directo y práctico",
            "misterioso y curioso",
            "orgulloso del estudiante",
            "gracioso con una pizca de sabiduría",
            "soñador pero concreto"
        ]

        /// Temas de bienestar que Hamlet Hamster puede traer a colación cuando no hay urgencia inmediata.
        /// Diseñados para estudiantes +15 años que pueden tener dificultades de concentración o TDAH.
        static let wellbeingAngles: [String] = [
            "técnica de enfoque para TDAH: bloques de 10-15 min con pausa activa",
            "ancla sensorial: un objeto o aroma que indique 'hora de estudiar'",
            "la regla de los 2 minutos: si algo tarda menos de 2 min, hazlo ahora y despeja la mente",
            "body doubling: estudiar con alguien cerca (aunque sea por videollamada) ayuda a mantenerse",
            "música sin letra o ruido blanco para reducir distracción auditiva",
            "dividir la tarea en pasos mini: solo el primer paso importa ahora mismo",
            "movimiento antes de estudiar: 5 min de ejercicio activan el lóbulo prefrontal",
            "modo avión para el teléfono: 20 min sin notificaciones cambia el juego",
            "hidratación y respiración profunda: el cerebro funciona mejor bien oxigenado",
            "recompensa planificada: define qué harás después de estudiar como motivación extra",
            "journaling de 2 minutos: vaciar la mente antes de empezar reduce el ruido interno",
            "ambiente visual limpio: despeja el escritorio antes de abrir el libro"
        ]

        static func randomMood() -> String {
            mascotMoods.randomElement() ?? mascotMoods[0]
        }

        static func randomWellbeingAngle() -> String {
            wellbeingAngles.randomElement() ?? wellbeingAngles[0]
        }
    }

    func startSupportPrompt(for context: String) -> String {
        """
        Inicio de actividad de estudio: \(context).
        Devuelve hasta 3 fuentes directas confiables (URL completas) para estudiar ese tema.
        Formato preferido por línea: "Fuente directa: https://...".
        Si no encuentras fuentes directas, responde solo: SALUDO_AMIGABLE.
        """
    }

    func guidedChatPrompt(for query: String, activityTitle: String, topic: String) -> String {
        let safeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Contexto de actividad:
        - Título: \(safeTitle.isEmpty ? "sin título" : safeTitle)
        - Tema: \(safeTopic.isEmpty ? "sin tema" : safeTopic)
        Consulta del usuario: \(safeQuery.isEmpty ? "sin consulta explícita" : safeQuery)
        """
    }

    func sourceOnlyPrompt(for context: String) -> String {
        """
        El usuario pidió que le resuelvan una tarea/ejercicio sobre: \(context).
        No resuelvas el trabajo. Devuelve solo fuentes directas de estudio (URLs completas) relacionadas.
        Formato por línea: "Fuente directa: https://...".
        """
    }

    func extractDirectSources(from text: String) -> [String] {
        let pattern = #"https?://[^\s\)\]\}>,]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        let urls = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var seen = Set<String>()
        return urls
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .map { "Fuente directa: \($0)" }
    }

    func isDirectSolveRequest(_ message: String) -> Bool {
        let normalized = " \(message.lowercased()) "
        let solveTokens = [
            " resuelve ", " resuélveme ", " resuélvelo ", " hazme la tarea ", " haz la tarea ", " dame la respuesta ",
            " responde por mí ", " escribe el ensayo ", " dame el resultado ", " soluciona "
        ]
        return solveTokens.contains { normalized.contains($0) }
    }

    func friendlyGreeting() -> String {
        "Soy Hamlet Hamster 🐹 No encontré fuentes directas ahora mismo, pero puedo ayudarte a enfocar tu estudio paso a paso."
    }

    func refusalWithSources(_ sources: [String]) -> String {
        let bulletList = sources.prefix(3).map { "• \($0)" }.joined(separator: "\n")
        return "Eso tienes que desarrollarlo tú — así es como se aprende de verdad.\n\nTe dejo estas fuentes para orientarte:\n\n\(bulletList)"
    }

    func refusalWithoutSources(context: String) -> String {
        "Mejor que lo trabajes tú mismo 🐹\n\nSi quieres, armo un plan de estudio sobre \"\(context)\" y te comparto fuentes directas."
    }

    func fallbackChatReply(title: String, context: String) -> String {
        let safeTitle = title.isEmpty ? "tu actividad" : title
        return cleanChatResponse("Entendido. Puedo ayudarte con \"\(safeTitle)\" sobre \"\(context)\".\n\nDime la pregunta exacta o dame más contexto.")
    }

    private func cleanChatResponse(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = stripCommonOpeningPhrase(from: text)

        // Collapse runs of 3+ newlines down to one blank line between paragraphs.
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        // Collapse inline multiple spaces/tabs to a single space.
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)

        // Deduplicate consecutive identical paragraphs while preserving paragraph breaks.
        let rawParagraphs = text.components(separatedBy: "\n\n")
        var dedupedParagraphs: [String] = []
        var seenNormalized = Set<String>()
        for paragraph in rawParagraphs {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParagraph.isEmpty else { continue }
            let cleanedParagraph = stripCommonOpeningPhrase(from: trimmedParagraph)
            guard !cleanedParagraph.isEmpty else { continue }
            let normalized = cleanedParagraph.lowercased()
            guard !seenNormalized.contains(normalized) else { continue }
            seenNormalized.insert(normalized)
            dedupedParagraphs.append(cleanedParagraph)
        }

        let result = dedupedParagraphs.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }

    private func stripCommonOpeningPhrase(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let leadingCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",!:.-"))

        let openingPhrases = [
            "hola", "¡hola!", "claro", "por supuesto", "entiendo",
            "genial", "perfecto", "buena pregunta", "excelente pregunta"
        ]
        let lowered = trimmed.lowercased()
        for phrase in openingPhrases where lowered.hasPrefix(phrase) {
            let phraseEnd = trimmed.index(trimmed.startIndex, offsetBy: phrase.count, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            var remainder = String(trimmed[phraseEnd...])
            if let firstValidScalar = remainder.unicodeScalars.firstIndex(where: { !leadingCharacters.contains($0) }) {
                remainder = String(remainder.unicodeScalars[firstValidScalar...])
            } else {
                remainder = ""
            }
            return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    func triviaGenerationPrompt(count: Int, categories: [TriviaCategory], difficulty: Int) -> String {
        let categoryTokens = categories.map(\.rawValue).joined(separator: ", ")
        return """
        Genera \(count) preguntas de trivia aleatorias en español.
        Categorías permitidas: \(categoryTokens).
        Dificultad aproximada de 1 a 5: \(difficulty).

        Responde ÚNICAMENTE en JSON válido con este formato exacto:
        {
          "questions": [
            {
              "category": "math|history|science|popCulture",
              "prompt": "pregunta",
              "options": ["opción 1","opción 2","opción 3","opción 4"],
              "correctOptionIndex": 0,
              "imageURL": null
            }
          ]
        }

        Reglas obligatorias:
        - Exactamente \(count) preguntas.
        - Cada pregunta con 4 opciones.
        - Solo una opción correcta.
        - correctOptionIndex entre 0 y 3.
        - No incluyas explicación ni texto fuera del JSON.
        """
    }

    func upcomingActivities(
        todayActivities: [Activity],
        tomorrowActivities: [Activity],
        now: Date
    ) -> [Activity] {
        let horizon = now.addingTimeInterval(MascotMessageConfig.upcomingHorizonSeconds)
        return (todayActivities + tomorrowActivities)
            .filter { $0.status != .completed && $0.status != .failed }
            .filter { $0.scheduledAt >= now && $0.scheduledAt <= horizon }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func mascotMessagePrompt(
        todayActivities: [Activity],
        tomorrowActivities: [Activity],
        upcomingActivities: [Activity],
        streakDays: Int,
        now: Date,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "HH:mm"
        let upcomingRows = upcomingActivities.prefix(3).map { activity in
            let dayLabel = calendar.isDateInToday(activity.scheduledAt) ? "hoy" : "mañana"
            return "- \(activity.title) (\(dayLabel) \(formatter.string(from: activity.scheduledAt)))"
        }.joined(separator: "\n")

        let mood = MascotMessageConfig.randomMood()
        let wellbeing = MascotMessageConfig.randomWellbeingAngle()
        let pending = (todayActivities + tomorrowActivities)
            .filter { $0.status != .completed && $0.status != .failed }.count

        return """
        Eres Hamlet Hamster 🐹, un hamster molesto pero buena onda: travieso, un poco dramático, siempre amigable y siempre dispuesto a ayudar.
        Tu misión es acompañar al estudiante (15+ años, puede tener TDAH o dificultades de concentración) con un mensaje fresco y genuino cada vez que abre la app.

        Hoy tu humor es: \(mood).
        Tema de bienestar disponible: \(wellbeing).

        Contexto del estudiante:
        - Racha activa: \(streakDays) día(s).
        - Actividades pendientes hoy + mañana: \(pending).
        - Hora actual: \(formatter.string(from: now)).
        \(upcomingRows.isEmpty ? "" : "\nActividades próximas (en menos de 6 h):\n\(upcomingRows)")

        Instrucciones de escritura:
        - Escribe UN solo mensaje en español, máximo \(MascotMessageConfig.maxMessageLength) caracteres.
        - Sin markdown, sin links, sin listas.
        - Varía el inicio, el tono y los emojis en cada respuesta: nunca empieces igual dos veces.
        - Debe sentirse la personalidad de Hamlet Hamster: molestia ligera + ternura + apoyo real.
        - Puedes incluir una mini queja bromista (máximo una), pero jamás insultes ni hagas sentir mal al estudiante.
        - Si hay actividad próxima, prioriza ese aviso con cariño y un poco de urgencia.
        - Si la racha es alta (7+), celébralo con entusiasmo.
        - Si no hay nada urgente, elige entre: dar el tip de bienestar del día, una reflexión motivacional, un consejo de concentración o una metáfora ingeniosa.
        - El bienestar no es solo estudiar: también vale recordar respirar, moverse, hidratarse o descansar la mente.
        - Puedes hablar de Hamlet Hamster en tercera persona ocasionalmente, o en primera.
        - Lo único prohibido: repetir la misma estructura de mensaje dos veces seguidas.
        """
    }

    func sanitizeMascotMessage(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oneLine.isEmpty else { return "" }
        let maxLength = MascotMessageConfig.maxMessageLength
        guard oneLine.count > maxLength else { return oneLine }
        return String(oneLine.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fallbackMascotMessage(
        todayActivities: [Activity],
        tomorrowActivities: [Activity],
        upcomingActivities: [Activity],
        streakDays: Int,
        now: Date
    ) -> String {
        if let next = upcomingActivities.first {
            let minutes = max(Int(next.scheduledAt.timeIntervalSince(now) / 60), 0)
            if minutes <= MascotMessageConfig.urgentActivityThresholdMinutes {
                let urgent = [
                    "👀 Oye, en \(minutes) min toca \"\(next.title)\"... ¡Hamlet Hamster confía en ti!",
                    "⏰ \(minutes) minutos para \"\(next.title)\". Respira, enfócate y tú puedes.",
                    "🎯 Misión en \(minutes) min: \"\(next.title)\". ¡Tú ya sabes lo que hay que hacer!",
                    "🔔 Psst... \"\(next.title)\" llama en \(minutes) min. ¡Que no te agarre desprevenido!"
                ]
                return urgent.randomElement()!
            }
            let soon = [
                "🕒 Antes de que te relajes demasiado: \"\(next.title)\" está en camino. Prepara el terreno.",
                "📌 Próxima parada: \"\(next.title)\". Hamlet Hamster ya tiene el cronómetro listo.",
                "🌱 Un poco de preparación ahora para \"\(next.title)\" te ahorra estrés después.",
                "🗂️ \"\(next.title)\" se acerca. Échale un vistazo rápido y llegas con ventaja."
            ]
            return soon.randomElement()!
        }

        if streakDays >= 7 {
            let celebration = [
                "🔥 \(streakDays) días seguidos, ¡eso no es casualidad! Hamlet Hamster te mira con orgullo.",
                "🏆 \(streakDays) días de racha. Los hámsteres no aplaudimos, pero si pudiéramos...",
                "⚡ \(streakDays) días y contando. ¡Deja que el Trainer añada otro escalón hoy!",
                "🌟 \(streakDays) días. Hamlet Hamster dice: la constancia construye castillos de conocimiento."
            ]
            return celebration.randomElement()!
        }

        if todayActivities.isEmpty && tomorrowActivities.isEmpty {
            let free = [
                "🌿 Día sin agenda, mente libre. ¿Y si le das al Trainer solo 5 minutos?",
                "🎲 Sin compromisos hoy. Es el momento perfecto para explorar el Trainer sin prisa.",
                "💭 Agenda en blanco... ¿Qué tal un round de trivia para calentar neuronas?",
                "🐛 Hamlet Hamster dice: los días tranquilos son los mejores para aprender algo nuevo."
            ]
            return free.randomElement()!
        }

        let general = [
            "💡 Un paso pequeño hoy vale más que un salto perfecto mañana. ¡Dale!",
            "🧠 El Trainer espera. 5 minutos bastan para despertar al cerebro dormido.",
            "🌀 La técnica Pomodoro: 25 min de enfoque, 5 de descanso. Hamlet Hamster lo aprueba.",
            "🎵 Estudiar tiene su ritmo. Encuentra el tuyo y el tiempo vuela solo.",
            "🔑 ¿Sabes qué abre todas las puertas? La constancia. Y tú ya la tienes.",
            "🌈 Cada actividad que cierras es una ficha más en tu tablero. ¡Mueve ficha!",
            "🦗 Hamlet Hamster estuvo leyendo: 3 repasos espaciados fijan más que 1 hora seguida.",
            "🎯 Foco + pausa + foco: la receta secreta de Hamlet Hamster para el día de hoy.",
            "📵 Modo avión 20 min y el teléfono deja de robar tu atención. Pruébalo.",
            "💧 Hidratado y con dos respiraciones profundas antes de empezar. Hamlet Hamster lo jura.",
            "🏃 5 min de movimiento antes de estudiar activan el cerebro mejor que el café.",
            "🎯 Solo el primer paso importa ahora: ábrete a la primera tarea y el resto llega solo.",
            "🔕 Notificaciones en silencio, puerta cerrada, un solo objetivo. Así se entra en zona.",
            "🌿 Si tu mente divaga, no te regañes: nota el pensamiento, suéltalo y vuelve al texto.",
            "⏱️ Bloques cortos de 10-15 min son igual de válidos que una hora seguida. Tú eliges.",
            "🧩 Divide la tarea en partes mini y solo mira la primera pieza. El resto aparece solo.",
            "🎧 Música sin letra o lluvia de fondo: pequeño truco para bloquear distracciones.",
            "🛋️ Body doubling: estudia con alguien cerca (video incluido) y el foco llega más fácil."
        ]
        return general.randomElement()!
    }
}

struct LocalFallbackGenerator {
    func defaultSupportMaterial(for topic: String) -> [String] {
        [
            "Resumen guiado sobre \(topic).",
            "Lista de conceptos clave para estudiar \(topic).",
            "Ejercicios de práctica progresiva para \(topic)."
        ]
    }

    func defaultQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) -> [TriviaQuestion] {
        let base = questionBank(difficulty: difficulty)
        let cycle = categories.isEmpty ? TriviaCategory.allCases : categories
        let available: [TriviaQuestion] = cycle.flatMap { base[$0] ?? [] }.shuffled()
        guard !available.isEmpty else { return [] }

        let targetCount = min(count, available.count)
        return Array(available.prefix(targetCount))
    }

    private func questionBank(difficulty _: Int) -> [TriviaCategory: [TriviaQuestion]] {
        return [
            .math: [
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es (5 * 6) + 8 - 2?",
                    options: ["26", "36", "30", "20"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Resultado de 2 + 2 * 3?",
                    options: ["12", "8", "6", "10"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es el resultado de 18 ÷ 3 + 2 * 4?",
                    options: ["14", "20", "10", "24"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto da 7 + 3 * (2 + 1)?",
                    options: ["30", "16", "28", "12"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es el resultado de 9 * 9?",
                    options: ["72", "99", "81", "90"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 144 ÷ 12?",
                    options: ["10", "11", "12", "14"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Qué valor tiene x en 2x = 18?",
                    options: ["6", "9", "8", "7"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es la raíz cuadrada de 64?",
                    options: ["6", "7", "8", "9"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 15% de 200?",
                    options: ["20", "30", "35", "40"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Qué número sigue en la secuencia 2, 4, 8, 16, ...?",
                    options: ["18", "20", "24", "32"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 3³?",
                    options: ["6", "9", "27", "81"],
                    correctOptionIndex: 2
                )
            ],
            .history: [
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año llegó Cristóbal Colón a América?",
                    options: ["1492", "1502", "1450", "1521"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Quién fue el primer presidente de Estados Unidos?",
                    options: ["Abraham Lincoln", "George Washington", "Thomas Jefferson", "John Adams"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué país se construyó originalmente el Muro de Berlín?",
                    options: ["Alemania Oriental", "Alemania Occidental", "Polonia", "Austria"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año comenzó la Primera Guerra Mundial?",
                    options: ["1914", "1918", "1939", "1905"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué civilización construyó Machu Picchu?",
                    options: ["Maya", "Azteca", "Inca", "Romana"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Quién lideró la independencia de la India con la no violencia?",
                    options: ["Nehru", "Gandhi", "Mandela", "Churchill"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué imperio fue gobernado por Julio César?",
                    options: ["Romano", "Bizantino", "Otomano", "Persa"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año cayó el Muro de Berlín?",
                    options: ["1985", "1989", "1991", "1995"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué país tuvo la Revolución de 1789?",
                    options: ["Italia", "España", "Francia", "Alemania"],
                    correctOptionIndex: 2
                )
            ],
            .science: [
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es el símbolo químico del cobre?",
                    options: ["Co", "Cu", "Cr", "Cp"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué planeta es conocido como el planeta rojo?",
                    options: ["Venus", "Marte", "Júpiter", "Saturno"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es el órgano que bombea la sangre?",
                    options: ["Pulmón", "Hígado", "Riñón", "Corazón"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué gas respiramos principalmente del aire?",
                    options: ["Oxígeno", "Nitrógeno", "CO2", "Helio"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cómo se llama el proceso por el cual las plantas producen su alimento?",
                    options: ["Fermentación", "Respiración", "Fotosíntesis", "Transpiración"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuántos huesos tiene un adulto aproximadamente?",
                    options: ["206", "180", "230", "250"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué unidad mide la fuerza en el SI?",
                    options: ["Pascal", "Joule", "Newton", "Watt"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es la estrella del sistema solar?",
                    options: ["Sirio", "La Luna", "El Sol", "Polaris"],
                    correctOptionIndex: 2
                )
            ],
            .popCulture: [
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿En qué año se estrenó Star Wars: Episode IV?",
                    options: ["1972", "1977", "1980", "1983"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué saga incluye al personaje Harry Potter?",
                    options: ["Narnia", "Harry Potter", "Percy Jackson", "Dune"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Cuál de estos personajes pertenece a Marvel?",
                    options: ["Batman", "Spider-Man", "Shrek", "Sherlock Holmes"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué videojuego popular incluye bloques y construcción libre?",
                    options: ["FIFA", "Minecraft", "Pac-Man", "Tetris"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué banda lanzó el álbum 'Abbey Road'?",
                    options: ["Queen", "The Beatles", "Nirvana", "ABBA"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Cuál es el apellido de la familia en 'Los Simpson'?",
                    options: ["Smith", "Simpson", "Johnson", "Brown"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué personaje dice 'Yo soy tu padre' en Star Wars?",
                    options: ["Yoda", "Luke", "Obi-Wan", "Darth Vader"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué superhéroe usa el alias de Bruce Wayne?",
                    options: ["Superman", "Batman", "Flash", "Aquaman"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿En qué saga aparece el anillo único?",
                    options: ["Star Trek", "Harry Potter", "El Señor de los Anillos", "Matrix"],
                    correctOptionIndex: 2
                )
            ]
        ]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
