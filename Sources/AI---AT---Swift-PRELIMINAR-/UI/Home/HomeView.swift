#if canImport(SwiftUI)
import SwiftUI

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

    private let dependencies: UIDependencyContainer
    private let calendar: Calendar
    private let presentationModel: HomePresentationModel

    private var agendaService: AgendaService { dependencies.agendaService }

    public init(
        dependencies: UIDependencyContainer = UIDependencyContainer.makeDefault(),
        calendar: Calendar = .current
    ) {
        self.dependencies = dependencies
        self.calendar = calendar
        self.presentationModel = HomePresentationModel(
            agendaService: dependencies.agendaService,
            intelligence: dependencies.intelligenceService,
            calendar: calendar
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UIDesignTokens.Spacing.screen) {
                    HStack {
                        HStack(spacing: UIDesignTokens.Spacing.compact) {
                            Text("🔥")
                            Text("Racha")
                                .fontWeight(.semibold)
                            Text("\(streakState.days) días")
                                .font(.subheadline.weight(.bold))
                        }
                        Spacer()
                        NavigationLink {
                            MentalTrainerView(dependencies: dependencies)
                        } label: {
                            Label("Trainer", systemImage: "brain.head.profile")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: UIDesignTokens.Radius.card))

                    dailyGoalsCard

                    Button {
                        openPersonalChatbot = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("🐭")
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Roedor")
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
                        .clipShape(RoundedRectangle(cornerRadius: UIDesignTokens.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: UIDesignTokens.Radius.card)
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
        VStack(alignment: .leading, spacing: UIDesignTokens.Spacing.compact) {
            Text("Agenda")
                .font(.headline)
            HStack(spacing: UIDesignTokens.Spacing.compact) {
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
                HStack(spacing: UIDesignTokens.Spacing.compact) {
                    Button(action: { openWeeklyAgenda = true }) {
                        Text(String(format: "%02d:00", hour))
                            .font(.caption.monospacedDigit())
                            .frame(width: 60, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    agendaCell(for: presentationModel.activitiesAt(hour: hour, in: todayActivities))
                    agendaCell(for: presentationModel.activitiesAt(hour: hour, in: tomorrowActivities))
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: UIDesignTokens.Radius.card))
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
        .clipShape(RoundedRectangle(cornerRadius: UIDesignTokens.Radius.card))
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
                            .clipShape(RoundedRectangle(cornerRadius: UIDesignTokens.Radius.element))
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
        let snapshot = await presentationModel.refreshSummary(now: Date())
        await MainActor.run {
            todayActivities = snapshot.todayActivities
            tomorrowActivities = snapshot.tomorrowActivities
            aiPetSupportMessage = snapshot.petMessage
            streakState = snapshot.streakState
        }
    }

    private func seedInitialActivitiesIfNeeded() async {
        await presentationModel.seedInitialActivitiesIfNeeded(now: Date())
    }

    private var nextDay: Date {
        presentationModel.nextDay(from: Date())
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
        HomePresentationModel.displayedPetSupportMessage(
            generatedMessage: aiPetSupportMessage,
            streakState: streakState,
            todayActivities: todayActivities
        )
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
#endif
