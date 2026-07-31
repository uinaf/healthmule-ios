import SwiftUI

@main
struct HealthMuleWatchApp: App {
    @State private var model = CompanionAppModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CompanionStatusView(model: model)
            }
            .tint(Color.secondary)
        }
    }
}
