import Testing
@testable import AI___AT___Swift_PRELIMINAR_
import Foundation
#if canImport(SwiftUI)

@Test("HomePresentationModel siembra actividades iniciales cuando la agenda está vacía")
func homePresentationModelSeedsInitialActivitiesWhenEmpty() async throws {
    let agenda = AgendaService(intelligence: MockConversationIntelligence())
    let intelligence = AIConversationService(openSourceKnowledge: MockHomeOpenSourceKnowledge(answer: "Mensaje de mascota"))
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_710_172_800)
    let model = HomePresentationModel(agendaService: agenda, intelligence: intelligence, calendar: calendar)

    await model.seedInitialActivitiesIfNeeded(now: now)

    let today = await agenda.listActivities(on: now, calendar: calendar)
    let tomorrow = await agenda.listActivities(on: calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar)
    #expect(today.count == 2)
    #expect(tomorrow.count == 1)
}

@Test("HomePresentationModel ordena actividades por hora, estado y título")
func homePresentationModelOrdersActivitiesForAgendaCell() async throws {
    let agenda = AgendaService(intelligence: MockConversationIntelligence())
    let intelligence = AIConversationService(openSourceKnowledge: MockHomeOpenSourceKnowledge(answer: "ok"))
    let calendar = Calendar(identifier: .gregorian)
    let day = Date(timeIntervalSince1970: 1_710_172_800)
    let nineTen = calendar.date(bySettingHour: 9, minute: 10, second: 0, of: day) ?? day
    let nineThirty = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? day

    let pendingA = Activity(title: "Álgebra", topic: "Tema", type: .study, status: .pending, scheduledAt: nineThirty)
    let inProgress = Activity(title: "Biología", topic: "Tema", type: .study, status: .inProgress, scheduledAt: nineThirty)
    let pendingB = Activity(title: "Cálculo", topic: "Tema", type: .study, status: .pending, scheduledAt: nineThirty)
    let earlier = Activity(title: "Historia", topic: "Tema", type: .study, status: .completed, scheduledAt: nineTen)

    let model = HomePresentationModel(agendaService: agenda, intelligence: intelligence, calendar: calendar)
    let ordered = model.activitiesAt(hour: 9, in: [pendingB, inProgress, earlier, pendingA])

    #expect(ordered.map(\.title) == ["Historia", "Biología", "Álgebra", "Cálculo"])
}

@Test("HomePresentationModel usa fallback cuando no hay mensaje generado")
func homePresentationModelUsesFallbackPetMessage() async throws {
    let withStreak = HomePresentationModel.displayedPetSupportMessage(
        generatedMessage: "   ",
        streakState: StreakState(days: 8, lastValidatedDay: Date(), reason: .allScheduledActivitiesCompleted),
        todayActivities: []
    )
    let noActivities = HomePresentationModel.displayedPetSupportMessage(
        generatedMessage: nil,
        streakState: StreakState(days: 0, lastValidatedDay: nil, reason: .incompleteDay),
        todayActivities: []
    )
    let withGenerated = HomePresentationModel.displayedPetSupportMessage(
        generatedMessage: "  Mensaje directo  ",
        streakState: StreakState(),
        todayActivities: []
    )

    #expect(withStreak.contains("8 días"))
    #expect(noActivities.contains("Sin actividades hoy"))
    #expect(withGenerated == "Mensaje directo")
}

private struct MockConversationIntelligence: AIConversationProviding {
    func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] { [] }

    func chatReply(
        userMessage: String,
        history: [ConversationTurn],
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        "ok"
    }

    func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        []
    }
}

private struct MockHomeOpenSourceKnowledge: OpenSourceKnowledgeProviding {
    let answer: String?

    func answer(for query: String) async -> String? { answer }
    func answer(for query: String, history: [ConversationTurn]) async -> String? { answer }
}
#endif
