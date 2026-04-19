import Testing
@testable import AI___AT___Swift_PRELIMINAR_
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Test("Streak sube cuando todas las actividades del día están completas")
func streakIncrementsWhenAllActivitiesComplete() async throws {
    let engine = StreakEngine(calendar: Calendar(identifier: .gregorian))
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let previous = StreakState(days: 2, lastValidatedDay: day.addingTimeInterval(-86_400), reason: .allScheduledActivitiesCompleted)
    let activities = [
        Activity(title: "Cálculo", topic: "Derivadas", type: .study, status: .completed, scheduledAt: day),
        Activity(title: "Tarea 1", topic: "Álgebra", type: .task, status: .completed, scheduledAt: day)
    ]

    let updated = engine.evaluate(
        current: previous,
        input: DailyEvaluationInput(day: day, scheduledActivities: activities, validMentalTrainingCompletions: 0)
    )

    #expect(updated.days == 3)
    #expect(updated.reason == .allScheduledActivitiesCompleted)
}

@Test("Streak sube en día sin agenda con una sesión válida de trainer")
func streakUsesMentalTrainerOnNoAgendaDay() async throws {
    let engine = StreakEngine()
    let day = Date(timeIntervalSince1970: 1_710_086_400)
    let previous = StreakState(days: 4, lastValidatedDay: day.addingTimeInterval(-86_400), reason: .allScheduledActivitiesCompleted)

    let updated = engine.evaluate(
        current: previous,
        input: DailyEvaluationInput(day: day, scheduledActivities: [], validMentalTrainingCompletions: 1)
    )

    #expect(updated.days == 5)
    #expect(updated.reason == .mentalTrainingOnNoAgendaDay)
}

@Test("Streak no sube en día sin agenda sin sesión válida de trainer")
func streakDoesNotUseMentalTrainerWhenCompletionsAreUnderThreshold() async throws {
    let engine = StreakEngine()
    let day = Date(timeIntervalSince1970: 1_710_086_400)
    let previous = StreakState(days: 4, lastValidatedDay: day.addingTimeInterval(-86_400), reason: .allScheduledActivitiesCompleted)

    let updated = engine.evaluate(
        current: previous,
        input: DailyEvaluationInput(day: day, scheduledActivities: [], validMentalTrainingCompletions: 0)
    )

    #expect(updated.days == 4)
    #expect(updated.reason == .incompleteDay)
}

@Test("Streak no se duplica al evaluar el mismo día más de una vez")
func streakDoesNotIncrementTwiceOnSameDay() async throws {
    let engine = StreakEngine(calendar: Calendar(identifier: .gregorian))
    let day = Date(timeIntervalSince1970: 1_710_172_800)
    let current = StreakState(days: 3, lastValidatedDay: day, reason: .allScheduledActivitiesCompleted)
    let activities = [
        Activity(title: "Repaso", topic: "Álgebra", type: .study, status: .completed, scheduledAt: day)
    ]

    let updated = engine.evaluate(
        current: current,
        input: DailyEvaluationInput(day: day, scheduledActivities: activities, validMentalTrainingCompletions: 0)
    )

    #expect(updated.days == 3)
    #expect(updated.reason == .allScheduledActivitiesCompleted)
}

@Test("Streak permite continuidad combinando día con agenda y día de trainer válido")
func streakSupportsMixedValidDays() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let engine = StreakEngine(calendar: calendar)
    let dayOne = Date(timeIntervalSince1970: 1_710_086_400)
    let dayTwo = dayOne.addingTimeInterval(86_400)

    let dayOneState = engine.evaluate(
        current: StreakState(),
        input: DailyEvaluationInput(
            day: dayOne,
            scheduledActivities: [
                Activity(title: "Tarea", topic: "Tema", type: .task, status: .completed, scheduledAt: dayOne)
            ],
            validMentalTrainingCompletions: 0
        )
    )
    let dayTwoState = engine.evaluate(
        current: dayOneState,
        input: DailyEvaluationInput(
            day: dayTwo,
            scheduledActivities: [],
            validMentalTrainingCompletions: 1
        )
    )

    #expect(dayOneState.days == 1)
    #expect(dayTwoState.days == 2)
    #expect(dayTwoState.reason == .mentalTrainingOnNoAgendaDay)
}

