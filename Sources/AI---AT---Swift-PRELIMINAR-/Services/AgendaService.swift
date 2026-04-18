import Foundation

public actor AgendaService {
    private let intelligence: AppleIntelligenceProviding
    private(set) var activities: [Activity]
    private(set) var sessions: [ActivitySession]

    public init(
        intelligence: AppleIntelligenceProviding = AppleIntelligenceService(),
        activities: [Activity] = [],
        sessions: [ActivitySession] = []
    ) {
        self.intelligence = intelligence
        self.activities = activities
        self.sessions = sessions
    }

    @discardableResult
    public func createActivity(
        title: String,
        topic: String,
        type: ActivityType,
        scheduledAt: Date
    ) -> Activity {
        let activity = Activity(title: title, topic: topic, type: type, scheduledAt: scheduledAt)
        activities.append(activity)
        return activity
    }

    public func listActivities(on day: Date, calendar: Calendar = .current) -> [Activity] {
        activities.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
    }

    @discardableResult
    public func updateActivity(_ activity: Activity) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return false }
        activities[index] = activity
        return true
    }

    @discardableResult
    public func completeActivity(id: UUID) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].status = .completed
        return true
    }

    @discardableResult
    public func markActivityPending(id: UUID) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].status = .pending
        return true
    }

    @discardableResult
    public func deleteActivity(id: UUID) -> Bool {
        let before = activities.count
        activities.removeAll { $0.id == id }
        return activities.count != before
    }

    public func startActivity(id: UUID, now: Date = Date()) async throws -> ActivitySession? {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return nil }
        activities[index].status = .inProgress
        let activity = activities[index]

        let material: [String]
        if activity.type == .task || activity.type == .study {
            material = try await intelligence.supportMaterial(for: activity.topic, type: activity.type)
        } else {
            material = []
        }

        let session = ActivitySession(
            activityID: activity.id,
            startedAt: now,
            pomodoroLengthMinutes: 25,
            supportMaterial: material
        )
        sessions.append(session)
        return session
    }
}
