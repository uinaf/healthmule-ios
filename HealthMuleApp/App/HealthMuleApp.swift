import GoogleSignIn
import SwiftUI

@main
struct HealthMuleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
                .preferredColorScheme(
                    ProcessInfo.processInfo.arguments.contains("--ui-dark-mode")
                        ? .dark
                        : nil
                )
                .environment(
                    \.dynamicTypeSize,
                    ProcessInfo.processInfo.arguments.contains(
                        "--ui-accessibility-text"
                    )
                        ? .accessibility3
                        : dynamicTypeSize
                )
                .task {
                    await model.bootstrap()
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.applicationDidBecomeActive()
                    }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefreshCoordinator.identifier)) {
            await model.performBackgroundRefresh()
        }
        .backgroundTask(
            .urlSession(BackgroundDriveUploadTransport.sessionIdentifier)
        ) {
            guard
                await BackgroundDriveUploadTransport.shared
                    .handleDeliveredBackgroundEvents()
            else {
                return
            }
            await model.performBackgroundRefresh()
        }
    }
}