@Test("Inicio de tarea devuelve apoyo y sesión pomodoro")
func agendaStartTaskReturnsSupportMaterial() async throws {
    let agenda = AgendaService(intelligence: MockIntelligence())
    let day = Date(timeIntervalSince1970: 1_710_172_800)
    let activity = await agenda.createActivity(title: "Repaso", topic: "Cálculo lineal", type: .study, scheduledAt: day)

    let session = try await agenda.startActivity(id: activity.id, now: day)

    #expect(session != nil)
    #expect(session?.pomodoroLengthMinutes == 25)
    #expect((session?.supportMaterial.count ?? 0) > 0)
}

@Test("Actividad puede volver a pendiente desde flujo pomodoro")
func agendaCanMarkPendingAfterCompletion() async throws {
    let agenda = AgendaService(intelligence: MockIntelligence())
    let day = Date().addingTimeInterval(3_600)
    let activity = await agenda.createActivity(title: "Repaso", topic: "Álgebra", type: .task, scheduledAt: day)

    _ = await agenda.completeActivity(id: activity.id)
    let markedPending = await agenda.markActivityPending(id: activity.id)
    let updated = await agenda.listActivities(on: day).first(where: { $0.id == activity.id })

    #expect(markedPending == true)
    #expect(updated?.status == .pending)
}

@Test("Persistencia local de agenda guarda y recarga actividades")
func localAgendaDatabasePersistsData() async throws {
    let tempFile = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("agenda-test.json")
    let database = LocalAgendaDatabase(fileURL: tempFile)

    let day = Date(timeIntervalSince1970: 1_710_172_800)
    let activity = Activity(title: "Persistir", topic: "Tema", type: .task, status: .completed, scheduledAt: day)
    let session = ActivitySession(activityID: activity.id, startedAt: day, endedAt: day.addingTimeInterval(60))
    let snapshot = AgendaStorageSnapshot(activities: [activity], sessions: [session])

    try database.save(snapshot)
    let loaded = try database.load()

    #expect(loaded == snapshot)
}

@Test("AgendaService usa snapshot local al inicializar")
func agendaServiceLoadsFromPersistenceSnapshot() async throws {
    let tempFile = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("agenda-load-test.json")
    let database = LocalAgendaDatabase(fileURL: tempFile)
    let day = Date(timeIntervalSince1970: 1_710_172_800)
    let persistedActivity = Activity(
        title: "Desde DB",
        topic: "Persistencia",
        type: .study,
        status: .pending,
        scheduledAt: day
    )
    try database.save(AgendaStorageSnapshot(activities: [persistedActivity], sessions: []))

    let service = AgendaService(
        intelligence: MockIntelligence(),
        activities: [],
        sessions: [],
        persistence: database
    )
    let loaded = await service.listActivities(on: day)

    #expect(loaded.contains(where: { $0.id == persistedActivity.id }))
}

@Test("Actividad vencida sin iniciar pasa a fallida")
func overdueNotStartedActivityBecomesFailed() async throws {
    let agenda = AgendaService(intelligence: MockIntelligence())
    let oldDate = Date().addingTimeInterval(-7_200)
    let activity = await agenda.createActivity(
        title: "Pendiente vieja",
        topic: "Repaso",
        type: .study,
        scheduledAt: oldDate
    )

    let listed = await agenda.listActivities(on: oldDate)
    let updated = listed.first(where: { $0.id == activity.id })

    #expect(updated?.status == .failed)
}

@Test("Trivia termina al primer fallo")
func triviaGameOverAtFirstFail() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_710_259_200)
    let service = MentalTrainerService(
        intelligence: MockIntelligence(questionCount: 10),
        dateProvider: FixedDateProvider(now: baseDate)
    )

    _ = try await service.startSession(questionCount: 10)
    let failFeedback = try await service.submitAnswer(optionIndex: 1, answeredAt: baseDate.addingTimeInterval(1))
    #expect(failFeedback?.isCorrect == false)
    #expect(failFeedback?.isGameOver == true)
    #expect(failFeedback?.isWin == false)
}

