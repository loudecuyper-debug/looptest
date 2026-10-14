import SwiftUI

@main
struct LoopTestApp: App {
    @StateObject private var session = RunSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}
