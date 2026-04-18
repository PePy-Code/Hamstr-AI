#if canImport(SwiftUI)
import SwiftUI

public struct HomeView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                NavigationLink("Agenda") { AgendaView() }
                NavigationLink("Entrenador Mental") { MentalTrainerView() }
                Label("Racha actual", systemImage: "flame.fill")
            }
            .navigationTitle("Entrenador Académico")
        }
    }
}

public struct AgendaView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Agenda")
                .font(.title2)
            Text("UI simple y reemplazable para tareas, estudio y otros.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PomodoroTimerView(
                title: "Pomodoro activo",
                secondsRemaining: 25 * 60,
                onMarkCompleted: {},
                onMarkPending: {}
            )
        }
        .padding()
    }
}

public struct PomodoroTimerView: View {
    public let title: String
    public let secondsRemaining: Int
    public let onMarkCompleted: () -> Void
    public let onMarkPending: () -> Void

    public init(
        title: String,
        secondsRemaining: Int,
        onMarkCompleted: @escaping () -> Void,
        onMarkPending: @escaping () -> Void
    ) {
        self.title = title
        self.secondsRemaining = secondsRemaining
        self.onMarkCompleted = onMarkCompleted
        self.onMarkPending = onMarkPending
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text(formattedTime(secondsRemaining))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Marcar realizada", action: onMarkCompleted)
                    .buttonStyle(.borderedProminent)
                Button("Dejar pendiente", action: onMarkPending)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = max(totalSeconds, 0) / 60
        let seconds = max(totalSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public struct MentalTrainerView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Entrenador Mental")
                .font(.title2)
            Text("UI simple y reemplazable para trivia de 10 segundos por pregunta.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
#endif