@Test("Trivia continúa después de 8 aciertos y no repite preguntas")
func triviaContinuesAfterEightAndAvoidsRepeats() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_710_259_200)
    let service = MentalTrainerService(
        intelligence: MockIntelligence(questionCount: 20),
        dateProvider: FixedDateProvider(now: baseDate)
    )

    _ = try await service.startSession(questionCount: 20)
    var prompts = Set<String>()
    if let first = await service.currentQuestion() {
        prompts.insert(first.prompt)
    }
    var finalFeedback: TriviaFeedback?
    for second in 0..<12 {
        finalFeedback = try await service.submitAnswer(optionIndex: 0, answeredAt: baseDate.addingTimeInterval(Double(second)))
        if let next = await service.currentQuestion() {
            prompts.insert(next.prompt)
        }
    }
    let session = await service.activeSession

    #expect(finalFeedback?.isCorrect == true)
    #expect(finalFeedback?.isGameOver == false)
    #expect(await service.activeSession != nil)
    #expect(session?.attempt.correctAnswers == 12)
    #expect(prompts.count == 13)
}

@Test("Trivia usa timeout de 15 segundos por pregunta")
func triviaUsesFifteenSecondTimeout() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_710_259_200)
    let service = MentalTrainerService(
        intelligence: MockIntelligence(questionCount: 10),
        dateProvider: FixedDateProvider(now: baseDate)
    )

    let session = try await service.startSession(questionCount: 10)
    let validFeedback = try await service.submitAnswer(optionIndex: 0, answeredAt: session.deadline.addingTimeInterval(-1))

    #expect(validFeedback?.isCorrect == true)
}

@Test("Notificación cambia según haya actividades o no")
func notificationPlannerMessages() async throws {
    let planner = NotificationPlanner()
    let withoutActivities = planner.reminderForDay(activities: [])
    let withActivities = planner.reminderForDay(activities: [
        Activity(title: "Tarea", topic: "Tema", type: .task, scheduledAt: .now)
    ])

    #expect(withoutActivities.body.contains("entrenador mental"))
    #expect(withActivities.body.contains("entrenamiento rápido"))
    #expect(planner.pomodoroFinishReminder(activityTitle: "Repaso").title.contains("Pomodoro"))
    #expect(planner.mentalTrainingMotivation(streakDays: 3).body.contains("racha"))
    #expect(planner.mentalTrainingMotivation(streakDays: 0).title.contains("enfoque"))
}

@Test("Servicio de notificaciones agenda recordatorio, motivación y temporizador")
func engagementNotificationServiceSchedulesNotifications() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_710_345_600)
    let scheduler = InMemoryNotificationScheduler()
    let service = EngagementNotificationService(
        scheduler: scheduler,
        planner: NotificationPlanner(),
        dateProvider: FixedDateProvider(now: baseDate),
        calendar: Calendar(identifier: .gregorian)
    )

    _ = await service.scheduleDailyReminder(for: [], on: baseDate)
    _ = await service.scheduleMentalTrainingMotivation(on: baseDate, streakDays: 2)
    _ = await service.schedulePomodoroTimerNotification(
        activityTitle: "Repaso de cálculo",
        remainingSeconds: 25 * 60,
        now: baseDate
    )

    let scheduled = await scheduler.scheduledNotifications()

    #expect(scheduled.count == 3)
    #expect(scheduled.contains(where: { $0.id.contains("daily-reminder") }))
    #expect(scheduled.contains(where: { $0.id.contains("mental-motivation") }))
    #expect(scheduled.contains(where: { $0.id.contains("pomodoro") }))
    #expect(scheduled.contains(where: { $0.message.title.contains("Pomodoro") }))
    #expect(scheduled.contains(where: { $0.message.body.contains("racha") }))
}

@Test("Parser local extrae material con fuentes desde JSON")
func localAgentParserReadsSupportMaterialWithSources() async throws {
    let response = """
    ```json
    {
      "material": [
        { "point": "Revisa conceptos base de derivadas", "source": "https://es.khanacademy.org/math" },
        { "point": "Practica 10 ejercicios guiados", "source": "https://www.geogebra.org/" },
        { "point": "Resume errores frecuentes en una hoja", "source": "https://openstax.org/" }
      ]
    }
    ```
    """

    let parsed = LocalAgentResponseParser.parseSupportMaterial(from: response, limit: 3)

    #expect(parsed.count == 3)
    #expect(parsed[0].contains("Fuente:"))
    #expect(parsed[1].contains("geogebra"))
}

