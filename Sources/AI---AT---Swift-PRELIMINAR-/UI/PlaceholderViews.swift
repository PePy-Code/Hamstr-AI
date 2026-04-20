#if canImport(SwiftUI)
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UserNotifications)
// Delegate that allows local notifications to appear as banners even when the
// app is in the foreground (without this, iOS silently drops them).
private final class PomodoroNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PomodoroNotificationDelegate()
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// One-shot setup: request permission and register the foreground delegate.
private func requestPomodoroNotificationPermission() {
    guard AppPreferences.notificationsEnabled else { return }
    let center = UNUserNotificationCenter.current()
    center.delegate = PomodoroNotificationDelegate.shared
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
}

// Schedule an immediate local notification.  Safe to call from any thread.
private func schedulePomodoroNotification(title: String, body: String) {
    guard AppPreferences.notificationsEnabled else { return }
    guard !AppPreferences.isWithinQuietHours(date: Date()) else { return }
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
        identifier: "pomodoro-\(UUID().uuidString)",
        content: content,
        trigger: nil
    )
    center.add(request)
}
#endif

private func playConfiguredPomodoroSound() {
    #if canImport(AudioToolbox)
    guard let soundID = AppPreferences.timerSoundSystemID else { return }
    AudioServicesPlaySystemSound(SystemSoundID(soundID))
    #endif
}

private func localizedText(es: String, en: String) -> String {
    AppPreferences.language == .english ? en : es
}

private func appLocale() -> Locale {
    Locale(identifier: AppPreferences.localeIdentifier)
}

