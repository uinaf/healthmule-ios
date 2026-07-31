import SwiftUI

struct StatusView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                OperationBanner(state: model.operationState)
                backgroundDeliveryAdvisory

                if shouldShowSummary {
                    VStack(spacing: 12) {
                        SectionHeading(
                            title: "Sync summary",
                            subtitle: "Your local export queue at a glance."
                        )
                        NavigationLink(value: HomeRoute.sync) {
                            summaryCard
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 12) {
                    SectionHeading(
                        title: "Connections",
                        subtitle: "Both sources stay under your control."
                    )
                    connectionCards
                }

                VStack(spacing: 12) {
                    SectionHeading(
                        title: "Health data",
                        subtitle: metricSummarySubtitle
                    )
                    NavigationLink(value: HomeRoute.metrics) {
                        metricSummaryCard
                    }
                    .buttonStyle(.plain)
                }

                privacyNote
            }
            .frame(maxWidth: HealthRelayStyle.contentWidth)
            .padding(.horizontal, HealthRelayStyle.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(HealthRelayStyle.canvas)
        .navigationTitle("Health Mule")
        .navigationBarTitleDisplayMode(
            dynamicTypeSize.isAccessibilitySize ? .inline : .large
        )
        .accessibilityIdentifier("home-screen")
        .refreshable {
            await model.applicationDidBecomeActive()
        }
    }

    @ViewBuilder
    private var backgroundDeliveryAdvisory: some View {
        if let advisory = model.backgroundDeliveryAdvisory {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    advisory.title,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatusTone.warning.color)

                Text(advisory.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Check Again") {
                    Task {
                        await model.retryHealthStatus()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.operationState.isWorking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .healthRelayCard(padding: 14)
            .accessibilityIdentifier("background-delivery-advisory")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBadge(
                title: heroPresentation.badge,
                tone: heroPresentation.tone
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(heroPresentation.title)
                    .font(.title2.weight(.semibold))
                Text(heroPresentation.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            heroAction
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            HealthRelayStyle.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HealthRelayStyle.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var heroAction: some View {
        switch heroPresentation.action {
        case .none:
            EmptyView()
        case .setup(let title):
            NavigationLink(value: HomeRoute.setup) {
                Label(title, systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HealthRelayStyle.tint)
            .controlSize(.large)
            .accessibilityIdentifier("open-setup-action")
        case .sync:
            Button {
                Task {
                    await model.reconcile(trigger: .manual)
                }
            } label: {
                Label(
                    model.operationState.isWorking(.sync) ? "Syncing" : "Sync now",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HealthRelayStyle.tint)
            .controlSize(.large)
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("home-sync-action")
        case .retry:
            Button {
                Task {
                    await model.retryFailedUploads()
                }
            } label: {
                Label(
                    "Retry uploads",
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HealthRelayStyle.tint)
            .controlSize(.large)
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("home-retry-action")
        }
    }

    private var connectionCards: some View {
        VStack(spacing: 0) {
            healthConnectionCard
            Divider()
                .padding(.leading, 52)
            googleConnectionCard
        }
        .healthRelayCard(padding: 0)
    }

    private var healthConnectionCard: some View {
        NavigationLink(value: HomeRoute.setup) {
            ConnectionCard(
                title: "Apple Health",
                detail: healthConnectionDetail,
                systemImage: "heart.fill",
                badge: healthConnectionBadge,
                tone: healthConnectionTone
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("health-connection-card")
    }

    private var googleConnectionCard: some View {
        NavigationLink(value: HomeRoute.setup) {
            ConnectionCard(
                title: "Google Drive",
                detail: googleConnectionDetail,
                systemImage: "externaldrive.fill",
                badge: googleConnectionBadge,
                tone: googleConnectionTone
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("google-connection-card")
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sync details")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if dynamicTypeSize > .large {
                VStack(spacing: 14) {
                    summaryValue(
                        "Last sync",
                        value: lastSyncValue
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    summaryValue(
                        "Latest day",
                        value: model.syncSummary.latestExportedDate ?? "None"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    summaryValue(
                        "Pending",
                        value: model.syncSummary.pendingUploadCount.formatted()
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    summaryValue(
                        "Last sync",
                        value: compactLastSyncValue,
                        accessibilityValue: lastSyncValue,
                        staysOnOneLine: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 10)
                    Divider()
                    summaryValue(
                        "Latest day",
                        value: compactLatestDayValue,
                        accessibilityValue:
                            model.syncSummary.latestExportedDate ?? "None",
                        staysOnOneLine: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    Divider()
                    summaryValue(
                        "Pending",
                        value: model.syncSummary.pendingUploadCount.formatted(),
                        staysOnOneLine: true
                    )
                    .frame(width: 48, alignment: .leading)
                    .padding(.leading, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .healthRelayCard(padding: 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens sync details.")
    }

    private var metricSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(metricSummaryTitle)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(metricSummaryDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .healthRelayCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health data")
        .accessibilityValue(metricSummarySubtitle)
        .accessibilityHint("Opens per-metric status.")
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                "Only normalized daily records go to your own Drive. Health values and OAuth tokens never enter diagnostics."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func summaryValue(
        _ label: String,
        value: String,
        accessibilityValue: String? = nil,
        staysOnOneLine: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(staysOnOneLine ? 1 : nil)
                .minimumScaleFactor(staysOnOneLine ? 0.82 : 1)
                .allowsTightening(staysOnOneLine)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? value)
    }

    private var isReady: Bool {
        model.syncReadiness.canSync
    }

    private var shouldShowSummary: Bool {
        isReady
            || model.syncSummary.lastSuccessfulSyncAt != nil
            || model.syncSummary.latestExportedDate != nil
            || model.syncSummary.pendingUploadCount > 0
    }

    private var readableMetricCount: Int {
        model.metricStatuses.readableMetricCount
    }

    private var includedMetricCount: Int {
        model.metricStatuses.includedMetricCount
    }

    private var metricSummarySubtitle: String {
        switch model.healthAuthorizationState {
        case .unavailable:
            return "Apple Health is unavailable on this device."
        case .checking:
            return "Checking which selected types currently expose samples."
        case .statusUnavailable(let previouslyRequested):
            if previouslyRequested {
                return "\(readableMetricCount) types currently expose samples; the Health request status could not be refreshed."
            }
            return "The Apple Health request status could not be checked."
        case .notRequested:
            return "\(includedMetricCount) read-only types ready to request."
        case .reviewRequired:
            return "\(readableMetricCount) types currently expose samples; Apple says the request needs review."
        case .requestCompleted:
            return "\(readableMetricCount) types currently expose samples."
        }
    }

    private var metricSummaryTitle: String {
        switch model.healthAuthorizationState {
        case .unavailable:
            "Health data unavailable"
        case .checking:
            "Checking Health data"
        case .statusUnavailable:
            "Health status unavailable"
        case .notRequested:
            "\(includedMetricCount) read-only data types"
        case .reviewRequired, .requestCompleted:
            "\(readableMetricCount) "
                + (readableMetricCount == 1
                    ? "type has visible data"
                    : "types have visible data")
        }
    }

    private var metricSummaryDetail: String {
        switch model.healthAuthorizationState {
        case .unavailable:
            "Apple Health can be read only on a supported iPhone."
        case .checking:
            "Readable sample status will appear after this check finishes."
        case .statusUnavailable:
            "Try the Health status check again from Setup."
        case .notRequested:
            "Apple keeps every read choice private from the app."
        case .reviewRequired, .requestCompleted:
            "Apple does not distinguish denied read access from having no matching samples."
        }
    }

    private var lastSyncValue: String {
        model.syncSummary.lastSuccessfulSyncAt?
            .formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    private var compactLastSyncValue: String {
        guard let lastSync = model.syncSummary.lastSuccessfulSyncAt else {
            return "Never"
        }

        let calendar = Calendar.current
        let date: String
        if calendar.component(.year, from: lastSync)
            == calendar.component(.year, from: .now)
        {
            date = lastSync.formatted(
                .dateTime.month(.abbreviated).day()
            )
        } else {
            date = lastSync.formatted(
                .dateTime.month(.abbreviated).day().year()
            )
        }
        let time = lastSync.formatted(date: .omitted, time: .shortened)
        return "\(date) · \(time)"
    }

    private var compactLatestDayValue: String {
        guard let rawValue = model.syncSummary.latestExportedDate else {
            return "None"
        }
        guard let date = BackfillDateCodec.date(from: rawValue) else {
            return rawValue
        }

        let calendar = Calendar.current
        if calendar.component(.year, from: date)
            == calendar.component(.year, from: .now)
        {
            return date.formatted(
                .dateTime.month(.abbreviated).day()
            )
        }
        return date.formatted(
            .dateTime.month(.abbreviated).day().year()
        )
    }

    private var healthConnectionDetail: String {
        switch model.healthAuthorizationState {
        case .unavailable:
            return "Apple Health requires a supported iPhone."
        case .checking:
            return "Checking the Health request and visible samples."
        case .statusUnavailable(let previouslyRequested):
            return previouslyRequested
                ? "The request status could not be refreshed; previously readable data can still sync."
                : "The Apple Health request status could not be checked."
        case .notRequested:
            return "Read-only access has not been requested."
        case .reviewRequired:
            return "Apple says at least one requested type needs review; existing readable types can still sync."
        case .requestCompleted:
            if readableMetricCount > 0 {
                return "\(readableMetricCount) types currently expose samples."
            }
            return "Request complete. Apple cannot distinguish denied access from no matching data."
        }
    }

    private var healthConnectionBadge: String {
        switch model.healthAuthorizationState {
        case .unavailable:
            "Unavailable"
        case .checking:
            "Checking"
        case .statusUnavailable:
            "Check failed"
        case .notRequested:
            "Not requested"
        case .reviewRequired:
            "Review needed"
        case .requestCompleted:
            "Request complete"
        }
    }

    private var healthConnectionTone: StatusTone {
        switch model.healthAuthorizationState {
        case .requestCompleted:
            .success
        case .checking:
            .accent
        case .reviewRequired, .statusUnavailable:
            .warning
        case .unavailable, .notRequested:
            .warning
        }
    }

    private var googleConnectionDetail: String {
        switch model.googleConnection {
        case .notConfigured:
            "Add the local Google connection details."
        case .restoring:
            "Checking the saved Google connection."
        case .disconnected:
            "Connect the Drive account that will own the export."
        case .temporarilyUnavailable:
            "Google sign-in is temporarily unavailable. Local data is safe."
        case .reauthorizationRequired:
            "Reconnect to resume pending uploads."
        case .authorized(let account):
            if model.syncReadiness == .localStorageUnavailable {
                account.email.map {
                    "\($0) is authorized; Drive activation is paused by local storage."
                } ?? "Google is authorized; Drive activation is paused by local storage."
            } else {
                account.email.map {
                    "\($0) is authorized; Drive folder setup is finishing."
                } ?? "Google is authorized; Drive folder setup is finishing."
            }
        case .driveUnavailable(let account):
            account.email.map {
                "\($0) is authorized, but the Drive folder could not be verified."
            } ?? "Google is authorized, but the Drive folder could not be verified."
        case .connected(let connection):
            connection.accountName ?? connection.folderName
        }
    }

    private var googleConnectionBadge: String {
        switch model.googleConnection {
        case .notConfigured:
            "Needs config"
        case .restoring:
            "Checking"
        case .disconnected:
            "Not connected"
        case .temporarilyUnavailable:
            "Unavailable"
        case .reauthorizationRequired:
            "Reconnect"
        case .authorized:
            model.syncReadiness == .localStorageUnavailable
                ? "Authorized"
                : "Finishing setup"
        case .driveUnavailable:
            "Drive unavailable"
        case .connected:
            "Connected"
        }
    }

    private var googleConnectionTone: StatusTone {
        switch model.googleConnection {
        case .connected:
            .success
        case .restoring:
            .accent
        case .authorized:
            model.syncReadiness == .localStorageUnavailable
                ? .warning
                : .accent
        case .temporarilyUnavailable, .driveUnavailable:
            .warning
        case .reauthorizationRequired:
            .danger
        case .notConfigured, .disconnected:
            .warning
        }
    }

    private var heroPresentation: HeroPresentation {
        switch model.syncReadiness {
        case .localStorageUnavailable:
            return connectionHero(
                badge: "Storage error",
                tone: .danger,
                title: "Local sync storage is unavailable",
                message: "Health Mule could not prepare its protected staging area, so syncing is paused.",
                action: .none
            )
        case .checkingConnections:
            return connectionHero(
                badge: "Checking",
                tone: .accent,
                title: "Checking your connections",
                message: "Health Mule is restoring local authorization state.",
                action: .none
            )
        case .healthUnavailable:
            return connectionHero(
                badge: "Unavailable",
                tone: .danger,
                title: "Apple Health is unavailable",
                message: "Health Mule needs a supported iPhone to read Apple Health data.",
                action: .none
            )
        case .healthStatusUnavailable(let canSync):
            if !canSync {
                return connectionHero(
                    badge: "Check failed",
                    tone: .warning,
                    title: "Apple Health status is unavailable",
                    message: "Health Mule could not check the request status yet. Try again from Setup.",
                    action: .setup("Check Health Again")
                )
            }
            break
        case .healthRequestRequired:
            return connectionHero(
                badge: "Setup needed",
                tone: .warning,
                title: "Request Apple Health access",
                message: "Choose the read-only fitness types you want Health Mule to query.",
                action: .setup("Request Health Access")
            )
        case .healthReviewRecommended:
            break
        case .googleNotConfigured:
            return connectionHero(
                badge: "Setup needed",
                tone: .warning,
                title: "Configure Google Drive",
                message: "Add this app’s local OAuth configuration before connecting Drive.",
                action: .setup("Review setup")
            )
        case .googleDisconnected:
            return connectionHero(
                badge: "Setup needed",
                tone: .warning,
                title: "Connect Google Drive",
                message: "Choose the Drive account that will own your private export.",
                action: .setup("Connect Drive")
            )
        case .googleTemporarilyUnavailable:
            return connectionHero(
                badge: "Unavailable",
                tone: .warning,
                title: "Google is temporarily unavailable",
                message: "Your local records are safe. Try restoring the connection again.",
                action: .setup("Review connection")
            )
        case .googleReauthorizationRequired:
            return connectionHero(
                badge: "Reconnect",
                tone: .danger,
                title: "Google Drive needs approval",
                message: "Reconnect to resume pending uploads.",
                action: .setup("Reconnect Drive")
            )
        case .googleDriveSetupRequired:
            return connectionHero(
                badge: "Finishing setup",
                tone: .accent,
                title: "Preparing your Drive folder",
                message: "Google is authorized; the managed export folder still needs verification.",
                action: .none
            )
        case .googleDriveUnavailable:
            return connectionHero(
                badge: "Drive unavailable",
                tone: .warning,
                title: "Drive folder setup needs a retry",
                message: "Your local records are safe while Health Mule verifies its managed folder.",
                action: .setup("Retry Drive Setup")
            )
        case .ready:
            break
        }
        if model.operationState.isWorking(.sync) {
            return HeroPresentation(
                badge: "Syncing",
                tone: .accent,
                title: "Relaying your latest changes",
                message: "New daily records are staged locally before anything is uploaded.",
                action: .sync
            )
        }
        if model.operationState.isFailure(.sync) {
            if model.syncSummary.permanentFailureCount > 0 {
                return permanentFailureHero
            }
            return HeroPresentation(
                badge: "Needs attention",
                tone: .danger,
                title: "Sync needs another look",
                message: "Your local copies are safe. Try the pending work again when you are ready.",
                action: model.syncSummary.retryableUploadCount > 0
                    ? .retry
                    : .none
            )
        }
        if model.syncSummary.permanentFailureCount > 0 {
            return permanentFailureHero
        }
        if model.syncSummary.pendingUploadCount > 0 {
            return HeroPresentation(
                badge: "\(model.syncSummary.pendingUploadCount) pending",
                tone: .warning,
                title: "Uploads are waiting",
                message: "The records are staged safely on this iPhone. Eligible uploads are ready to retry.",
                action: model.syncSummary.retryableUploadCount > 0
                    ? .retry
                    : .none
            )
        }
        if model.syncReadiness == .healthReviewRecommended {
            return connectionHero(
                badge: "Review suggested",
                tone: .warning,
                title: "Apple Health access needs review",
                message: "Existing readable types can still sync while you review the latest Health request.",
                action: .setup("Review Health Access")
            )
        }
        if case .healthStatusUnavailable(canSync: true) = model.syncReadiness {
            return connectionHero(
                badge: "Check failed",
                tone: .warning,
                title: "Apple Health status could not be refreshed",
                message: "Previously readable data can still sync. Recheck the request status from Setup.",
                action: .setup("Check Health Again")
            )
        }
        if model.syncSummary.lastSuccessfulSyncAt == nil {
            return HeroPresentation(
                badge: "Ready",
                tone: .accent,
                title: "Ready for the first sync",
                message: "Health Mule will build the selected history and publish it to your Drive.",
                action: .sync
            )
        }
        return HeroPresentation(
            badge: "Up to date",
            tone: .success,
            title: "Everything is in sync",
            message: "Opening the app will keep reconciling recent changes automatically.",
            action: .sync
        )
    }

    private func connectionHero(
        badge: String,
        tone: StatusTone,
        title: String,
        message: String,
        action: HeroPresentation.Action
    ) -> HeroPresentation {
        HeroPresentation(
            badge: badge,
            tone: tone,
            title: title,
            message: message,
            action: action
        )
    }

    private var permanentFailureHero: HeroPresentation {
        HeroPresentation(
            badge: "\(model.syncSummary.permanentFailureCount) blocked",
            tone: .danger,
            title: "An upload was rejected",
            message: "The local record is safe, but Drive reported a non-retryable error. Export diagnostics before resetting local sync state.",
            action: .none
        )
    }
}

private struct HeroPresentation {
    enum Action {
        case none
        case setup(String)
        case sync
        case retry
    }

    let badge: String
    let tone: StatusTone
    let title: String
    let message: String
    let action: Action
}

private struct ConnectionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let badge: String
    let tone: StatusTone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens setup.")
    }

    private var standardLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    connectionTitle
                    Spacer()
                    StatusBadge(title: badge, tone: tone)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            connectionTitle
            StatusBadge(title: badge, tone: tone)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var connectionTitle: some View {
        Text(title)
            .font(.headline)
    }
}