@Test("Parser local extrae preguntas válidas desde JSON")
func localAgentParserReadsTriviaQuestionsFromJSON() async throws {
    let response = """
    {
      "questions": [
        {
          "category": "science",
          "prompt": "¿Qué planeta es conocido como el planeta rojo?",
          "options": ["Venus", "Marte", "Júpiter", "Mercurio"],
          "correctOptionIndex": 1,
          "imageURL": null
        },
        {
          "category": "pop_culture",
          "prompt": "¿Qué saga incluye al personaje Frodo?",
          "options": ["Star Trek", "Harry Potter", "El Señor de los Anillos", "Matrix"],
          "correctOptionIndex": 2,
          "imageURL": "https://example.com/frodo.png"
        }
      ]
    }
    """

    let parsed = LocalAgentResponseParser.parseTriviaQuestions(
        from: response,
        categories: TriviaCategory.allCases,
        limit: 2
    )

    #expect(parsed.count == 2)
    #expect(parsed[0].category == .science)
    #expect(parsed[1].category == .popCulture)
    #expect(parsed[1].imageURL != nil)
}

@Test("Parser local tolera ruido y aplica hardening en trivia")
func localAgentParserHardensTriviaPayload() async throws {
    let response = """
    Aquí tienes el resultado:
    ```json
    {
      "questions": [
        {
          "category": "science",
          "prompt": "¿Cuál es el planeta más grande del sistema solar?",
          "options": ["Mercurio", "Venus", "Tierra", "Júpiter"],
          "correctOptionIndex": 3,
          "imageURL": "https://example.com/jupiter.png"
        },
        {
          "category": "history",
          "prompt": "¿Año de independencia de México?",
          "options": ["1810", "1821", "1910"],
          "correctOptionIndex": 1,
          "imageURL": "https://example.com/mx.png"
        },
        {
          "category": "popCulture",
          "prompt": "¿Qué consola lanzó Nintendo en 2006?",
          "options": ["Wii", "SNES", "N64", "GameCube"],
          "correctOptionIndex": 0,
          "imageURL": "javascript:alert(1)"
        }
      ]
    }
    ```
    """

    let parsed = LocalAgentResponseParser.parseTriviaQuestions(
        from: response,
        categories: TriviaCategory.allCases,
        limit: 3
    )

    #expect(parsed.count == 2)
    #expect(parsed[0].category == .science)
    #expect(parsed[0].imageURL != nil)
    #expect(parsed[1].category == .popCulture)
    #expect(parsed[1].imageURL == nil)
}

@Test("AIConversationService usa API abierta para responder chat")
func aiConversationServiceUsesOpenSourceKnowledgeAnswer() async throws {
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: "Respuesta abierta"))

    let answer = try await service.chatReply(
        userMessage: "¿Qué es la fotosíntesis?",
        activityTitle: "Biología",
        topic: "Plantas",
        type: .study
    )

    #expect(answer == "Respuesta abierta")
}

@Test("AIConversationService responde fallback cuando API abierta no devuelve contenido")
func aiConversationServiceFallsBackWhenOpenSourceFails() async throws {
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: nil))

    let answer = try await service.chatReply(
        userMessage: "Necesito ayuda",
        activityTitle: "Repaso",
        topic: "Historia",
        type: .other
    )

    #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test("AIConversationService bloquea solicitudes de resolución directa y entrega fuentes")
func aiConversationServiceBlocksDirectSolveRequestsWithSources() async throws {
    let service = AIConversationService(
        openSourceKnowledge: MockOpenSourceKnowledge(
            answerProvider: { query in
                if query.contains("No resuelvas el trabajo") {
                    return "Fuente directa: https://es.khanacademy.org/math/algebra"
                }
                return nil
            }
        )
    )

    let answer = try await service.chatReply(
        userMessage: "Resuélveme este ejercicio de álgebra",
        activityTitle: "Álgebra",
        topic: "Ecuaciones lineales",
        type: .task
    )

    #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(answer.contains("https://es.khanacademy.org/math/algebra"))
}

@Test("AIConversationService devuelve saludo amigable si no hay fuentes en inicio")
func aiConversationServiceReturnsFriendlyGreetingWhenNoStartSources() async throws {
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: nil))

    let material = try await service.supportMaterial(for: "Repaso de química", type: .study)

    #expect(material.count == 1)
    #expect(material[0].contains("Roedor"))
}

@Test("AIConversationService por defecto prioriza agente externo open source")
func aiConversationServiceDefaultUsesOpenSourceProvider() async throws {
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: "Respuesta externa"))

    let answer = try await service.chatReply(
        userMessage: "Explícame la mitocondria",
        activityTitle: "Biología celular",
        topic: "Células",
        type: .study
    )

    #expect(answer == "Respuesta externa")
}