public struct HomeView: View {
    @State private var todayActivities: [Activity] = []
    @State private var tomorrowActivities: [Activity] = []
    @State private var streakState = StreakState()
    @State private var aiPetSupportMessage: String?
    @State private var hasLoaded = false
    @State private var pendingStartActivity: Activity?
    @State private var activeActivity: Activity?
    @State private var editingActivity: Activity?
    @State private var openWeeklyAgenda = false
    @State private var showQuickAddActivity = false
    @State private var openPersonalChatbot = false
    @State private var openSettings = false
    private let agendaService = AgendaService(persistence: LocalAgendaDatabase())
    private let intelligence = AIConversationService()
    private let calendar = Calendar.current

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Text("🔥")
                            Text("Racha")
                                .fontWeight(.semibold)
                            Text("\(streakState.days) días")
                                .font(.subheadline.weight(.bold))
                        }
                        Spacer()
                        NavigationLink {
                            MentalTrainerView()
                        } label: {
                            Label("Trainer", systemImage: "brain.head.profile")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    dailyGoalsCard

                    Button {
                        openPersonalChatbot = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("🐹")
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hamlet Hamster")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(displayedPetSupportMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button {
                            showQuickAddActivity = true
                        } label: {
                            Label("Nueva actividad", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            openWeeklyAgenda = true
                        } label: {
                            Label("Agenda completa", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    menuAgendaTable
                }
                .padding()
            }
            .navigationTitle("Menú principal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .onAppear {
                #if canImport(UserNotifications)
                requestPomodoroNotificationPermission()
                #endif
                Task { await refreshSummary() }
            }
            .onDisappear {
                aiPetSupportMessage = nil
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await seedInitialActivitiesIfNeeded()
                await refreshSummary()
            }
            .refreshable {
                await refreshSummary()
            }
            .alert(
                "¿Deseas iniciar esta actividad?",
                isPresented: Binding(
                    get: { pendingStartActivity != nil },
                    set: { newValue in
                        if !newValue { pendingStartActivity = nil }
                    }
                ),
                presenting: pendingStartActivity
            ) { activity in
                Button("No", role: .cancel) {
                    pendingStartActivity = nil
                }
                Button("Sí") {
                    activeActivity = activity
                    pendingStartActivity = nil
                }
            } message: { activity in
                Text("Actividad: \(activity.title)")
            }
            .sheet(item: $editingActivity) { activity in
                ActivityEditSheet(
                    agendaService: agendaService,
                    activity: activity,
                    onDidComplete: {
                        Task { await refreshSummary() }
                    }
                )
            }
            .navigationDestination(isPresented: $openWeeklyAgenda) {
                WeeklyAgendaView(agendaService: agendaService)
            }
            .navigationDestination(isPresented: $openPersonalChatbot) {
                PersonalChatbotView(
                    todayActivities: todayActivities,
                    tomorrowActivities: tomorrowActivities,
                    streakDays: streakState.days
                )
            }
            .navigationDestination(isPresented: $openSettings) {
                AppSettingsView()
            }
            .navigationDestination(item: $activeActivity) { activity in
                ActivityLaunchPlaceholderView(
                    agendaService: agendaService,
                    activity: activity,
                    onDidUpdateActivityState: {
                        Task { await refreshSummary() }
                    }
                )
            }
            .sheet(isPresented: $showQuickAddActivity) {
                AddActivitySheet(
                    agendaService: agendaService,
                    defaultDate: Date()
                ) {
                    Task { await refreshSummary() }
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .environment(\.dynamicTypeSize, preferredDynamicTypeSize)
    }

    private var menuAgendaTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agenda")
                .font(.headline)
            HStack(spacing: 8) {
                Text("Hora")
                    .frame(width: 60, alignment: .leading)
                    .font(.caption.weight(.semibold))
                Button(action: { openWeeklyAgenda = true }) {
                    Text("Hoy \(shortDate(Date()))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                Button(action: { openWeeklyAgenda = true }) {
                    Text("Mañana \(shortDate(nextDay))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            ForEach(0...24, id: \.self) { hour in
                HStack(spacing: 8) {
                    Button(action: { openWeeklyAgenda = true }) {
                        Text(String(format: "%02d:00", hour))
                            .font(.caption.monospacedDigit())
                            .frame(width: 60, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    agendaCell(for: activitiesAt(hour: hour, in: todayActivities))
                    agendaCell(for: activitiesAt(hour: hour, in: tomorrowActivities))
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dailyGoalsCard: some View {
        let completedActivities = todayActivities.filter { $0.status == .completed }.count
        let trainerSessions = MentalTrainingStreakStore.completionCount(on: Date(), calendar: calendar)
        let estimatedStudyMinutes = completedActivities * AppPreferences.pomodoroWorkMinutes
        let minutesGoal = max(AppPreferences.dailyGoalMinutes, 1)
        let activitiesGoal = max(AppPreferences.dailyGoalActivitiesCompleted, 1)
        let trainerGoal = max(AppPreferences.dailyGoalTrainerSessions, 1)
        let summary = localizedText(
            es: "Meta diaria: \(estimatedStudyMinutes)/\(minutesGoal) min · \(completedActivities)/\(activitiesGoal) actividades · trainer \(trainerSessions)/\(trainerGoal)",
            en: "Daily goal: \(estimatedStudyMinutes)/\(minutesGoal) min · \(completedActivities)/\(activitiesGoal) activities · trainer \(trainerSessions)/\(trainerGoal)"
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(localizedText(es: "🎯 Objetivo diario", en: "🎯 Daily goal"))
                .font(.subheadline.weight(.semibold))
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func agendaCell(for activities: [Activity]) -> some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(activities) { activity in
                    let isCompleted = activity.status == .completed
                    HStack(spacing: 6) {
                        Button {
                            pendingStartActivity = activity
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(for: activity.status))
                                    .frame(width: 8, height: 8)
                                Text("\(hourMinute(activity.scheduledAt)) \(activity.title)")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(6)
                            .background(statusColor(for: activity.status).opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(isCompleted)

                        Button {
                            editingActivity = activity
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .padding(6)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isCompleted)
                    }
                }
            }
        } else {
            Button(action: { openWeeklyAgenda = true }) {
                Text("—")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshSummary() async {
        let today = Date()
        let tomorrow = nextDay
        let activities = await agendaService.listActivities(on: today)
        let tomorrowItems = await agendaService.listActivities(on: tomorrow)
        let updatedStreakDays = await StreakComputation.days(endingOn: today, agendaService: agendaService, calendar: calendar)
        let todayReason = await StreakComputation.validationReason(for: today, agendaService: agendaService, calendar: calendar)
        let generatedPetMessage = await intelligence.mascotSupportMessage(
            todayActivities: activities,
            tomorrowActivities: tomorrowItems,
            streakDays: updatedStreakDays,
            now: today,
            calendar: calendar
        )
        await MainActor.run {
            self.todayActivities = activities
            self.tomorrowActivities = tomorrowItems
            self.aiPetSupportMessage = generatedPetMessage
            self.streakState = StreakState(
                days: updatedStreakDays,
                lastValidatedDay: updatedStreakDays > 0 ? calendar.startOfDay(for: today) : nil,
                reason: updatedStreakDays > 0 ? todayReason : .incompleteDay
            )
        }
    }

    private func seedInitialActivitiesIfNeeded() async {
        let existingToday = await agendaService.listActivities(on: Date())
        let existingTomorrow = await agendaService.listActivities(on: nextDay)
        guard existingToday.isEmpty, existingTomorrow.isEmpty else { return }

        let today = Date()
        let tomorrow = nextDay
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

    private var nextDay: Date {
        calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private func activitiesAt(hour: Int, in activities: [Activity]) -> [Activity] {
        activities
            .filter { calendar.component(.hour, from: $0.scheduledAt) == hour }
            .sorted {
                if $0.scheduledAt != $1.scheduledAt {
                    return $0.scheduledAt < $1.scheduledAt
                }
                if statusSortOrder($0.status) != statusSortOrder($1.status) {
                    return statusSortOrder($0.status) < statusSortOrder($1.status)
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        formatter.locale = appLocale()
        return formatter.string(from: date)
    }

    private func hourMinute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = appLocale()
        return formatter.string(from: date)
    }

    private func statusSortOrder(_ status: ActivityStatus) -> Int {
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

    private var preferredColorScheme: ColorScheme? {
        switch AppPreferences.visualTheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var preferredDynamicTypeSize: DynamicTypeSize {
        switch AppPreferences.fontScale {
        case .small: .small
        case .normal: .large
        case .large: .xLarge
        case .extraLarge: .xxLarge
        }
    }

    private var displayedPetSupportMessage: String {
        let generated = aiPetSupportMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !generated.isEmpty {
            return generated
        }
        return petSupportFallbackMessage
    }

    private var petSupportFallbackMessage: String {
        if streakState.days >= 7 {
            return "Llevas \(streakState.days) días seguidos. Eso es constancia real. 🔥"
        }
        if todayActivities.isEmpty {
            return "Sin actividades hoy. Una pequeña tarea marca la diferencia."
        }
        return "Un bloque a la vez. Cada paso suma 🐹"
    }

    private func statusColor(for status: ActivityStatus) -> Color {
        switch status {
        case .completed:
            return .green
        case .pending:
            return .yellow
        case .notStarted:
            return .gray.opacity(0.8)
        case .failed:
            return .red
        case .inProgress:
            return .blue
        }
    }
}

private struct PersonalChatbotView: View {
    let todayActivities: [Activity]
    let tomorrowActivities: [Activity]
    let streakDays: Int

    @State private var messages: [ActivityChatMessage] = []
    @State private var userInput = ""
    @State private var hasLoaded = false
    private let intelligence = AIConversationService()
    private static let maxActivitiesInSummary = 5

    var body: some View {
        VStack(spacing: 12) {
            chatSection
            chatComposer
        }
        .padding()
        .navigationTitle("Hamlet Hamster 🐹")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await seedWelcomeMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiChatHistoryCleared)) { _ in
            Task { await seedWelcomeMessage() }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hamlet Hamster 🐹")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        HStack {
                            if message.role == .assistant {
                                chatBubble(message, alignment: .leading, background: Color(.secondarySystemBackground))
                                Spacer(minLength: 30)
                            } else {
                                Spacer(minLength: 30)
                                chatBubble(message, alignment: .trailing, background: Color.blue.opacity(0.18))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var chatComposer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Escribe a Hamlet Hamster...", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Enviar") {
                    Task { await sendUserMessage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Pídele a Hamlet Hamster consejos, ayuda para organizarte o para recordar actividades.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: ActivityChatMessage, alignment: Alignment, background: Color) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 4) {
            messageTextView(message.text)
                .font(.footnote)
        }
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func messageTextView(_ text: String) -> some View {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(markdown)
                .tint(.blue)
        } else {
            Text(text)
        }
    }

    private func seedWelcomeMessage() async {
        await MainActor.run {
            messages = [ActivityChatMessage(role: .assistant, text: summaryIntroMessage())]
        }
    }

    private func sendUserMessage() async {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .user, text: text))
            userInput = ""
        }

        let response = await assistantResponse(for: text)
        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .assistant, text: response))
        }
    }

    private func assistantResponse(for text: String) async -> String {
        let agendaContext = agendaContextText
        let contextualMessage = agendaContext.isEmpty
            ? text
            : "\(text)\n\nContexto de agenda personal:\n\(agendaContext)"
        let history = conversationHistory(excluding: text)
        let modelReply = (try? await intelligence.chatReply(
            userMessage: contextualMessage,
            history: history,
            activityTitle: "Agenda personal",
            topic: agendaContext.isEmpty ? "Organización y foco" : agendaContext,
            type: .other
        )) ?? ""
        let cleaned = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Cuéntame qué necesitas organizar hoy 🐹"
        }
        return cleaned
    }

    /// Converts the current messages array into ConversationTurn history,
    /// excluding the most recently appended user message (which is passed separately).
    private func conversationHistory(excluding latestUserText: String) -> [ConversationTurn] {
        var turns = messages.compactMap { msg -> ConversationTurn? in
            switch msg.role {
            case .user:
                return ConversationTurn(role: .user, content: msg.text)
            case .assistant:
                return ConversationTurn(role: .assistant, content: msg.text)
            }
        }
        // Drop the last user turn — it was just appended and equals latestUserText.
        if turns.last?.role == .user, turns.last?.content.hasPrefix(latestUserText) == true {
            turns.removeLast()
        }
        return turns
    }

    private func summaryIntroMessage() -> String {
        let todayPending = todayActivities.filter { $0.status != .completed }.count
        let tomorrowCount = tomorrowActivities.count
        let streakDayWord = pluralizedWord(for: streakDays, singular: "día", plural: "días")
        let activityWord = pluralizedWord(for: todayPending, singular: "actividad", plural: "actividades")
        let streakText = streakDays > 0
            ? "Llevas una racha de \(streakDays) \(streakDayWord)."
            : "Aún no tienes racha activa."
        if todayActivities.isEmpty && tomorrowActivities.isEmpty {
            return "Hola, soy Hamlet Hamster 🐹\n\n\(streakText) No tienes actividades programadas.\n\nSi quieres, cuéntame en qué quieres avanzar hoy."
        }
        return "Hola, soy Hamlet Hamster 🐹\n\nHoy tienes \(todayPending) \(activityWord) pendientes y mañana hay \(tomorrowCount) más. \(streakText)\n\n¿En qué te ayudo?"
    }

    private func pluralizedWord(for count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    private var agendaContextText: String {
        let today = summarize(activities: todayActivities, dayLabel: "Hoy")
        let tomorrow = summarize(activities: tomorrowActivities, dayLabel: "Mañana")
        return [today, tomorrow]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func summarize(activities: [Activity], dayLabel: String) -> String {
        guard !activities.isEmpty else { return "" }
        let sorted = activities.sorted { $0.scheduledAt < $1.scheduledAt }
        let items = sorted.prefix(Self.maxActivitiesInSummary).map { activity in
            "\(hourAndMinute(activity.scheduledAt)) \(activity.title) [\(activity.status.rawValue)]"
        }.joined(separator: ", ")
        return "\(dayLabel): \(items)"
    }

    private func hourAndMinute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func appendChatMessage(_ message: ActivityChatMessage) {
        messages.append(message)
        let keepLimit = AppPreferences.aiStoreConversationHistory
            ? AppPreferences.aiChatHistoryLimit
            : 4
        if messages.count > keepLimit {
            messages = Array(messages.suffix(keepLimit))
        }
    }
}

private struct ActivityLaunchPlaceholderView: View {
    let agendaService: AgendaService
    let activity: Activity
    let onDidUpdateActivityState: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasLoaded = false
    @State private var messages: [ActivityChatMessage] = []
    @State private var userInput = ""
    @State private var finishAlertStep: FinishAlertStep?
    @State private var streakDays = 0
    @State private var navigateToTrainer = false
    @State private var navigateToTrainerAfterStreak = false
    @State private var didNavigateToTrainerFromActivity = false
    @State private var shouldShowStreakPopup = false
    @State private var isFinishing = false
    @State private var pomodoroTransitionAlert: PomodoroTransitionAlert?
    @State private var remainingSeconds = max(AppPreferences.pomodoroWorkMinutes, 1) * 60
    @State private var isRunning = true
    @State private var isWorkPhase = true
    @State private var completedWorkCycles = 0
    @State private var elapsedWellbeingSeconds = 0
    @State private var wellbeingMessage: String?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let intelligence = AIConversationService()
    private let calendar = Calendar.current
    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("Finalizar") {
                    finishAlertStep = .confirmFinish
                }
                .buttonStyle(.borderedProminent)

                Button("Pendiente") {
                    Task { await markPendingAndExit() }
                }
                .buttonStyle(.bordered)
            }

            pomodoroCard
                .alert(item: $pomodoroTransitionAlert) { alert in
                    Alert(
                        title: Text("Pomodoro"),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            chatSection
            chatComposer
        }
        .padding()
        .navigationTitle("Iniciar actividad")
        .navigationBarBackButtonHidden(true)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await startSessionAndSeedChat()
        }
        .onReceive(ticker) { _ in
            guard isRunning else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                processWellbeingTick()
            } else {
                let wasWorkPhase = isWorkPhase
                isWorkPhase.toggle()
                if wasWorkPhase {
                    completedWorkCycles += 1
                }
                remainingSeconds = durationForCurrentPhase()
                isRunning = AppPreferences.pomodoroAutoStartNextPhase
                pomodoroTransitionAlert = PomodoroTransitionAlert(
                    message: wasWorkPhase
                        ? "¡Hora de descanso!"
                        : "¡Hora de trabajo!"
                )
                elapsedWellbeingSeconds = 0
                playPomodoroTransitionSound()
                sendPomodoroPhaseNotification(isBreak: wasWorkPhase)
            }
        }
        .alert(item: $finishAlertStep) { step in
            switch step {
            case .confirmFinish:
                return Alert(
                    title: Text("Finalizar actividad"),
                    message: Text("¿Seguro que quieres finalizar \(activity.title)?"),
                    primaryButton: .destructive(Text("Finalizar")) {
                        Task { await completeAndStartFinishFlow() }
                    },
                    secondaryButton: .cancel(Text("Cancelar"))
                )
            case .congrats:
                return Alert(
                    title: Text("¡Felicidades!"),
                    message: Text("Terminaste \(activity.title)."),
                    dismissButton: .default(Text("Continuar")) {
                        if AppPreferences.mentalTrainerSuggestionEnabled {
                            finishAlertStep = .mentalTrainingPrompt
                        } else if shouldShowStreakPopup {
                            finishAlertStep = .streak
                        } else {
                            dismiss()
                        }
                    }
                )
            case .mentalTrainingPrompt:
                return Alert(
                    title: Text("🐹 Entrenamiento mental"),
                    message: Text("¿Te gustaría hacer un entrenamiento mental?"),
                    primaryButton: .default(Text("Sí")) {
                        if shouldShowStreakPopup {
                            navigateToTrainerAfterStreak = true
                            finishAlertStep = .streak
                        } else {
                            didNavigateToTrainerFromActivity = true
                            navigateToTrainer = true
                        }
                    },
                    secondaryButton: .cancel(Text("No")) {
                        if shouldShowStreakPopup {
                            navigateToTrainerAfterStreak = false
                            finishAlertStep = .streak
                        } else {
                            dismiss()
                        }
                    }
                )
            case .streak:
                return Alert(
                    title: Text("🔥 Racha"),
                    message: Text("Llevas una racha de \(streakDays) días."),
                    dismissButton: .default(Text("Continuar")) {
                        if navigateToTrainerAfterStreak {
                            navigateToTrainerAfterStreak = false
                            didNavigateToTrainerFromActivity = true
                            navigateToTrainer = true
                        } else {
                            dismiss()
                        }
                    }
                )
            }
        }
        .navigationDestination(isPresented: $navigateToTrainer) {
            MentalTrainerView()
        }
        .onChange(of: navigateToTrainer) { _, isPresented in
            guard didNavigateToTrainerFromActivity, !isPresented else { return }
            didNavigateToTrainerFromActivity = false
            dismiss()
        }
        #if canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task { await handleImageAttachment(item: newValue) }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .aiChatHistoryCleared)) { _ in
            messages = []
        }
    }

    private var pomodoroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pomodoro")
                    .font(.headline)
                Spacer()
                Text(isWorkPhase ? "Trabajo" : "Descanso")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isWorkPhase ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(isWorkPhase ? .blue : .green)
                    .clipShape(Capsule())
            }

            Text(formattedTime(remainingSeconds))
                .font(.title2.monospacedDigit().weight(.bold))

            Text(currentPomodoroPhaseMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                isWorkPhase
                    ? "Próxima fase: descanso (\(formattedTime(nextBreakDurationSeconds())))"
                    : "Próxima fase: trabajo (\(formattedTime(workDurationSeconds())))"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let wellbeingMessage {
                Text(wellbeingMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button(isRunning ? "Pausar" : "Iniciar") {
                    isRunning.toggle()
                }
                .buttonStyle(.bordered)

                Button("Reiniciar") {
                    isRunning = false
                    isWorkPhase = true
                    remainingSeconds = workDurationSeconds()
                    completedWorkCycles = 0
                    elapsedWellbeingSeconds = 0
                    wellbeingMessage = nil
                }
                .buttonStyle(.bordered)

                #if DEBUG
                Button("DEBUG 10 s") {
                    remainingSeconds = 10
                    isRunning = true
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hamlet Hamster 🐹")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        HStack {
                            if message.role == .assistant {
                                chatBubble(message, alignment: .leading, background: Color(.secondarySystemBackground))
                                Spacer(minLength: 30)
                            } else {
                                Spacer(minLength: 30)
                                chatBubble(message, alignment: .trailing, background: Color.blue.opacity(0.18))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private var chatComposer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                #if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "plus.viewfinder")
                }
                .buttonStyle(.bordered)
                #else
                Button {
                    Task { await addSimulatedImageAttachment() }
                } label: {
                    Image(systemName: "plus.viewfinder")
                }
                .buttonStyle(.bordered)
                #endif

                TextField("Escribe a Hamlet Hamster...", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Enviar") {
                    Task { await sendUserMessage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Hamlet Hamster responde preguntas, explica conceptos y sugiere fuentes abiertas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: ActivityChatMessage, alignment: Alignment, background: Color) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 4) {
            if message.isImageAttachment {
                Label("Imagen adjunta", systemImage: "photo")
                    .font(.caption.weight(.semibold))
            }
            messageTextView(message.text)
                .font(.footnote)
        }
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func messageTextView(_ text: String) -> some View {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(markdown)
                .tint(.blue)
        } else {
            Text(text)
        }
    }

    private func startSessionAndSeedChat() async {
        _ = try? await agendaService.startActivity(id: activity.id)
        await MainActor.run {
            messages = []
            isWorkPhase = true
            completedWorkCycles = 0
            remainingSeconds = workDurationSeconds()
            wellbeingMessage = nil
            elapsedWellbeingSeconds = 0
        }
    }

    private func sendUserMessage() async {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .user, text: text))
            userInput = ""
        }

        let response = await assistantResponse(for: text)
        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .assistant, text: response))
        }
    }

    private func assistantResponse(for text: String) async -> String {
        let history = conversationHistory(excluding: text)
        let modelReply = (try? await intelligence.chatReply(
            userMessage: text,
            history: history,
            activityTitle: activity.title,
            topic: normalizedTopic,
            type: activity.type
        )) ?? ""
        let cleaned = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Dame más contexto y te respondo de forma concreta 🐹"
        }
        return cleaned
    }

    /// Converts the current messages array into ConversationTurn history,
    /// excluding the most recently appended user message (which is passed separately).
    private func conversationHistory(excluding latestUserText: String) -> [ConversationTurn] {
        var turns = messages.compactMap { msg -> ConversationTurn? in
            switch msg.role {
            case .user:
                return ConversationTurn(role: .user, content: msg.text)
            case .assistant:
                return ConversationTurn(role: .assistant, content: msg.text)
            }
        }
        if turns.last?.role == .user, turns.last?.content == latestUserText {
            turns.removeLast()
        }
        return turns
    }

    #if canImport(PhotosUI)
    private func handleImageAttachment(item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        let sizeText: String
        if let data {
            sizeText = "\(max(data.count / 1024, 1)) KB"
        } else {
            sizeText = "sin tamaño"
        }
        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .user, text: "Compartí una imagen (\(sizeText)) para revisión.", isImageAttachment: true))
        }
        let supportContext = [activity.title, normalizedTopic]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let support = (try? await intelligence.supportMaterial(for: supportContext, type: activity.type)) ?? []
        let bulletText = support.isEmpty ? "" : "\n" + support.map { "• \($0)" }.joined(separator: "\n")
        await MainActor.run {
            appendChatMessage(
                ActivityChatMessage(
                    role: .assistant,
                    text: "Gracias por la imagen. Te doy retroalimentación general y cómo mejorar tu trabajo con estas fuentes:\(bulletText)"
                )
            )
            selectedPhotoItem = nil
        }
    }
    #else
    private func addSimulatedImageAttachment() async {
        await MainActor.run {
            appendChatMessage(ActivityChatMessage(role: .user, text: "Compartí una imagen para revisión.", isImageAttachment: true))
            appendChatMessage(ActivityChatMessage(role: .assistant, text: "Recibí tu imagen. Puedo darte retroalimentación y fuentes para mejorar tu actividad."))
        }
    }
    #endif

    private func markPendingAndExit() async {
        _ = await agendaService.markActivityPending(id: activity.id)
        await MainActor.run {
            onDidUpdateActivityState()
            dismiss()
        }
    }

    private func completeAndStartFinishFlow() async {
        guard !isFinishing else { return }
        await MainActor.run {
            isFinishing = true
        }
        let didComplete = await agendaService.completeActivity(id: activity.id)
        guard didComplete else {
            await MainActor.run {
                isFinishing = false
            }
            return
        }
        let todaysActivities = await agendaService.listActivities(on: Date(), calendar: calendar)
        let shouldShowStreak = !todaysActivities.isEmpty && todaysActivities.allSatisfy { $0.status == .completed }
        let streak = shouldShowStreak
            ? await StreakComputation.days(endingOn: Date(), agendaService: agendaService, calendar: calendar)
            : 0
        await MainActor.run {
            onDidUpdateActivityState()
            shouldShowStreakPopup = shouldShowStreak
            streakDays = streak
            finishAlertStep = .congrats
            isFinishing = false
        }
    }

    private var normalizedTopic: String {
        let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return activity.topic
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = max(totalSeconds, 0) / 60
        let seconds = max(totalSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var currentPomodoroPhaseMessage: String {
        let phase = isWorkPhase ? "trabajo" : "descanso"
        return isRunning
            ? "En curso: \(phase)"
            : "Pausado: \(phase)"
    }

    private func playPomodoroTransitionSound() {
        playConfiguredPomodoroSound()
    }

    private func sendPomodoroPhaseNotification(isBreak: Bool) {
        #if canImport(UserNotifications)
        let body = isBreak ? "¡Hora de descanso!" : "¡Hora de trabajo!"
        schedulePomodoroNotification(title: "Pomodoro", body: body)
        #endif
    }

    private func workDurationSeconds() -> Int {
        max(AppPreferences.pomodoroWorkMinutes, 1) * 60
    }

    private func shortBreakDurationSeconds() -> Int {
        max(AppPreferences.pomodoroBreakMinutes, 1) * 60
    }

    private func longBreakDurationSeconds() -> Int {
        max(AppPreferences.pomodoroLongBreakMinutes, 1) * 60
    }

    private func nextBreakDurationSeconds() -> Int {
        breakDurationSeconds(forCompletedCycles: completedWorkCycles + 1)
    }

    private func breakDurationSeconds(forCompletedCycles completedCycles: Int) -> Int {
        let cycleLength = max(AppPreferences.pomodoroCyclesBeforeLongBreak, 1)
        if completedCycles % cycleLength == 0 {
            return longBreakDurationSeconds()
        }
        return shortBreakDurationSeconds()
    }

    private func durationForCurrentPhase() -> Int {
        isWorkPhase ? workDurationSeconds() : breakDurationSeconds(forCompletedCycles: completedWorkCycles)
    }

    private func processWellbeingTick() {
        let intervalSeconds = max(AppPreferences.wellbeingReminderMinutes, 5) * 60
        guard intervalSeconds > 0 else { return }
        elapsedWellbeingSeconds += 1
        guard elapsedWellbeingSeconds >= intervalSeconds else { return }
        elapsedWellbeingSeconds = 0
        wellbeingMessage = nextWellbeingMessage()
    }

    private func nextWellbeingMessage() -> String? {
        var messages: [String] = []
        if AppPreferences.wellbeingActiveBreakEnabled {
            messages.append(localizedText(es: "Haz una pausa activa de 1-2 minutos.", en: "Take a 1-2 minute active break."))
        }
        if AppPreferences.wellbeingHydrationEnabled {
            messages.append(localizedText(es: "Toma agua para mantenerte hidratado.", en: "Drink water to stay hydrated."))
        }
        if AppPreferences.wellbeingEyeRestEnabled {
            messages.append(localizedText(es: "Descansa la vista: mira a lo lejos 20 segundos.", en: "Rest your eyes: look into the distance for 20 seconds."))
        }
        guard !messages.isEmpty else { return nil }
        let index = completedWorkCycles % messages.count
        return messages[index]
    }

    private func appendChatMessage(_ message: ActivityChatMessage) {
        messages.append(message)
        let keepLimit = AppPreferences.aiStoreConversationHistory
            ? AppPreferences.aiChatHistoryLimit
            : 4
        if messages.count > keepLimit {
            messages = Array(messages.suffix(keepLimit))
        }
    }
}

private enum FinishAlertStep: String, Identifiable {
    case confirmFinish
    case congrats
    case mentalTrainingPrompt
    case streak

    var id: String { rawValue }
}

private struct ActivityChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var isImageAttachment: Bool = false
}

