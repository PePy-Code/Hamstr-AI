import Testing
@testable import AI___AT___Swift_PRELIMINAR_
import Foundation

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

@Test("Streak sube en día sin agenda solo con 5 respuestas correctas")
func streakUsesMentalTrainerOnNoAgendaDay() async throws {
    let engine = StreakEngine()
    let day = Date(timeIntervalSince1970: 1_710_086_400)
    let previous = StreakState(days: 4, lastValidatedDay: day.addingTimeInterval(-86_400), reason: .allScheduledActivitiesCompleted)

    let updated = engine.evaluate(
        current: previous,
        input: DailyEvaluationInput(day: day, scheduledActivities: [], validMentalTrainingCompletions: 5)
    )

    #expect(updated.days == 5)
    #expect(updated.reason == .mentalTrainingOnNoAgendaDay)
}

@Test("Streak no sube en día sin agenda con menos de 5 respuestas correctas")
func streakDoesNotUseMentalTrainerWhenCompletionsAreUnderThreshold() async throws {
    let engine = StreakEngine()
    let day = Date(timeIntervalSince1970: 1_710_086_400)
    let previous = StreakState(days: 4, lastValidatedDay: day.addingTimeInterval(-86_400), reason: .allScheduledActivitiesCompleted)

    let updated = engine.evaluate(
        current: previous,
        input: DailyEvaluationInput(day: day, scheduledActivities: [], validMentalTrainingCompletions: 4)
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
            validMentalTrainingCompletions: 5
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

@Test("Trivia muestra game over al primer fallo después de 5 aciertos")
func triviaGameOverAfterFiveCorrectAndOneFail() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_710_259_200)
    let service = MentalTrainerService(
        intelligence: MockIntelligence(questionCount: 10),
        dateProvider: FixedDateProvider(now: baseDate)
    )

    _ = try await service.startSession(questionCount: 10)
    for second in 0..<5 {
        let feedback = await service.submitAnswer(optionIndex: 0, answeredAt: baseDate.addingTimeInterval(Double(second)))
        #expect(feedback?.isCorrect == true)
        #expect(feedback?.isGameOver == false)
    }

    let failFeedback = await service.submitAnswer(optionIndex: 1, answeredAt: baseDate.addingTimeInterval(6))
    #expect(failFeedback?.isCorrect == false)
    #expect(failFeedback?.isGameOver == true)
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

@Test("AppleIntelligenceService usa API abierta cuando no hay agente local")
func appleIntelligenceServiceUsesOpenSourceKnowledgeAnswer() async throws {
    let service = AppleIntelligenceService(
        localAgent: nil,
        openSourceKnowledge: MockOpenSourceKnowledge(answer: "Respuesta abierta")
    )

    let answer = try await service.chatReply(
        userMessage: "¿Qué es la fotosíntesis?",
        activityTitle: "Biología",
        topic: "Plantas",
        type: .study
    )

    #expect(answer == "Respuesta abierta")
}

@Test("AppleIntelligenceService responde fallback cuando API abierta no devuelve contenido")
func appleIntelligenceServiceFallsBackWhenOpenSourceFails() async throws {
    let service = AppleIntelligenceService(
        localAgent: nil,
        openSourceKnowledge: MockOpenSourceKnowledge(answer: nil)
    )

    let answer = try await service.chatReply(
        userMessage: "Necesito ayuda",
        activityTitle: "Repaso",
        topic: "Historia",
        type: .other
    )

    #expect(answer.contains("Listo."))
}

private struct MockIntelligence: AppleIntelligenceProviding {
    let questionCount: Int

    init(questionCount: Int = 4) {
        self.questionCount = questionCount
    }

    func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        ["Guía rápida de \(topic)", "Ejercicios sobre \(topic)"]
    }

    func chatReply(
        userMessage: String,
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
    let answer: String?

    func answer(for query: String) async -> String? {
        guard !query.isEmpty else { return nil }
        return answer
    }
}

private struct FixedDateProvider: DateProviding {
    let now: Date
}