@Test("AIConversationService limpia inicios repetitivos y texto duplicado en chat")
func aiConversationServiceCleansRepetitiveOpenings() async throws {
    let noisyAnswer = """
    Claro, te ayudo con eso.

    Claro, te ayudo con eso.

    Aquí tienes pasos concretos para avanzar.
    """
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: noisyAnswer))

    let answer = try await service.chatReply(
        userMessage: "Ayúdame a organizar esta actividad",
        activityTitle: "Plan semanal",
        topic: "Organización",
        type: .other
    )

    #expect(!answer.lowercased().hasPrefix("claro"))
    #expect(answer.contains("Aquí tienes pasos concretos para avanzar."))
    #expect(!answer.lowercased().contains("claro, te ayudo con eso"))
}

@Test("AIConversationService trivia usa payload JSON del proveedor externo")
func aiConversationServiceTriviaUsesGeneratedPayload() async throws {
    let triviaJSON = """
    {
      "questions": [
        {
          "category": "math",
          "prompt": "¿Cuánto es 3 + 5 * 2?",
          "options": ["16", "13", "10", "8"],
          "correctOptionIndex": 1,
          "imageURL": null
        },
        {
          "category": "history",
          "prompt": "¿Qué civilización construyó Machu Picchu?",
          "options": ["Maya", "Inca", "Azteca", "Romana"],
          "correctOptionIndex": 1,
          "imageURL": null
        }
      ]
    }
    """
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: triviaJSON))

    let questions = try await service.triviaQuestions(
        count: 2,
        categories: [.math, .history],
        difficulty: 2
    )

    #expect(questions.count == 2)
    #expect(questions.allSatisfy { $0.options.count == 4 })
}

@Test("AIConversationService fallback de trivia soporta un banco más grande")
func aiConversationServiceFallbackTriviaSupportsLargerBank() async throws {
    let service = AIConversationService(openSourceKnowledge: MockOpenSourceKnowledge(answer: nil))

    let questions = try await service.triviaQuestions(
        count: 20,
        categories: TriviaCategory.allCases,
        difficulty: 2
    )

    #expect(questions.count == 20)
    #expect(Set(questions.map(\.prompt)).count == questions.count)
}

