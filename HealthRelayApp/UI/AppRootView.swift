import SwiftUI

enum HomeRoute: Hashable {
    case setup
    case sync
    case metrics
}

struct AppRootView: View {
    @Bindable var model: AppModel
    @State private var homePath: [HomeRoute] = []

    init(model: AppModel) {
        self.model = model
        let arguments = ProcessInfo.processInfo.arguments
        let initialRoute: HomeRoute?
        if arguments.contains("--ui-show-setup") {
            initialRoute = .setup
        } else if arguments.contains("--ui-show-sync") {
            initialRoute = .sync
        } else if arguments.contains("--ui-show-metrics") {
            initialRoute = .metrics
        } else {
            initialRoute = nil
        }
        _homePath = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack(path: $homePath) {
                StatusView(model: model)
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .setup:
                            SetupView(model: model)
                        case .sync:
                            SyncView(model: model)
                        case .metrics:
                            MetricsView(model: model)
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "heart.text.clipboard")
            }
            .tag(AppTab.home)

            NavigationStack {
                SettingsView(model: model)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.accentColor)
    }
}

#Preview {
    AppRootView(model: .live())
}