private struct PomodoroTransitionAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct ActivityEditSheet: View {
    let agendaService: AgendaService
    let activity: Activity
    let onDidComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var topic: String
    @State private var typeRawValue: String
    @State private var scheduledAt: Date
    @State private var errorMessage: String?
    @State private var shouldConfirmDelete = false

    init(
        agendaService: AgendaService,
        activity: Activity,
        onDidComplete: @escaping () -> Void
    ) {
        self.agendaService = agendaService
        self.activity = activity
        self.onDidComplete = onDidComplete
        _title = State(initialValue: activity.title)
        _topic = State(initialValue: activity.topic)
        _typeRawValue = State(initialValue: activity.type.rawValue)
        _scheduledAt = State(initialValue: activity.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Editar valores de actividad") {
                    TextField("Nombre", text: $title)
                    TextField("Tema", text: $topic)
                    Picker("Tipo", selection: $typeRawValue) {
                        ForEach(ActivityType.allCases, id: \.rawValue) { type in
                            Text(typeLabel(type)).tag(type.rawValue)
                        }
                    }
                    DatePicker("Fecha y hora", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Button("Guardar cambios") {
                        Task { await save() }
                    }
                    Button("Eliminar actividad", role: .destructive) {
                        shouldConfirmDelete = true
                    }
                }
            }
            .navigationTitle("Editar actividad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .alert("No se pudo completar la acción", isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Eliminar actividad", isPresented: $shouldConfirmDelete) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
        }
    }

    private func save() async {
        var updated = activity
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.type = ActivityType(rawValue: typeRawValue) ?? .study
        updated.scheduledAt = scheduledAt
        guard !updated.title.isEmpty, !updated.topic.isEmpty else { return }
        let didUpdate = await agendaService.updateActivity(updated)
        guard handleResult(didUpdate, failureMessage: "No se pudo guardar la actividad. Inténtalo de nuevo.") else { return }
        await completeAndDismiss()
    }

    private func delete() async {
        let didDelete = await agendaService.deleteActivity(id: activity.id)
        guard handleResult(didDelete, failureMessage: "No se pudo eliminar la actividad. Inténtalo de nuevo.") else { return }
        await completeAndDismiss()
    }

    private func completeAndDismiss() async {
        await MainActor.run {
            onDidComplete()
            dismiss()
        }
    }

    private func handleResult(_ isSuccess: Bool, failureMessage: String) -> Bool {
        guard isSuccess else {
            errorMessage = failureMessage
            return false
        }
        return true
    }

    private func typeLabel(_ type: ActivityType) -> String {
        switch type {
        case .task: "Tarea"
        case .study: "Estudio"
        case .other: "Otro"
        }
    }
}

