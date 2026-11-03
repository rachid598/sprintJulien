import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("--uitesting"))
            container = try ModelContainer(for: StoredRace.self, configurations: configuration)
            startupError = nil
        } catch { container = nil; startupError = error.localizedDescription }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                HomeView().modelContainer(container).tint(.orange)
            } else {
                ContentUnavailableView("Historique indisponible", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Les données n’ont pas été effacées. Redémarrez l’application. \(startupError ?? "")"))
            }
        }
    }
}
