import SwiftUI

struct AppRootView: View {
    @Bindable var model: AppModel
    @State private var path: [HomeRoute]

    init(model: AppModel) {
        self.model = model
        let arguments = ProcessInfo.processInfo.arguments
        let initialRoute: HomeRoute? = if arguments.contains("--ui-show-metrics") {
            .metrics
        } else if arguments.contains("--ui-show-advanced") {
            .advanced
        } else {
            nil
        }
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(model: model)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .metrics:
                        MetricsView(model: model)
                    case .advanced:
                        AdvancedView(model: model)
                    }
                }
        }
    }
}

#Preview {
    AppRootView(model: .live())
}