private struct WeeklyAgendaView: View {
    let agendaService: AgendaService

    @State private var weekStart: Date
    @State private var weekActivities: [Activity] = []
    @State private var showAddActivity = false
    @State private var editingActivity: Activity?
    @State private var pendingStartActivity: Activity?
    @State private var activeActivity: Activity?
    private let calendar = Calendar.current

    init(agendaService: AgendaService) {
        self.agendaService = agendaService
        _weekStart = State(initialValue: Self.normalizedStartOfWeek(from: Date(), calendar: .current))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    moveWeek(by: -1)
                } label: {
                    Image(systemName: "triangle.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
                Text(weekTitle)
                    .font(.headline)
                Spacer()

                Button {
                    moveWeek(by: 1)
                } label: {
                    Image(systemName: "triangle.fill")
                        .rotationEffect(.degrees(180))
                }
                .buttonStyle(.bordered)
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Hora")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption.weight(.semibold))
                        ForEach(weekDays, id: \.self) { day in
                            Text(weekdayTitle(day))
                                .frame(minWidth: 120, alignment: .leading)
                                .font(.caption.weight(.semibold))
                        }
                    }

                    ForEach(0...24, id: \.self) { hour in
                        HStack(spacing: 8) {
                            Text(String(format: "%02d:00", hour))
                                .font(.caption.monospacedDigit())
                                .frame(width: 60, alignment: .leading)
                            ForEach(weekDays, id: \.self) { day in
                                let activities = activities(for: day, hour: hour)
                                Group {
                                    if activities.isEmpty {
                                        Text("—")
                                            .foregroundStyle(.tertiary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(activities) { activity in
                                                let isCompleted = activity.status == .completed
                                                Button {
                                                    guard !isCompleted else { return }
                                                    pendingStartActivity = activity
                                                } label: {
                                                    Text("\(hourMinute(activity.scheduledAt)) \(activity.title) • \(statusLabel(for: activity.status))")
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(statusColor(for: activity.status).opacity(0.2))
                                                        .foregroundStyle(statusColor(for: activity.status))
                                                        .clipShape(Capsule())
                                                    }
                                                .buttonStyle(.plain)
                                                .disabled(isCompleted)
                                                .contextMenu {
                                                    if !isCompleted {
                                                        Button("Iniciar actividad") {
                                                            pendingStartActivity = activity
                                                        }
                                                    }
                                                    Button("Editar") {
                                                        editingActivity = activity
                                                    }
                                                }
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Button {
                    showAddActivity = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
            }
        }
        .padding()
        .navigationTitle("Agenda semanal")
        .task {
            await loadWeekActivities()
        }
        .alert(
            "¿Deseas iniciar esta actividad?",
            isPresented: Binding(
                get: { pendingStartActivity != nil },
                set: { newValue in
                    if !newValue { pendingStartActivity = nil }
                }
            ),
            presenting: pendingStartActivity
        ) { activity in
            Button("No", role: .cancel) {
                pendingStartActivity = nil
            }
            Button("Sí") {
                activeActivity = activity
                pendingStartActivity = nil
            }
        } message: { activity in
            Text("Actividad: \(activity.title)")
        }
        .navigationDestination(item: $activeActivity) { activity in
            ActivityLaunchPlaceholderView(
                agendaService: agendaService,
                activity: activity,
                onDidUpdateActivityState: {
                    Task { await loadWeekActivities() }
                }
            )
        }
        .sheet(isPresented: $showAddActivity) {
            AddActivitySheet(
                agendaService: agendaService,
                defaultDate: Date()
            ) {
                Task { await loadWeekActivities() }
            }
        }
        .sheet(item: $editingActivity) { activity in
            ActivityEditSheet(
                agendaService: agendaService,
                activity: activity,
                onDidComplete: {
                    Task { await loadWeekActivities() }
                }
            )
        }
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }
    }

    private var weekTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: end))"
    }

    private func moveWeek(by delta: Int) {
        if let newStart = calendar.date(byAdding: .day, value: delta * 7, to: weekStart) {
            weekStart = newStart
            Task { await loadWeekActivities() }
        }
    }

    private func loadWeekActivities() async {
        var collected: [Activity] = []
        for day in weekDays {
            let activities = await agendaService.listActivities(on: day, calendar: calendar)
            collected.append(contentsOf: activities)
        }
        await MainActor.run {
            self.weekActivities = collected
        }
    }

    private func activities(for day: Date, hour: Int) -> [Activity] {
        weekActivities.filter {
            calendar.isDate($0.scheduledAt, inSameDayAs: day)
            && calendar.component(.hour, from: $0.scheduledAt) == hour
        }
        .sorted {
            if $0.scheduledAt != $1.scheduledAt {
                return $0.scheduledAt < $1.scheduledAt
            }
            if statusSortOrder($0.status) != statusSortOrder($1.status) {
                return statusSortOrder($0.status) < statusSortOrder($1.status)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func weekdayTitle(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE dd/MM"
        return formatter.string(from: day)
    }

    private func statusLabel(for status: ActivityStatus) -> String {
        switch status {
        case .completed:
            return "Finalizado"
        case .pending:
            return "Pendiente"
        case .notStarted:
            return "Por hacer"
        case .failed:
            return "No completada"
        case .inProgress:
            return "En progreso"
        }
    }

    private func statusColor(for status: ActivityStatus) -> Color {
        switch status {
        case .completed:
            return .green
        case .pending:
            return .yellow
        case .notStarted:
            return .gray.opacity(0.8)
        case .failed:
            return .red
        case .inProgress:
            return .blue
        }
    }

    private func hourMinute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func statusSortOrder(_ status: ActivityStatus) -> Int {
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

    private static func normalizedStartOfWeek(from date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}

private struct AddActivitySheet: View {
    let agendaService: AgendaService
    let defaultDate: Date
    let onDidAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var topic = ""
    @State private var typeRawValue = ActivityType.study.rawValue
    @State private var scheduledAt: Date

    init(
        agendaService: AgendaService,
        defaultDate: Date,
        onDidAdd: @escaping () -> Void
    ) {
        self.agendaService = agendaService
        self.defaultDate = defaultDate
        self.onDidAdd = onDidAdd
        _scheduledAt = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva actividad") {
                    TextField("Nombre", text: $title)
                    TextField("Tema", text: $topic)
                    Picker("Tipo", selection: $typeRawValue) {
                        ForEach(ActivityType.allCases, id: \.rawValue) { type in
                            Text(typeLabel(type)).tag(type.rawValue)
                        }
                    }
                    DatePicker("Fecha y hora", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Button("Agregar") {
                        Task { await add() }
                    }
                }
            }
            .navigationTitle("Agregar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func add() async {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, !cleanedTopic.isEmpty else { return }
        let type = ActivityType(rawValue: typeRawValue) ?? .study
        _ = await agendaService.createActivity(title: cleanedTitle, topic: cleanedTopic, type: type, scheduledAt: scheduledAt)
        await MainActor.run {
            onDidAdd()
            dismiss()
        }
    }

    private func typeLabel(_ type: ActivityType) -> String {
        switch type {
        case .task: "Tarea"
        case .study: "Estudio"
        case .other: "Otro"
        }
    }
}

public struct AgendaView: View {
    @State private var activities: [Activity] = []
    @State private var selectedActivityID: UUID?
    @State private var hasLoaded = false
    @State private var newTitle = ""
    @State private var newTopic = ""
    @State private var newTypeRawValue = ActivityType.study.rawValue
    @State private var supportMaterialByActivityID: [UUID: [String]] = [:]
    @State private var timerNotificationMessage: NotificationMessage?
    private let agendaService = AgendaService(persistence: LocalAgendaDatabase())
    private let notificationService = AppNotifications.service

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Agenda")
                .font(.title2)
            Text("Agenda funcional para tareas, estudio y otros.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                TextField("Título", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Tema", text: $newTopic)
                    .textFieldStyle(.roundedBorder)
                Picker("Tipo", selection: $newTypeRawValue) {
                    ForEach(ActivityType.allCases, id: \.rawValue) { type in
                        Text(typeLabel(for: type)).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Button("Agregar actividad") {
                    Task {
                        await addActivity()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if activities.isEmpty {
                Text("Sin actividades para hoy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activities) { activity in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activity.title)
                                    .font(.headline)
                                Text(activity.topic)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(statusLabel(for: activity.status))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor(for: activity.status).opacity(0.2))
                                .foregroundStyle(statusColor(for: activity.status))
                                .clipShape(Capsule())
                            Button("Iniciar") {
                                Task {
                                    if let session = try? await agendaService.startActivity(id: activity.id) {
                                        await MainActor.run {
                                            supportMaterialByActivityID[activity.id] = session.supportMaterial
                                        }
                                    }
                                    selectedActivityID = activity.id
                                    await reloadActivities()
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("Eliminar", role: .destructive) {
                                Task {
                                    _ = await agendaService.deleteActivity(id: activity.id)
                                    await reloadActivities()
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedActivityID = activity.id
                        }
                    }
                }
            }

            if let active = selectedActivity {
                if let timerNotificationMessage {
                    Label(timerNotificationMessage.body, systemImage: "timer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let support = supportMaterialByActivityID[active.id], !support.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Material IA para \(active.topic)")
                            .font(.headline)
                        ForEach(support, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(line)
                                    .font(.footnote)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                PomodoroTimerView(
                    title: "Pomodoro: \(active.title)",
                    initialSeconds: max(AppPreferences.pomodoroWorkMinutes, 1) * 60,
                    onTimerScheduled: { remainingSeconds in
                        guard AppPreferences.notificationsEnabled else {
                            timerNotificationMessage = nil
                            return
                        }
                        Task {
                            let message = await notificationService.schedulePomodoroTimerNotification(
                                activityTitle: active.title,
                                remainingSeconds: remainingSeconds
                            )
                            await MainActor.run {
                                timerNotificationMessage = message
                            }
                        }
                    },
                    onMarkCompleted: {
                        Task {
                            _ = await agendaService.completeActivity(id: active.id)
                            await reloadActivities()
                        }
                    },
                    onMarkPending: {
                        Task {
                            _ = await agendaService.markActivityPending(id: active.id)
                            await reloadActivities()
                        }
                    },
                    onTimerFinished: {
                        Task {
                            _ = await agendaService.completeActivity(id: active.id)
                            await reloadActivities()
                        }
                    }
                )
                .id(active.id)
            }
        }
        .padding()
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await seedInitialActivitiesIfNeeded()
            await reloadActivities()
        }
    }

    private var selectedActivity: Activity? {
        if let selectedActivityID {
            return activities.first(where: { $0.id == selectedActivityID })
        }
        return activities.first(where: { $0.status == .inProgress }) ?? activities.first
    }

    private func seedInitialActivitiesIfNeeded() async {
        let today = Date()
        let existing = await agendaService.listActivities(on: today)
        guard existing.isEmpty else {
            selectedActivityID = existing.first(where: { $0.status == .inProgress })?.id ?? existing.first?.id
            return
        }

        _ = await agendaService.createActivity(
            title: "Repaso de matemáticas",
            topic: "Derivadas",
            type: .study,
            scheduledAt: today
        )
        _ = await agendaService.createActivity(
            title: "Entregar tarea",
            topic: "Álgebra",
            type: .task,
            scheduledAt: today
        )
    }

    private func reloadActivities() async {
        let today = Date()
        let listed = await agendaService.listActivities(on: today)
        await MainActor.run {
            self.activities = listed
            if self.selectedActivityID == nil || !listed.contains(where: { $0.id == self.selectedActivityID }) {
                self.selectedActivityID = listed.first(where: { $0.status == .inProgress })?.id ?? listed.first?.id
            }
        }
    }

    private func addActivity() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !topic.isEmpty else { return }
        let type = ActivityType(rawValue: newTypeRawValue) ?? .study
        _ = await agendaService.createActivity(title: title, topic: topic, type: type, scheduledAt: Date())
        await MainActor.run {
            newTitle = ""
            newTopic = ""
            newTypeRawValue = ActivityType.study.rawValue
        }
        await reloadActivities()
    }

    private func typeLabel(for type: ActivityType) -> String {
        switch type {
        case .task:
            "Tarea"
        case .study:
            "Estudio"
        case .other:
            "Otro"
        }
    }

    private func statusLabel(for status: ActivityStatus) -> String {
        switch status {
        case .notStarted:
            "Por hacer"
        case .pending:
            "Pendiente"
        case .inProgress:
            "En progreso"
        case .completed:
            "Finalizado"
        case .failed:
            "No completada"
        }
    }

    private func statusColor(for status: ActivityStatus) -> Color {
        switch status {
        case .notStarted:
            .gray.opacity(0.8)
        case .pending:
            .yellow
        case .inProgress:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

public struct PomodoroTimerView: View {
    public let title: String
    public let initialSeconds: Int
    public let onTimerScheduled: ((Int) -> Void)?
    public let onMarkCompleted: () -> Void
    public let onMarkPending: () -> Void
    public let onTimerFinished: (() -> Void)?
    @State private var remainingSeconds: Int
    @State private var isRunning = false
    @State private var didFinish = false
    @State private var showFinishedAlert = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        title: String,
        initialSeconds: Int,
        onTimerScheduled: ((Int) -> Void)? = nil,
        onMarkCompleted: @escaping () -> Void,
        onMarkPending: @escaping () -> Void,
        onTimerFinished: (() -> Void)? = nil
    ) {
        self.title = title
        self.initialSeconds = max(initialSeconds, 0)
        self.onTimerScheduled = onTimerScheduled
        self.onMarkCompleted = onMarkCompleted
        self.onMarkPending = onMarkPending
        self.onTimerFinished = onTimerFinished
        _remainingSeconds = State(initialValue: max(initialSeconds, 0))
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text(formattedTime(remainingSeconds))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            if didFinish {
                Text("Tiempo completado")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                Button(isRunning ? "Pausar" : "Iniciar") {
                    guard remainingSeconds > 0 else { return }
                    let shouldStart = !isRunning
                    isRunning.toggle()
                    if shouldStart {
                        didFinish = false
                        onTimerScheduled?(remainingSeconds)
                    }
                }
                .buttonStyle(.bordered)
                Button("Reiniciar") {
                    resetTimer()
                }
                .buttonStyle(.bordered)
                Button("Marcar realizada", action: onMarkCompleted)
                    .buttonStyle(.borderedProminent)
                Button("Dejar pendiente", action: onMarkPending)
                    .buttonStyle(.bordered)
            }
        }
        .onReceive(ticker) { _ in
            guard isRunning, remainingSeconds > 0 else { return }
            remainingSeconds -= 1
            if remainingSeconds == 0 {
                isRunning = false
                didFinish = true
                showFinishedAlert = true
                playFinishSound()
                sendFinishNotification()
                onTimerFinished?()
            }
        }
        .alert("⏰ Pomodoro terminado", isPresented: $showFinishedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(title.isEmpty ? "¡Tiempo completado!" : "¡Completaste: \(title)!")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resetTimer() {
        isRunning = false
        didFinish = false
        remainingSeconds = initialSeconds
    }

    private func playFinishSound() {
        playConfiguredPomodoroSound()
    }

    private func sendFinishNotification() {
        #if canImport(UserNotifications)
        let body = title.isEmpty ? "¡Tiempo completado!" : "¡Completaste: \(title)!"
        schedulePomodoroNotification(title: "⏰ Pomodoro terminado", body: body)
        #endif
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = max(totalSeconds, 0) / 60
        let seconds = max(totalSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public struct MentalTrainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasStarted = false
    @State private var currentQuestion: TriviaQuestion?
    @State private var correctAnswers = 0
    @State private var incorrectAnswers = 0
    @State private var currentQuestionIndex = 0
    @State private var totalQuestions = 0
    @State private var questionDeadline: Date?
    @State private var remainingSeconds = 0
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .secondary
    @State private var isGameOver = false
    @State private var sessionCompleted = false
    @State private var questionAnswered = false
    @State private var showCorrectAnswerIndicator = false
    @State private var answeredOptionIndex: Int?
    @State private var correctOptionIndex: Int?
    @State private var hasScheduledMotivation = false
    @State private var scheduledMotivationMessage: NotificationMessage?
    @State private var trainerAlertStep: TrainerAlertStep?
    @State private var lossAlertMessage = ""
    @State private var countdownTask: Task<Void, Never>?
    private let answerRevealDelayNanoseconds: UInt64 = 350_000_000
    private let mentalService = MentalTrainerService()
    private let notificationService = AppNotifications.service
    private let agendaService = AgendaService(persistence: LocalAgendaDatabase())
    private let calendar = Calendar.current

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entrenador Mental")
                .font(.title2.weight(.semibold))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !hasStarted {
                if let scheduledMotivationMessage {
                    Label(scheduledMotivationMessage.body, systemImage: "bell.badge")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Responde trivia de opción múltiple con 15 segundos por pregunta. La partida termina en el primer error.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(isLoading ? "Cargando..." : "Iniciar entrenamiento") {
                    Task { await startSession() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            } else {
                HStack {
                    Label("Correctas: \(correctAnswers)", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Label("Fallos: \(incorrectAnswers)", systemImage: "xmark.seal.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let currentQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pregunta \(currentQuestionIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentQuestion.prompt)
                            .font(.headline)

                        if questionDeadline != nil {
                            Text("Tiempo restante: \(remainingSeconds)s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(remainingSeconds <= 3 ? .red : .secondary)
                        }

                        ForEach(Array(currentQuestion.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                Task { await answer(optionIndex: index) }
                            } label: {
                                HStack {
                                    Text(option)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if questionAnswered {
                                        if showCorrectAnswerIndicator {
                                            if index == correctOptionIndex {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                            } else if index == answeredOptionIndex {
                                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                            }
                                        } else if index == answeredOptionIndex {
                                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(questionAnswered || sessionCompleted || isLoading)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.footnote)
                        .foregroundStyle(feedbackColor)
                }

                HStack(spacing: 10) {
                    Button("Nueva sesión") {
                        Task { await startSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    if sessionCompleted || isGameOver {
                        Text(isGameOver ? "Game Over" : "Sesión finalizada")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isGameOver ? .red : .green)
                    }
                }
            }
        }
        .padding()
        .task {
            guard !hasScheduledMotivation else { return }
            hasScheduledMotivation = true
            guard AppPreferences.notificationsEnabled else { return }
            let message = await notificationService.scheduleMentalTrainingMotivation(on: Date(), streakDays: 0)
            await MainActor.run {
                scheduledMotivationMessage = message
            }
        }
        .alert(item: $trainerAlertStep) { step in
            switch step {
            case .loss:
                return Alert(
                    title: Text("Fin de la trivia"),
                    message: Text(lossAlertMessage),
                    dismissButton: .default(Text("Continuar")) {
                        dismiss()
                    }
                )
            }
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    private func startSession() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            feedbackMessage = nil
            isGameOver = false
            sessionCompleted = false
            questionAnswered = false
            showCorrectAnswerIndicator = false
            answeredOptionIndex = nil
            correctOptionIndex = nil
            trainerAlertStep = nil
            remainingSeconds = 0
        }
        countdownTask?.cancel()

        do {
            let session = try await mentalService.startSession(questionCount: 10)
            let question = await mentalService.currentQuestion()
            await MainActor.run {
                hasStarted = true
                isLoading = false
                currentQuestion = question
                totalQuestions = session.questions.count
                currentQuestionIndex = session.currentIndex
                questionDeadline = session.deadline
                remainingSeconds = max(Int(session.deadline.timeIntervalSinceNow.rounded(.up)), 0)
                correctAnswers = session.attempt.correctAnswers
                incorrectAnswers = session.attempt.incorrectAnswers
            }
            startCountdown(deadline: session.deadline)
        } catch {
            await MainActor.run {
                isLoading = false
                hasStarted = false
                errorMessage = "No se pudo iniciar la sesión: \(error.localizedDescription)"
            }
        }
    }

    private func answer(optionIndex: Int, answerDate: Date = Date()) async {
        guard !questionAnswered, !sessionCompleted, !isGameOver else { return }
        await MainActor.run {
            questionAnswered = true
            showCorrectAnswerIndicator = false
            answeredOptionIndex = optionIndex >= 0 ? optionIndex : nil
            isLoading = true
        }
        countdownTask?.cancel()

        guard let feedback = try? await mentalService.submitAnswer(optionIndex: optionIndex, answeredAt: answerDate) else {
            let session = await mentalService.activeSession
            let fallbackScore = session?.attempt.correctAnswers ?? correctAnswers
            await MainActor.run {
                isLoading = false
                isGameOver = true
                sessionCompleted = true
                questionAnswered = true
                feedbackMessage = "No se pudo continuar la trivia. Fin del intento."
                feedbackColor = .red
                questionDeadline = nil
                remainingSeconds = 0
            }
            await finalizeLossFlow(score: fallbackScore)
            return
        }

        let nextQuestion = await mentalService.currentQuestion()
        let session = await mentalService.activeSession

        await MainActor.run {
            correctAnswers = session?.attempt.correctAnswers ?? correctAnswers + (feedback.isCorrect ? 1 : 0)
            incorrectAnswers = session?.attempt.incorrectAnswers ?? incorrectAnswers + (feedback.isCorrect ? 0 : 1)
            currentQuestionIndex = session?.currentIndex ?? currentQuestionIndex + 1
            questionDeadline = session?.deadline
            remainingSeconds = max(Int((session?.deadline ?? Date()).timeIntervalSinceNow.rounded(.up)), 0)
            correctOptionIndex = nil

            if feedback.isCorrect {
                feedbackMessage = "¡Correcto!"
                feedbackColor = .green
            } else if feedback.isGameOver {
                feedbackMessage = "Respuesta incorrecta. Fin de la trivia."
                feedbackColor = .red
            } else {
                feedbackMessage = "Respuesta incorrecta."
                feedbackColor = .red
            }
        }

        guard await pauseForAnswerReveal() else { return }
        await MainActor.run {
            correctOptionIndex = feedback.correctOptionIndex
            showCorrectAnswerIndicator = true
        }
        guard await pauseForAnswerReveal() else { return }

        await MainActor.run {
            if feedback.isGameOver {
                isGameOver = true
                sessionCompleted = true
                isLoading = false
                questionDeadline = nil
                remainingSeconds = 0
                return
            }

            if let nextQuestion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.currentQuestion = nextQuestion
                    self.answeredOptionIndex = nil
                    self.correctOptionIndex = nil
                    self.showCorrectAnswerIndicator = false
                    self.questionAnswered = false
                    self.isLoading = false
                }
            } else {
                currentQuestion = nil
                sessionCompleted = true
                isLoading = false
                if feedbackMessage == nil {
                    feedbackMessage = "Sesión finalizada."
                    feedbackColor = .green
                }
            }
        }

        if feedback.isGameOver {
            await finalizeLossFlow(score: feedback.currentCorrectAnswers)
        } else if let deadline = session?.deadline {
            startCountdown(deadline: deadline)
        }
    }

    private func finalizeLossFlow(score: Int) async {
        let qualifiesForStreak = score >= MentalTrainerService.trainerScoreThresholdForDailyStreak
        if qualifiesForStreak {
            let today = Date()
            let todaysActivities = await agendaService.listActivities(on: today, calendar: calendar)
            if todaysActivities.isEmpty {
                _ = MentalTrainingStreakStore.registerDailyTrainerStreakIfNeeded(on: today, calendar: calendar)
            }
        }
        let bestScore = await mentalService.bestScore()
        await MainActor.run {
            lossAlertMessage = "Tu intento fue de \(score) aciertos. Tu mejor intento histórico es \(bestScore)."
            trainerAlertStep = .loss
        }
    }

    private func startCountdown(deadline: Date) {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                let seconds = max(Int(deadline.timeIntervalSinceNow.rounded(.up)), 0)
                remainingSeconds = seconds
                if seconds <= 0 {
                    answerTimeoutIfNeeded()
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // Must be a non-async @MainActor function so that it fires a NEW independent Task for
    // answer(). If it were async and awaited from countdownTask, answer() would cancel
    // countdownTask (its own parent), causing Task.sleep inside pauseForAnswerReveal() to
    // throw CancellationError and skip the Game Over flow entirely.
    @MainActor
    private func answerTimeoutIfNeeded() {
        guard hasStarted, !questionAnswered, !sessionCompleted, !isGameOver else { return }
        let forcedTimeoutDate = questionDeadline?.addingTimeInterval(0.001) ?? Date()
        Task { await answer(optionIndex: -1, answerDate: forcedTimeoutDate) }
    }

    private func pauseForAnswerReveal() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: answerRevealDelayNanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct AppSettingsView: View {
    private struct TimerSoundOption: Identifiable {
        let id: Int
        let title: String
    }

    private let timerSoundOptions: [TimerSoundOption] = [
        .init(id: 1000, title: "Sonido suave"),
        .init(id: 1001, title: "Sonido claro"),
        .init(id: 1002, title: "Sonido breve"),
        .init(id: 1003, title: "Sonido ligero"),
        .init(id: 1004, title: "Sonido clásico"),
        .init(id: 1005, title: "Sonido recomendado"),
        .init(id: 1006, title: "Sonido brillante"),
        .init(id: 1007, title: "Sonido limpio"),
        .init(id: 1008, title: "Sonido corto"),
        .init(id: 1009, title: "Sonido medio"),
        .init(id: 1010, title: "Sonido firme"),
        .init(id: 1011, title: "Sonido alerta"),
        .init(id: 1012, title: "Sonido campana"),
        .init(id: 1013, title: "Sonido timbre"),
        .init(id: 1014, title: "Sonido tono alto"),
        .init(id: 1015, title: "Sonido tono bajo"),
        .init(id: 1016, title: "Sonido relajado"),
        .init(id: 1020, title: "Sonido intenso")
    ]

    @State private var notificationsEnabled = AppPreferences.notificationsEnabled
    @State private var mentalTrainerSuggestionEnabled = AppPreferences.mentalTrainerSuggestionEnabled
    @State private var timerSoundEnabled = AppPreferences.timerSoundSystemID != nil
    @State private var timerSoundSystemIDText = "\(AppPreferences.timerSoundSystemID ?? AppPreferenceStore.defaultTimerSoundSystemID)"
    @State private var selectedTimerSoundID = AppPreferences.timerSoundSystemID ?? AppPreferenceStore.defaultTimerSoundSystemID
    @State private var timerSoundError: String?
    @State private var visualTheme = AppPreferences.visualTheme
    @State private var fontScale = AppPreferences.fontScale
    @State private var highContrastEnabled = AppPreferences.highContrastEnabled
    @State private var pomodoroWorkMinutes = AppPreferences.pomodoroWorkMinutes
    @State private var pomodoroBreakMinutes = AppPreferences.pomodoroBreakMinutes
    @State private var pomodoroLongBreakMinutes = AppPreferences.pomodoroLongBreakMinutes
    @State private var pomodoroCyclesBeforeLongBreak = AppPreferences.pomodoroCyclesBeforeLongBreak
    @State private var pomodoroAutoStartNextPhase = AppPreferences.pomodoroAutoStartNextPhase
    @State private var quietHoursEnabled = AppPreferences.quietHoursEnabled
    @State private var quietHoursStartHour = AppPreferences.quietHoursStartHour
    @State private var quietHoursEndHour = AppPreferences.quietHoursEndHour
    @State private var smartRemindersEnabled = AppPreferences.smartRemindersEnabled
    @State private var reminderStudyEnabled = AppPreferences.reminderStudyEnabled
    @State private var reminderTaskEnabled = AppPreferences.reminderTaskEnabled
    @State private var reminderOtherEnabled = AppPreferences.reminderOtherEnabled
    @State private var dailyGoalMinutes = AppPreferences.dailyGoalMinutes
    @State private var dailyGoalActivitiesCompleted = AppPreferences.dailyGoalActivitiesCompleted
    @State private var dailyGoalTrainerSessions = AppPreferences.dailyGoalTrainerSessions
    @State private var aiStoreConversationHistory = AppPreferences.aiStoreConversationHistory
    @State private var aiChatHistoryLimit = AppPreferences.aiChatHistoryLimit
    @State private var language = AppPreferences.language
    @State private var localeIdentifier = AppPreferences.localeIdentifier
    @State private var wellbeingActiveBreakEnabled = AppPreferences.wellbeingActiveBreakEnabled
    @State private var wellbeingHydrationEnabled = AppPreferences.wellbeingHydrationEnabled
    @State private var wellbeingEyeRestEnabled = AppPreferences.wellbeingEyeRestEnabled
    @State private var wellbeingReminderMinutes = AppPreferences.wellbeingReminderMinutes
    @State private var backupJSON: String?
    @State private var backupStatusMessage: String?
    @State private var isExporting = false
    private let agendaService = AgendaService(persistence: LocalAgendaDatabase())
    private let mentalService = MentalTrainerService()
    private let calendar = Calendar.current
    
    private var availableTimerSoundOptions: [TimerSoundOption] {
        if timerSoundOptions.contains(where: { $0.id == selectedTimerSoundID }) {
            return timerSoundOptions
        }
        return (timerSoundOptions + [.init(id: selectedTimerSoundID, title: "Sonido personalizado")])
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        Form {
            Section("Tema visual y accesibilidad") {
                Picker("Tema", selection: $visualTheme) {
                    Text("Sistema").tag(AppVisualTheme.system)
                    Text("Claro").tag(AppVisualTheme.light)
                    Text("Oscuro").tag(AppVisualTheme.dark)
                }
                .onChange(of: visualTheme) { _, value in
                    AppPreferences.visualTheme = value
                }

                Picker("Tamaño de letra", selection: $fontScale) {
                    Text("Pequeño").tag(AppFontScale.small)
                    Text("Normal").tag(AppFontScale.normal)
                    Text("Grande").tag(AppFontScale.large)
                    Text("Extra grande").tag(AppFontScale.extraLarge)
                }
                .onChange(of: fontScale) { _, value in
                    AppPreferences.fontScale = value
                }

                Toggle("Alto contraste", isOn: $highContrastEnabled)
                    .onChange(of: highContrastEnabled) { _, value in
                        AppPreferences.highContrastEnabled = value
                    }
            }

            Section("Pomodoro") {
                Toggle("Sonido del temporizador", isOn: $timerSoundEnabled)
                    .onChange(of: timerSoundEnabled) { _, isEnabled in
                        if !isEnabled {
                            AppPreferences.timerSoundSystemID = nil
                        } else if AppPreferences.timerSoundSystemID == nil {
                            AppPreferences.timerSoundSystemID = AppPreferenceStore.defaultTimerSoundSystemID
                            timerSoundSystemIDText = "\(AppPreferenceStore.defaultTimerSoundSystemID)"
                            selectedTimerSoundID = AppPreferenceStore.defaultTimerSoundSystemID
                        }
                    }

                TextField("ID de sonido del sistema iOS (ej. 1005)", text: $timerSoundSystemIDText)
                    .disabled(!timerSoundEnabled)
                
                Picker("Sonidos del sistema (scroll)", selection: $selectedTimerSoundID) {
                    ForEach(availableTimerSoundOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .disabled(!timerSoundEnabled)
                .onChange(of: selectedTimerSoundID) { _, soundID in
                    guard timerSoundEnabled else { return }
                    AppPreferences.timerSoundSystemID = soundID
                    timerSoundSystemIDText = "\(soundID)"
                    timerSoundError = nil
                }

                Button("Guardar sonido") {
                    guard timerSoundEnabled else {
                        timerSoundError = nil
                        return
                    }
                    guard let soundID = Int(timerSoundSystemIDText.trimmingCharacters(in: .whitespacesAndNewlines)), soundID > 0 else {
                        timerSoundError = "Ingresa un ID de sonido válido."
                        return
                    }
                    AppPreferences.timerSoundSystemID = soundID
                    selectedTimerSoundID = soundID
                    timerSoundError = nil
                }
                .disabled(!timerSoundEnabled)

                Button("Probar sonido") {
                    playConfiguredPomodoroSound()
                }
                .disabled(!timerSoundEnabled)

                Stepper("Trabajo: \(pomodoroWorkMinutes) min", value: $pomodoroWorkMinutes, in: 1...180)
                    .onChange(of: pomodoroWorkMinutes) { _, value in
                        AppPreferences.pomodoroWorkMinutes = value
                    }
                Stepper("Descanso corto: \(pomodoroBreakMinutes) min", value: $pomodoroBreakMinutes, in: 1...60)
                    .onChange(of: pomodoroBreakMinutes) { _, value in
                        AppPreferences.pomodoroBreakMinutes = value
                    }
                Stepper("Descanso largo: \(pomodoroLongBreakMinutes) min", value: $pomodoroLongBreakMinutes, in: 1...90)
                    .onChange(of: pomodoroLongBreakMinutes) { _, value in
                        AppPreferences.pomodoroLongBreakMinutes = value
                    }
                Stepper("Ciclos antes de descanso largo: \(pomodoroCyclesBeforeLongBreak)", value: $pomodoroCyclesBeforeLongBreak, in: 1...12)
                    .onChange(of: pomodoroCyclesBeforeLongBreak) { _, value in
                        AppPreferences.pomodoroCyclesBeforeLongBreak = value
                    }
                Toggle("Auto-iniciar siguiente fase", isOn: $pomodoroAutoStartNextPhase)
                    .onChange(of: pomodoroAutoStartNextPhase) { _, value in
                        AppPreferences.pomodoroAutoStartNextPhase = value
                    }

                if let timerSoundError {
                    Text(timerSoundError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Notificaciones") {
                Toggle("Activar notificaciones de la app", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, isEnabled in
                        AppPreferences.notificationsEnabled = isEnabled
                        #if canImport(UserNotifications)
                        if isEnabled {
                            requestPomodoroNotificationPermission()
                        } else {
                            let center = UNUserNotificationCenter.current()
                            center.removeAllPendingNotificationRequests()
                            center.removeAllDeliveredNotifications()
                        }
                        #endif
                    }

                Toggle("Horario silencioso", isOn: $quietHoursEnabled)
                    .onChange(of: quietHoursEnabled) { _, value in
                        AppPreferences.quietHoursEnabled = value
                    }
                Stepper("Desde: \(quietHoursStartHour):00", value: $quietHoursStartHour, in: 0...23)
                    .onChange(of: quietHoursStartHour) { _, value in
                        AppPreferences.quietHoursStartHour = value
                    }
                    .disabled(!quietHoursEnabled)
                Stepper("Hasta: \(quietHoursEndHour):00", value: $quietHoursEndHour, in: 0...23)
                    .onChange(of: quietHoursEndHour) { _, value in
                        AppPreferences.quietHoursEndHour = value
                    }
                    .disabled(!quietHoursEnabled)

                Toggle("Recordatorios inteligentes por tipo", isOn: $smartRemindersEnabled)
                    .onChange(of: smartRemindersEnabled) { _, value in
                        AppPreferences.smartRemindersEnabled = value
                    }
                Toggle("Recordatorios de estudio", isOn: $reminderStudyEnabled)
                    .onChange(of: reminderStudyEnabled) { _, value in
                        AppPreferences.reminderStudyEnabled = value
                    }
                    .disabled(!smartRemindersEnabled)
                Toggle("Recordatorios de tarea", isOn: $reminderTaskEnabled)
                    .onChange(of: reminderTaskEnabled) { _, value in
                        AppPreferences.reminderTaskEnabled = value
                    }
                    .disabled(!smartRemindersEnabled)
                Toggle("Recordatorios de otras actividades", isOn: $reminderOtherEnabled)
                    .onChange(of: reminderOtherEnabled) { _, value in
                        AppPreferences.reminderOtherEnabled = value
                    }
                    .disabled(!smartRemindersEnabled)
            }

            Section("Entrenador mental") {
                Toggle("Mostrar sugerencia al finalizar actividad", isOn: $mentalTrainerSuggestionEnabled)
                    .onChange(of: mentalTrainerSuggestionEnabled) { _, isEnabled in
                        AppPreferences.mentalTrainerSuggestionEnabled = isEnabled
                    }
            }

            Section("Objetivo diario") {
                Stepper("Minutos de enfoque: \(dailyGoalMinutes)", value: $dailyGoalMinutes, in: 1...720)
                    .onChange(of: dailyGoalMinutes) { _, value in
                        AppPreferences.dailyGoalMinutes = value
                    }
                Stepper("Actividades completadas: \(dailyGoalActivitiesCompleted)", value: $dailyGoalActivitiesCompleted, in: 1...30)
                    .onChange(of: dailyGoalActivitiesCompleted) { _, value in
                        AppPreferences.dailyGoalActivitiesCompleted = value
                    }
                Stepper("Sesiones trainer: \(dailyGoalTrainerSessions)", value: $dailyGoalTrainerSessions, in: 1...20)
                    .onChange(of: dailyGoalTrainerSessions) { _, value in
                        AppPreferences.dailyGoalTrainerSessions = value
                    }
            }

            Section("Respaldo y exportación") {
                Button(isExporting ? "Generando respaldo..." : "Generar respaldo JSON") {
                    Task { await generateBackupPayload() }
                }
                .disabled(isExporting)

                if let backupStatusMessage {
                    Text(backupStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let backupJSON {
                    TextEditor(text: .constant(backupJSON))
                        .font(.footnote.monospaced())
                        .frame(minHeight: 180)
                    Button("Copiar respaldo") {
                        copyBackupToClipboard(backupJSON)
                    }
                }
            }

            Section("Privacidad de IA") {
                Toggle("Guardar historial de chat local", isOn: $aiStoreConversationHistory)
                    .onChange(of: aiStoreConversationHistory) { _, value in
                        AppPreferences.aiStoreConversationHistory = value
                    }
                Stepper("Límite de mensajes en historial: \(aiChatHistoryLimit)", value: $aiChatHistoryLimit, in: 4...500)
                    .onChange(of: aiChatHistoryLimit) { _, value in
                        AppPreferences.aiChatHistoryLimit = value
                    }
                    .disabled(!aiStoreConversationHistory)
                Button("Limpiar historial de chat ahora", role: .destructive) {
                    NotificationCenter.default.post(name: .aiChatHistoryCleared, object: nil)
                }
            }

            Section("Idioma y formato regional") {
                Picker("Idioma", selection: $language) {
                    Text("Español").tag(AppLanguage.spanish)
                    Text("English").tag(AppLanguage.english)
                }
                .onChange(of: language) { _, value in
                    AppPreferences.language = value
                }

                TextField("Locale ID (ej. es_MX, en_US)", text: $localeIdentifier)
                    .onSubmit {
                        AppPreferences.localeIdentifier = localeIdentifier
                        localeIdentifier = AppPreferences.localeIdentifier
                    }
            }

            Section("Descanso y bienestar") {
                Toggle("Pausas activas", isOn: $wellbeingActiveBreakEnabled)
                    .onChange(of: wellbeingActiveBreakEnabled) { _, value in
                        AppPreferences.wellbeingActiveBreakEnabled = value
                    }
                Toggle("Recordatorio de hidratación", isOn: $wellbeingHydrationEnabled)
                    .onChange(of: wellbeingHydrationEnabled) { _, value in
                        AppPreferences.wellbeingHydrationEnabled = value
                    }
                Toggle("Descanso visual", isOn: $wellbeingEyeRestEnabled)
                    .onChange(of: wellbeingEyeRestEnabled) { _, value in
                        AppPreferences.wellbeingEyeRestEnabled = value
                    }
                Stepper("Intervalo de bienestar: \(wellbeingReminderMinutes) min", value: $wellbeingReminderMinutes, in: 5...240)
                    .onChange(of: wellbeingReminderMinutes) { _, value in
                        AppPreferences.wellbeingReminderMinutes = value
                    }
            }
        }
        .navigationTitle("Ajustes")
    }

    private func generateBackupPayload() async {
        guard !isExporting else { return }
        await MainActor.run {
            isExporting = true
            backupStatusMessage = nil
        }
        let now = Date()
        let todayActivities = await agendaService.listActivities(on: now, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrowActivities = await agendaService.listActivities(on: tomorrow, calendar: calendar)
        let streakDays = await StreakComputation.days(endingOn: now, agendaService: agendaService, calendar: calendar)
        let trainerBest = await mentalService.bestScore()
        let payload = SettingsBackupPayload(
            exportedAt: now,
            preferences: AppPreferences.values(),
            todayActivities: todayActivities,
            tomorrowActivities: tomorrowActivities,
            streakDays: streakDays,
            trainerBestScore: trainerBest
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(payload)
        let output = data.flatMap { String(data: $0, encoding: .utf8) }
        await MainActor.run {
            backupJSON = output
            backupStatusMessage = output == nil ? "No se pudo generar el respaldo." : "Respaldo generado."
            isExporting = false
        }
    }

    private func copyBackupToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        backupStatusMessage = "Respaldo copiado al portapapeles."
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        backupStatusMessage = "Respaldo copiado al portapapeles."
        #else
        backupStatusMessage = "Copia manualmente el contenido del respaldo."
        #endif
    }
}

private struct SettingsBackupPayload: Codable, Sendable {
    let exportedAt: Date
    let preferences: AppPreferenceValues
    let todayActivities: [Activity]
    let tomorrowActivities: [Activity]
    let streakDays: Int
    let trainerBestScore: Int
}

private enum MentalTrainingStreakStore {
    private static let keyPrefix = "mental-training-completions-"
    private static let trainerDailyStreakPrefix = "mental-training-trainer-streak-"

    static func registerCompletion(on day: Date, calendar: Calendar = .current) {
        let key = keyForDay(day, calendar: calendar)
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    static func completionCount(on day: Date, calendar: Calendar = .current) -> Int {
        UserDefaults.standard.integer(forKey: keyForDay(day, calendar: calendar))
    }

    @discardableResult
    static func registerDailyTrainerStreakIfNeeded(on day: Date, calendar: Calendar = .current) -> Bool {
        let key = trainerDailyStreakKeyForDay(day, calendar: calendar)
        if UserDefaults.standard.bool(forKey: key) { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    static func hasDailyTrainerStreak(on day: Date, calendar: Calendar = .current) -> Bool {
        UserDefaults.standard.bool(forKey: trainerDailyStreakKeyForDay(day, calendar: calendar))
    }

    private static func keyForDay(_ day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let date = components.day ?? 0
        return keyPrefix + String(format: "%04d-%02d-%02d", year, month, date)
    }

    private static func trainerDailyStreakKeyForDay(_ day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let date = components.day ?? 0
        return trainerDailyStreakPrefix + String(format: "%04d-%02d-%02d", year, month, date)
    }
}

private enum StreakComputation {
    // Compatibilidad con sesiones históricas: 5 completadas en un día sin agenda también
    // califican como día válido de racha aunque ahora exista el criterio por score del trainer.
    private static let mentalTrainingCompletionThreshold = 5

    static func days(endingOn day: Date, agendaService: AgendaService, calendar: Calendar) async -> Int {
        var count = 0
        var cursor = calendar.startOfDay(for: day)
        for _ in 0..<365 {
            let reason = await validationReason(for: cursor, agendaService: agendaService, calendar: calendar)
            guard reason != .incompleteDay else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func validationReason(for day: Date, agendaService: AgendaService, calendar: Calendar) async -> StreakValidationReason {
        let activities = await agendaService.listActivities(on: day, calendar: calendar)
        if !activities.isEmpty {
            return activities.allSatisfy { $0.status == .completed }
                ? .allScheduledActivitiesCompleted
                : .incompleteDay
        }
        let hasStreakQualification = MentalTrainingStreakStore.hasDailyTrainerStreak(on: day, calendar: calendar)
            || MentalTrainingStreakStore.completionCount(on: day, calendar: calendar) >= mentalTrainingCompletionThreshold
        return hasStreakQualification
            ? .mentalTrainingOnNoAgendaDay
            : .incompleteDay
    }
}

private enum TrainerAlertStep: String, Identifiable {
    case loss

    var id: String { rawValue }
}
#endif
