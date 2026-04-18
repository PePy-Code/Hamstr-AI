import Foundation

public struct StreakEngine {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func evaluate(current: StreakState, input: DailyEvaluationInput) -> StreakState {
        let dayStart = calendar.startOfDay(for: input.day)
        let hasActivities = !input.scheduledActivities.isEmpty
        let allCompleted = hasActivities && input.scheduledActivities.allSatisfy { $0.status == .completed }
        let hasValidMentalTraining = !hasActivities && input.validMentalTrainingCompletions >= 5

        let reason: StreakValidationReason
        let incrementsStreak: Bool
        if allCompleted {
            reason = .allScheduledActivitiesCompleted
            incrementsStreak = true
        } else if hasValidMentalTraining {
            reason = .mentalTrainingOnNoAgendaDay
            incrementsStreak = true
        } else {
            reason = .incompleteDay
            incrementsStreak = false
        }

        guard incrementsStreak else {
            return StreakState(days: current.days, lastValidatedDay: current.lastValidatedDay, reason: reason)
        }

        if let last = current.lastValidatedDay, calendar.isDate(last, inSameDayAs: dayStart) {
            if current.reason == .allScheduledActivitiesCompleted || current.reason == .mentalTrainingOnNoAgendaDay {
                return StreakState(days: current.days, lastValidatedDay: dayStart, reason: reason)
            }
        }

        if let last = current.lastValidatedDay,
           let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)),
           calendar.isDate(expected, inSameDayAs: dayStart) {
            return StreakState(days: current.days + 1, lastValidatedDay: dayStart, reason: reason)
        }

        return StreakState(days: 1, lastValidatedDay: dayStart, reason: reason)
    }
}

public struct NotificationPlanner {
    public init() {}

    public func reminderForDay(activities: [Activity]) -> NotificationMessage {
        if activities.isEmpty {
            return NotificationMessage(
                title: "Mantén tu racha activa",
                body: "Hoy no tienes actividades programadas. Haz un ejercicio del entrenador mental para mantener tu racha."
            )
        }

        return NotificationMessage(
            title: "Entrenamiento rápido",
            body: "¿Por qué no hacer un entrenamiento rápido hoy?"
        )
    }

    public func pomodoroFinishReminder(activityTitle: String) -> NotificationMessage {
        NotificationMessage(
            title: "Pomodoro listo",
            body: "Tu sesión para \"\(activityTitle)\" terminó. Toma un descanso corto y marca tu avance."
        )
    }

    public func mentalTrainingMotivation(streakDays: Int) -> NotificationMessage {
        if streakDays > 0 {
            return NotificationMessage(
                title: "Protege tu racha de \(streakDays) días",
                body: "Completa un entrenamiento mental rápido y mantén tu racha activa."
            )
        }
        return NotificationMessage(
            title: "Activa tu enfoque",
            body: "Haz un entrenamiento mental corto para arrancar con energía y concentración."
        )
    }
}
