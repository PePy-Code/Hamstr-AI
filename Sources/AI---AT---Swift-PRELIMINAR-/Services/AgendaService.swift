import Foundation

public actor AgendaService {
    private let intelligence: AIConversationProviding
    private let persistence: AgendaPersistenceProviding?
    private(set) var activities: [Activity]
    private(set) var sessions: [ActivitySession]

    public init(
        intelligence: AIConversationProviding = AIConversationService(),
        activities: [Activity] = [],
        sessions: [ActivitySession] = [],
        persistence: AgendaPersistenceProviding? = nil
    ) {
        self.intelligence = intelligence
        self.persistence = persistence
        if let persistence, let snapshot = try? persistence.load() {
            self.activities = snapshot.activities
            self.sessions = snapshot.sessions
        } else {
            self.activities = activities
            self.sessions = sessions
        }
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
        reconcileFailedActivities(now: Date())
        persist()
        return activity
    }

    public func listActivities(on day: Date, calendar: Calendar = .current) -> [Activity] {
        reconcileFailedActivities(now: Date())
        return activities.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
    }

    @discardableResult
    public func updateActivity(_ activity: Activity) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return false }
        activities[index] = activity
        reconcileFailedActivities(now: Date())
        persist()
        return true
    }

    @discardableResult
    public func completeActivity(id: UUID) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].status = .completed
        reconcileFailedActivities(now: Date())
        persist()
        return true
    }

    @discardableResult
    public func markActivityPending(id: UUID) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities[index].status = .pending
        reconcileFailedActivities(now: Date())
        persist()
        return true
    }

    @discardableResult
    public func deleteActivity(id: UUID) -> Bool {
        let before = activities.count
        activities.removeAll { $0.id == id }
        let changed = activities.count != before
        if changed {
            persist()
        }
        return changed
    }

    public func startActivity(id: UUID, now: Date = Date()) async throws -> ActivitySession? {
        reconcileFailedActivities(now: now)
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return nil }
        guard activities[index].status != .completed else { return nil }
        activities[index].status = .inProgress
        let activity = activities[index]

        let material: [String]
        if activity.type == .task || activity.type == .study {
            let supportContext = [activity.title, activity.topic]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
            material = try await intelligence.supportMaterial(for: supportContext, type: activity.type)
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
        persist()
        return session
    }

    private func reconcileFailedActivities(now: Date) {
        var hasChanges = false
        for index in activities.indices {
            let activity = activities[index]
            guard activity.scheduledAt < now else { continue }
            guard activity.status == .notStarted || activity.status == .pending else { continue }
            activities[index].status = .failed
            hasChanges = true
        }
        if hasChanges {
            persist()
        }
    }

    private func persist() {
        guard let persistence else { return }
        let snapshot = AgendaStorageSnapshot(activities: activities, sessions: sessions)
        try? persistence.save(snapshot)
    }
}
