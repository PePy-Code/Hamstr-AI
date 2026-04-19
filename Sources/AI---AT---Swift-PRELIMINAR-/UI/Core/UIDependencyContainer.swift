import Foundation

public struct UIDependencyContainer {
    public let agendaService: AgendaService
    public let intelligenceService: AIConversationService
    public let mentalTrainerService: MentalTrainerService
    public let notificationService: EngagementNotificationService

    public init(
        agendaService: AgendaService = AgendaService(persistence: LocalAgendaDatabase()),
        intelligenceService: AIConversationService = AIConversationService(),
        mentalTrainerService: MentalTrainerService = MentalTrainerService(),
        notificationService: EngagementNotificationService = AppNotifications.service
    ) {
        self.agendaService = agendaService
        self.intelligenceService = intelligenceService
        self.mentalTrainerService = mentalTrainerService
        self.notificationService = notificationService
    }

    public static func makeDefault() -> UIDependencyContainer {
        UIDependencyContainer()
    }
}
