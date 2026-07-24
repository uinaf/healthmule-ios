import GoogleSignInSwift
import SwiftUI
import UIKit

struct SetupView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Three small steps")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Health Relay reads a narrow fitness allowlist and writes normalized daily records directly to your Drive."
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                OperationBanner(state: model.operationState)
                healthCard
                historyCard
                googleCard

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(
                        "There is no developer backend, analytics, advertising, or write access to Apple Health."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: HealthRelayStyle.contentWidth)
            .padding(.horizontal, HealthRelayStyle.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(HealthRelayStyle.canvas)
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("setup-screen")
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupStepHeader(
                number: 1,
                title: "Apple Health",
                badge: healthBadge,
                tone: healthTone
            )

            Text(
                "Request read-only access to the fitness types you want included. Apple does not tell apps which read permissions were approved."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(HealthMetric.allCases) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(metric.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if !model.enabledMetrics.contains(metric) {
                                    Text("Not included")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(metric.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)

                        if metric != HealthMetric.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(
                    "\(model.enabledMetrics.count) of \(HealthMetric.allCases.count) read-only data types included"
                )
                    .font(.subheadline.weight(.medium))
            }

            healthAuthorizationButton

            if !model.isHealthKitAvailable {
                Text("Apple Health authorization requires a supported iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .healthRelayCard()
    }

    @ViewBuilder
    private var healthAuthorizationButton: some View {
        switch model.healthAuthorizationState {
        case .unavailable:
            EmptyView()
        case .checking:
            InlineProgressLabel(title: "Checking Health access")
        case .statusUnavailable(let previouslyRequested):
            Text(
                previouslyRequested
                    ? "Apple Health’s request status could not be refreshed. Previously readable data can still sync."
                    : "Apple Health’s request status could not be checked yet."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Check Again") {
                Task {
                    await model.retryHealthStatus()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("health-authorization-action")
        case .requestCompleted:
            Button("Open App Settings") {
                if let settingsURL = URL(
                    string: UIApplication.openSettingsURLString
                ) {
                    openURL(settingsURL)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.isHealthKitAvailable)
            .accessibilityIdentifier("health-authorization-action")

            Text(
                "Request complete. To change access, use Settings → Privacy & Security → Health → Health Relay. Visible samples are the only read signal Apple provides."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .notRequested, .reviewRequired:
            Button {
                Task {
                    await model.requestHealthAuthorization()
                }
            } label: {
                Label(
                    model.healthAuthorizationState == .reviewRequired
                        ? "Review Health Access"
                        : "Request Health Access",
                    systemImage: "heart.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isHealthKitAvailable || model.operationState.isWorking)
            .accessibilityIdentifier("health-authorization-action")

            if model.healthAuthorizationState == .reviewRequired {
                Text(
                    "Apple reports that at least one requested type still needs review. Existing readable types can continue syncing."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupStepHeader(
                number: 2,
                title: "History",
                badge: historyBadge,
                tone: .neutral
            )

            Text(
                "Choose the first local calendar day to export. The boundary stays fixed after selection."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Initial backfill")
                    backfillPicker
                }
            } else {
                HStack {
                    Text("Initial backfill")
                    Spacer()
                    backfillPicker
                }
            }

            if model.backfillRange == .custom {
                Divider()
                DatePicker(
                    "Start date",
                    selection: Binding(
                        get: { model.customBackfillStart },
                        set: { model.updateCustomBackfillStart($0) }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .disabled(model.operationState.isWorking)
            }
        }
        .healthRelayCard()
    }

    private var backfillPicker: some View {
        Picker(
            "Initial backfill",
            selection: Binding(
                get: { model.backfillRange },
                set: { model.updateBackfillRange($0) }
            )
        ) {
            ForEach(BackfillRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(model.operationState.isWorking)
        .accessibilityIdentifier("backfill-range-picker")
    }

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupStepHeader(
                number: 3,
                title: "Google Drive",
                badge: googleBadge,
                tone: googleTone
            )

            Text(
                "Health Relay can access only the Drive files it creates or that you explicitly open with it."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            googleStateContent
        }
        .healthRelayCard()
        .accessibilityIdentifier("google-state")
    }

    @ViewBuilder
    private var googleStateContent: some View {
        switch model.googleConnection {
        case .notConfigured:
            Text(
                "Add the client ID and reversed client ID to Config/Secrets.xcconfig, then rebuild the app."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        case .restoring:
            InlineProgressLabel(title: "Checking Google connection")
        case .disconnected:
            GoogleSignInButton(scheme: googleButtonScheme) {
                Task {
                    await model.connectGoogle()
                }
            }
            .frame(minHeight: 44)
            .disabled(model.operationState.isWorking)
            .accessibilityLabel("Connect Google Drive")
        case .temporarilyUnavailable:
            Text(
                "Google sign-in is temporarily unavailable. Health Relay will try again when the app becomes active."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Try Again") {
                Task {
                    await model.retryGoogleRestore()
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.operationState.isWorking)
        case .reauthorizationRequired:
            Text(
                "Google Drive access needs approval. Reconnect to resume pending uploads."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            GoogleSignInButton(scheme: googleButtonScheme) {
                Task {
                    await model.connectGoogle()
                }
            }
            .frame(minHeight: 44)
            .disabled(model.operationState.isWorking)
            .accessibilityLabel("Reconnect Google Drive")
        case .authorized(let account):
            if let email = account.email {
                ValueRow(title: "Account", value: email)
            }
            if model.syncReadiness == .localStorageUnavailable {
                Text(
                    "Google authorization is complete. Drive activation is paused because local sync storage is unavailable."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                InlineProgressLabel(title: "Finishing Drive folder setup")
            }
        case .driveUnavailable(let account):
            if let email = account.email {
                ValueRow(title: "Account", value: email)
            }
            Text(
                "Google is authorized, but the managed Drive folder could not be verified. Local records are safe."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Try Drive Again") {
                Task {
                    await model.retryGoogleRestore()
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.operationState.isWorking)
        case .connected(let connection):
            VStack(spacing: 12) {
                ValueRow(
                    title: "Account",
                    value: connection.accountName ?? "Connected"
                )
                Divider()
                ValueRow(title: "Folder", value: connection.folderName)
            }

            if let folderURL = connection.folderURL {
                Button("Open in Google Drive") {
                    openURL(folderURL)
                }
                .buttonStyle(.bordered)
            }

            Text(
                "You may move this folder anywhere in My Drive. Health Relay keeps using its immutable folder ID."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var historyBadge: String {
        switch model.backfillRange {
        case .thirtyDays:
            "30 days"
        case .ninetyDays:
            "90 days"
        case .custom:
            "Custom"
        }
    }

    private var googleBadge: String {
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

    private var googleTone: StatusTone {
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

    private var healthBadge: String {
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

    private var healthTone: StatusTone {
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

    private var googleButtonScheme: GoogleSignInButtonColorScheme {
        colorScheme == .dark ? .dark : .light
    }
}

private struct SetupStepHeader: View {
    let number: Int
    let title: String
    let badge: String
    let tone: StatusTone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    stepTitle
                    StatusBadge(title: badge, tone: tone)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    stepTitle
                    Spacer()
                    StatusBadge(title: badge, tone: tone)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stepTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number.formatted())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
        }
    }
}