@Suite(.serialized)
struct OpenSourceKnowledgeServiceNetworkTests {
    @Test("OpenSourceKnowledgeService soporta preguntas en frase completa y extrae keywords")
    func openSourceKnowledgeServiceHandlesNaturalLanguageQuestions() async throws {
        let session = makeMockedSession()

        MockURLProtocol.setRequestHandler { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = components?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""

            let payload: [String: Any]
            if query.lowercased() == "albert einstein" {
                payload = [
                    "AbstractText": "Albert Einstein fue un físico teórico alemán.",
                    "AbstractURL": "https://es.wikipedia.org/wiki/Albert_Einstein",
                    "RelatedTopics": []
                ]
            } else {
                payload = [
                    "AbstractText": "",
                    "AbstractURL": "",
                    "RelatedTopics": []
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (200, data)
        }
        defer { MockURLProtocol.setRequestHandler(nil) }

        let service = OpenSourceKnowledgeService(session: session, groqAPIKey: nil)
        let answer = await service.answer(for: "¿quien fue albert einstein?")

        #expect(answer?.contains("Einstein") == true)
    }

    @Test("OpenSourceKnowledgeService usa Groq y responde en español cuando hay API key")
    func openSourceKnowledgeServiceUsesGroqWhenConfigured() async throws {
        let session = makeMockedSession()
        var sawGroqRequest = false
        let stateQueue = DispatchQueue(label: "test.groq.request.state")
        MockURLProtocol.setRequestHandler { request in
            let url = try #require(request.url)
            if url.absoluteString.contains("api.groq.com/openai/v1/chat/completions") {
                stateQueue.sync {
                    sawGroqRequest = true
                }
                let payload: [String: Any] = [
                    "choices": [
                        [
                            "message": [
                                "role": "assistant",
                                "content": "Albert Einstein fue un científico destacado del siglo XX."
                            ]
                        ]
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: payload)
                return (200, data)
            }

            let fallbackPayload: [String: Any] = [
                "AbstractText": "Albert Einstein fue un científico destacado del siglo XX.",
                "AbstractURL": "https://es.wikipedia.org/wiki/Albert_Einstein",
                "RelatedTopics": []
            ]
            let fallbackData = try JSONSerialization.data(withJSONObject: fallbackPayload)
            return (200, fallbackData)
        }
        defer { MockURLProtocol.setRequestHandler(nil) }

        let service = OpenSourceKnowledgeService(session: session, groqAPIKey: "test-key")
        let answer = await service.answer(for: "quien fue albert einstein?")
        let didSeeGroqRequest = stateQueue.sync { sawGroqRequest }

        #expect(didSeeGroqRequest)
        #expect(answer?.contains("fue un científico") == true)
    }

    @Test("OpenSourceKnowledgeService agrega hipervínculos cuando Groq no los devuelve")
    func openSourceKnowledgeServiceAddsHyperlinksToGroqReplyWhenMissing() async throws {
        let session = makeMockedSession()

        MockURLProtocol.setRequestHandler { request in
            let url = try #require(request.url)
            if url.absoluteString.contains("api.groq.com/openai/v1/chat/completions") {
                let payload: [String: Any] = [
                    "choices": [
                        [
                            "message": [
                                "role": "assistant",
                                "content": "Albert Einstein fue un físico teórico."
                            ]
                        ]
                    ]
                ]
                return (200, try JSONSerialization.data(withJSONObject: payload))
            }

            if url.absoluteString.contains("api.duckduckgo.com") {
                let payload: [String: Any] = [
                    "AbstractText": "Resumen breve sobre Albert Einstein.",
                    "AbstractURL": "https://es.wikipedia.org/wiki/Albert_Einstein",
                    "RelatedTopics": []
                ]
                return (200, try JSONSerialization.data(withJSONObject: payload))
            }

            if url.absoluteString.contains("es.wikipedia.org/w/api.php") {
                let payload: [Any] = [
                    "albert einstein",
                    ["Albert Einstein"],
                    ["Científico teórico del siglo XX."],
                    ["https://es.wikipedia.org/wiki/Albert_Einstein"]
                ]
                return (200, try JSONSerialization.data(withJSONObject: payload))
            }

            throw URLError(.badURL)
        }
        defer { MockURLProtocol.setRequestHandler(nil) }

        let service = OpenSourceKnowledgeService(session: session, groqAPIKey: "test-key")
        let answer = await service.answer(for: "quien fue albert einstein?")

        #expect(answer?.contains("Fuentes web:") == true)
        #expect(answer?.contains("[Fuente web](https://es.wikipedia.org/wiki/Albert_Einstein)") == true)
    }
}

private struct MockIntelligence: AIConversationProviding {
    let questionCount: Int

    init(questionCount: Int = 4) {
        self.questionCount = questionCount
    }

    func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        ["Guía rápida de \(topic)", "Ejercicios sobre \(topic)"]
    }

    func chatReply(
        userMessage: String,
        history: [ConversationTurn],
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        "Respuesta de apoyo para \(activityTitle): \(userMessage)"
    }

    func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        let total = max(count, questionCount)
        return (0..<total).map { index in
            TriviaQuestion(
                category: categories[index % max(categories.count, 1)],
                prompt: "Pregunta \(index)",
                options: ["A", "B", "C", "D"],
                correctOptionIndex: 0
            )
        }
    }
}

private struct MockOpenSourceKnowledge: OpenSourceKnowledgeProviding {
    let answerProvider: @Sendable (String) -> String?

    init(answer: String?) {
        self.answerProvider = { _ in answer }
    }

    init(answerProvider: @escaping @Sendable (String) -> String?) {
        self.answerProvider = answerProvider
    }

    func answer(for query: String) async -> String? {
        guard !query.isEmpty else { return nil }
        return answerProvider(query)
    }

    func answer(for query: String, history: [ConversationTurn]) async -> String? {
        guard !query.isEmpty else { return nil }
        return answerProvider(query)
    }
}

private struct FixedDateProvider: DateProviding {
    let now: Date
}

private func makeMockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestHandler: ((URLRequest) throws -> (Int, Data))?
    private static let requestHandlerQueue = DispatchQueue(label: "tests.mock-url-protocol.handler")

    static func setRequestHandler(_ handler: ((URLRequest) throws -> (Int, Data))?) {
        requestHandlerQueue.sync {
            requestHandler = handler
        }
    }

    private static func currentRequestHandler() -> ((URLRequest) throws -> (Int, Data))? {
        requestHandlerQueue.sync { requestHandler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.currentRequestHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
