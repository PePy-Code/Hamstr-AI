import Foundation

#if canImport(SwiftUI)
import SwiftUI
import AI___AT___Swift_PRELIMINAR_

@main
struct AcademicTrainerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
#else
@main
struct AcademicTrainerCLIEntryPoint {
    static func main() {
        print("AcademicTrainerApp está diseñado para ejecutarse en plataformas con SwiftUI (iOS/macOS).")
    }
}
#endif
