import Foundation
#if canImport(SwiftUI)

struct HomeSummarySnapshot: Sendable, Equatable {
    let todayActivities: [Activity]
    let tomorrowActivities: [Activity]
    let streakState: StreakState
    let petMessage: String
}

struct HomePresentationModel: Sendable {
    private let agendaService: AgendaService
    private let intelligence: AIConversationService
    private let calendar: Calendar

    init(
        agendaService: AgendaService,
        intelligence: AIConversationService,
        calendar: Calendar = .current
    ) {
        self.agendaService = agendaService
        self.intelligence = intelligence
        self.calendar = calendar
    }

    func refreshSummary(now: Date = Date()) async -> HomeSummarySnapshot {
        let today = now
        let tomorrow = nextDay(from: now)
        let activities = await agendaService.listActivities(on: today, calendar: calendar)
        let tomorrowItems = await agendaService.listActivities(on: tomorrow, calendar: calendar)
        let updatedStreakDays = await StreakComputation.days(endingOn: today, agendaService: agendaService, calendar: calendar)
        let todayReason = await StreakComputation.validationReason(for: today, agendaService: agendaService, calendar: calendar)
        let generatedPetMessage = await intelligence.mascotSupportMessage(
            todayActivities: activities,
            tomorrowActivities: tomorrowItems,
            streakDays: updatedStreakDays,
            now: today,
            calendar: calendar
        )

        let streakState = StreakState(
            days: updatedStreakDays,
            lastValidatedDay: updatedStreakDays > 0 ? calendar.startOfDay(for: today) : nil,
            reason: updatedStreakDays > 0 ? todayReason : .incompleteDay
        )

        return HomeSummarySnapshot(
            todayActivities: activities,
            tomorrowActivities: tomorrowItems,
            streakState: streakState,
            petMessage: generatedPetMessage
        )
    }

    func seedInitialActivitiesIfNeeded(now: Date = Date()) async {
        let today = now
        let tomorrow = nextDay(from: now)
        let existingToday = await agendaService.listActivities(on: today, calendar: calendar)
        let existingTomorrow = await agendaService.listActivities(on: tomorrow, calendar: calendar)
        guard existingToday.isEmpty, existingTomorrow.isEmpty else { return }

        _ = await agendaService.createActivity(
            title: "Repaso de matemáticas",
            topic: "Derivadas",
            type: .study,
            scheduledAt: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        )
        _ = await agendaService.createActivity(
            title: "Entregar tarea",
            topic: "Álgebra",
            type: .task,
            scheduledAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? today
        )
        _ = await agendaService.createActivity(
            title: "Lectura corta",
            topic: "Historia",
            type: .other,
            scheduledAt: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        )
    }

    func activitiesAt(hour: Int, in activities: [Activity]) -> [Activity] {
        activities
            .filter { calendar.component(.hour, from: $0.scheduledAt) == hour }
            .sorted {
                if $0.scheduledAt != $1.scheduledAt {
                    return $0.scheduledAt < $1.scheduledAt
                }
                if Self.statusSortOrder($0.status) != Self.statusSortOrder($1.status) {
                    return Self.statusSortOrder($0.status) < Self.statusSortOrder($1.status)
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func nextDay(from now: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: 1, to: now) ?? now
    }

    static func statusSortOrder(_ status: ActivityStatus) -> Int {
        switch status {
        case .inProgress:
            return 0
        case .pending:
            return 1
        case .notStarted:
            return 2
        case .failed:
            return 3
        case .completed:
            return 4
        }
    }

    static func displayedPetSupportMessage(
        generatedMessage: String?,
        streakState: StreakState,
        todayActivities: [Activity]
    ) -> String {
        let generated = generatedMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !generated.isEmpty {
            return generated
        }
        return petSupportFallbackMessage(streakState: streakState, todayActivities: todayActivities)
    }

    static func petSupportFallbackMessage(streakState: StreakState, todayActivities: [Activity]) -> String {
        if streakState.days >= 7 {
            return "Llevas \(streakState.days) días seguidos. Eso es constancia real. 🔥"
        }
        if todayActivities.isEmpty {
            return "Sin actividades hoy. Una pequeña tarea marca la diferencia."
        }
        return "Un bloque a la vez. Cada paso suma 🐭"
    }
}
#endif
