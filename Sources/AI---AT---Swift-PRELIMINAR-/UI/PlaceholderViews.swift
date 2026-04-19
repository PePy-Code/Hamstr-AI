#if canImport(SwiftUI)
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

public struct HomeView: View {
    @State private var todayActivities: [Activity] = []
    @State private var tomorrowActivities: [Activity] = []
    @State private var streakState = StreakState()
    @State private var hasLoaded = false
    @State private var pendingStartActivity: Activity?
    @State private var activeActivity: Activity?
    @State private var editingActivity: Activity?
    @State private var suppressTapForActivityID: UUID?
    @State private var openWeeklyAgenda = false
    @State private var showQuickAddActivity = false
    private let agendaService = AgendaService(persistence: LocalAgendaDatabase())
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

                    HStack(alignment: .top, spacing: 10) {
                        Text("🐭")
                            .font(.largeTitle)
                        Text(petSupportMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

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
            .onAppear {
                Task { await refreshSummary() }
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
                    onDidSave: {
                        Task { await refreshSummary() }
                    }
                )
            }
            .navigationDestination(isPresented: $openWeeklyAgenda) {
                WeeklyAgendaView(agendaService: agendaService)
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
                    agendaCell(for: activityAt(hour: hour, in: todayActivities))
                    agendaCell(for: activityAt(hour: hour, in: tomorrowActivities))
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func agendaCell(for activity: Activity?) -> some View {
        if let activity {
            Button {
                if suppressTapForActivityID == activity.id {
                    suppressTapForActivityID = nil
                    return
                }
                pendingStartActivity = activity
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: activity.status))
                        .frame(width: 8, height: 8)
                    Text(activity.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .background(statusColor(for: activity.status).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0.5) {
                suppressTapForActivityID = activity.id
                editingActivity = activity
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
        await MainActor.run {
            self.todayActivities = activities
            self.tomorrowActivities = tomorrowItems
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

    private func activityAt(hour: Int, in activities: [Activity]) -> Activity? {
        activities
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first { calendar.component(.hour, from: $0.scheduledAt) == hour }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }

    private var petSupportMessage: String {
        if streakState.days >= 7 {
            return "¡Lo estás haciendo genial! Tu constancia está dando resultados."
        }
        if todayActivities.isEmpty {
            return "Hoy puedes avanzar un poco con una actividad corta para mantener el ritmo."
        }
        return "Paso a paso: inicia una actividad y enfócate unos minutos."
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
    @State private var shouldShowStreakPopup = false
    @State private var isFinishing = false
    @State private var pomodoroTransitionAlert: PomodoroTransitionAlert?
    @State private var remainingSeconds = 25 * 60
    @State private var isRunning = true
    @State private var isWorkPhase = true
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
            } else {
                isWorkPhase.toggle()
                remainingSeconds = isWorkPhase ? 25 * 60 : 5 * 60
                isRunning = true
                pomodoroTransitionAlert = PomodoroTransitionAlert(
                    message: isWorkPhase
                        ? "Descanso finalizado. Inicia un nuevo bloque de trabajo."
                        : "Trabajo finalizado. Inicia tu descanso corto."
                )
                playPomodoroTransitionSound()
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
                        finishAlertStep = .mentalTrainingPrompt
                    }
                )
            case .mentalTrainingPrompt:
                return Alert(
                    title: Text("🐭 Entrenamiento mental"),
                    message: Text("¿Te gustaría hacer un entrenamiento mental?"),
                    primaryButton: .default(Text("Sí")) {
                        if shouldShowStreakPopup {
                            navigateToTrainerAfterStreak = true
                            finishAlertStep = .streak
                        } else {
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
        #if canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task { await handleImageAttachment(item: newValue) }
        }
        #endif
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

            HStack(spacing: 10) {
                Button(isRunning ? "Pausar" : "Iniciar") {
                    isRunning.toggle()
                }
                .buttonStyle(.bordered)

                Button("Reiniciar") {
                    isRunning = false
                    isWorkPhase = true
                    remainingSeconds = 25 * 60
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asistente 🐭")
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

                TextField("Escribe al chatbot...", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Enviar") {
                    Task { await sendUserMessage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("La IA responde preguntas, explica conceptos y sugiere fuentes abiertas.")
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
            Text(message.text)
                .font(.footnote)
        }
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func startSessionAndSeedChat() async {
        _ = try? await agendaService.startActivity(id: activity.id)
        await MainActor.run {
            messages = []
        }
    }

    private func sendUserMessage() async {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        await MainActor.run {
            messages.append(ActivityChatMessage(role: .user, text: text))
            userInput = ""
        }

        let response = await assistantResponse(for: text)
        await MainActor.run {
            messages.append(ActivityChatMessage(role: .assistant, text: response))
        }
    }

    private func assistantResponse(for text: String) async -> String {
        let modelReply = (try? await intelligence.chatReply(
            userMessage: text,
            activityTitle: activity.title,
            topic: normalizedTopic,
            type: activity.type
        )) ?? ""
        let cleaned = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Cuéntame más detalle de lo que necesitas y te respondo de forma concreta."
        }
        return cleaned
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
            messages.append(ActivityChatMessage(role: .user, text: "Compartí una imagen (\(sizeText)) para revisión.", isImageAttachment: true))
        }
        let supportContext = [activity.title, normalizedTopic]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let support = (try? await intelligence.supportMaterial(for: supportContext, type: activity.type)) ?? []
        let bulletText = support.isEmpty ? "" : "\n" + support.map { "• \($0)" }.joined(separator: "\n")
        await MainActor.run {
            messages.append(
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
            messages.append(ActivityChatMessage(role: .user, text: "Compartí una imagen para revisión.", isImageAttachment: true))
            messages.append(ActivityChatMessage(role: .assistant, text: "Recibí tu imagen. Puedo darte retroalimentación y fuentes para mejorar tu actividad."))
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

    private func playPomodoroTransitionSound() {
        #if canImport(AudioToolbox)
        AudioServicesPlaySystemSound(1005)
        #endif
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
    let onDidSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var topic: String
    @State private var typeRawValue: String
    @State private var scheduledAt: Date

    init(
        agendaService: AgendaService,
        activity: Activity,
        onDidSave: @escaping () -> Void
    ) {
        self.agendaService = agendaService
        self.activity = activity
        self.onDidSave = onDidSave
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
                }
            }
            .navigationTitle("Editar actividad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
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
        _ = await agendaService.updateActivity(updated)
        await MainActor.run {
            onDidSave()
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

private struct WeeklyAgendaView: View {
    let agendaService: AgendaService

    @State private var weekStart: Date
    @State private var weekActivities: [Activity] = []
    @State private var showAddActivity = false
    @State private var editingActivity: Activity?
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
                                            ForEach(activities.prefix(2)) { activity in
                                                Text("\(activity.title) • \(statusLabel(for: activity.status))")
                                                    .lineLimit(1)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(statusColor(for: activity.status).opacity(0.2))
                                                    .foregroundStyle(statusColor(for: activity.status))
                                                    .clipShape(Capsule())
                                                    .contentShape(Rectangle())
                                                    .onLongPressGesture(minimumDuration: 0.5) {
                                                        editingActivity = activity
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
                onDidSave: {
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
        .sorted { $0.scheduledAt < $1.scheduledAt }
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
                    initialSeconds: 25 * 60,
                    onTimerScheduled: { remainingSeconds in
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
                onTimerFinished?()
            }
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

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = max(totalSeconds, 0) / 60
        let seconds = max(totalSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public struct MentalTrainerView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasStarted = false
    @State private var currentQuestion: TriviaQuestion?
    @State private var correctAnswers = 0
    @State private var incorrectAnswers = 0
    @State private var currentQuestionIndex = 0
    @State private var totalQuestions = 0
    @State private var questionDeadline: Date?
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .secondary
    @State private var isGameOver = false
    @State private var sessionCompleted = false
    @State private var questionAnswered = false
    @State private var answeredOptionIndex: Int?
    @State private var correctOptionIndex: Int?
    @State private var hasScheduledMotivation = false
    @State private var scheduledMotivationMessage: NotificationMessage?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let mentalService = MentalTrainerService()
    private let notificationService = AppNotifications.service

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
                Text("Responde trivia con 10 segundos por pregunta. Si fallas después de 5 aciertos, termina la partida.")
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
                        Text("Pregunta \(currentQuestionIndex + 1) de \(max(totalQuestions, 1))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentQuestion.prompt)
                            .font(.headline)

                        if let deadline = questionDeadline {
                            Text("Tiempo restante: \(remainingSeconds(until: deadline))s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(remainingSeconds(until: deadline) <= 3 ? .red : .secondary)
                        }

                        ForEach(Array(currentQuestion.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                Task { await answer(optionIndex: index) }
                            } label: {
                                HStack {
                                    Text(option)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if questionAnswered {
                                        if index == correctOptionIndex {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        } else if index == answeredOptionIndex {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
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
        .onReceive(ticker) { _ in
            guard hasStarted, !questionAnswered, !sessionCompleted, !isGameOver,
                  let deadline = questionDeadline else { return }
            if Date() >= deadline {
                Task { await answer(optionIndex: -1, answerDate: Date()) }
            }
        }
        .task {
            guard !hasScheduledMotivation else { return }
            hasScheduledMotivation = true
            let message = await notificationService.scheduleMentalTrainingMotivation(on: Date(), streakDays: 0)
            await MainActor.run {
                scheduledMotivationMessage = message
            }
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
            answeredOptionIndex = nil
            correctOptionIndex = nil
        }

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
                correctAnswers = session.attempt.correctAnswers
                incorrectAnswers = session.attempt.incorrectAnswers
            }
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
            answeredOptionIndex = optionIndex >= 0 ? optionIndex : nil
            isLoading = true
        }

        guard let feedback = await mentalService.submitAnswer(optionIndex: optionIndex, answeredAt: answerDate) else {
            await MainActor.run {
                isLoading = false
                questionAnswered = false
            }
            return
        }

        let nextQuestion = await mentalService.currentQuestion()
        let session = await mentalService.activeSession

        await MainActor.run {
            correctOptionIndex = feedback.correctOptionIndex
            correctAnswers = session?.attempt.correctAnswers ?? correctAnswers + (feedback.isCorrect ? 1 : 0)
            incorrectAnswers = session?.attempt.incorrectAnswers ?? incorrectAnswers + (feedback.isCorrect ? 0 : 1)
            currentQuestionIndex = session?.currentIndex ?? currentQuestionIndex + 1
            questionDeadline = session?.deadline

            if feedback.isCorrect {
                feedbackMessage = "¡Correcto!"
                feedbackColor = .green
            } else if feedback.shouldShowRetry {
                feedbackMessage = "Incorrecto. Sigue intentando."
                feedbackColor = .orange
            } else if feedback.isGameOver {
                feedbackMessage = "Perdiste después de 5 aciertos. Game Over."
                feedbackColor = .red
            } else {
                feedbackMessage = "Respuesta incorrecta."
                feedbackColor = .red
            }

            if feedback.isGameOver {
                isGameOver = true
                sessionCompleted = true
                isLoading = false
                if correctAnswers >= 5 {
                    MentalTrainingStreakStore.registerCompletion(on: Date())
                }
                return
            }

            if let nextQuestion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.currentQuestion = nextQuestion
                    self.answeredOptionIndex = nil
                    self.correctOptionIndex = nil
                    self.questionAnswered = false
                    self.isLoading = false
                }
            } else {
                currentQuestion = nil
                sessionCompleted = true
                isLoading = false
                if correctAnswers >= 5 {
                    MentalTrainingStreakStore.registerCompletion(on: Date())
                }
                if feedbackMessage == nil {
                    feedbackMessage = "Sesión finalizada."
                    feedbackColor = .green
                }
            }
        }
    }

    private func remainingSeconds(until deadline: Date) -> Int {
        max(Int(deadline.timeIntervalSinceNow.rounded(.down)), 0)
    }
}

private enum MentalTrainingStreakStore {
    private static let keyPrefix = "mental-training-completions-"

    static func registerCompletion(on day: Date, calendar: Calendar = .current) {
        let key = keyForDay(day, calendar: calendar)
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    static func completionCount(on day: Date, calendar: Calendar = .current) -> Int {
        UserDefaults.standard.integer(forKey: keyForDay(day, calendar: calendar))
    }

    private static func keyForDay(_ day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let date = components.day ?? 0
        return keyPrefix + String(format: "%04d-%02d-%02d", year, month, date)
    }
}

private enum StreakComputation {
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
        return MentalTrainingStreakStore.completionCount(on: day, calendar: calendar) >= 5
            ? .mentalTrainingOnNoAgendaDay
            : .incompleteDay
    }
}
#endif
