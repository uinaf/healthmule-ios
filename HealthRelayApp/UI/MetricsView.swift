import SwiftUI

struct MetricsView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                authorizationNote

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.metricStatuses) { status in
                        MetricStatusCard(status: status)
                    }
                }
            }
            .frame(maxWidth: HealthRelayStyle.contentWidth)
            .padding(.horizontal, HealthRelayStyle.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(HealthRelayStyle.canvas)
        .navigationTitle("Health data")
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("metrics-screen")
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 155), spacing: 12)]
    }

    private var authorizationNote: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    authorizationNoteIcon
                    authorizationNoteText
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    authorizationNoteIcon
                    authorizationNoteText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var authorizationNoteIcon: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var authorizationNoteText: some View {
        Text(
            "Apple does not reveal whether read access was denied. “No readable data” can also mean that no matching sample exists."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct MetricStatusCard: View {
    let status: MetricStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(status.metric.compactTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Circle()
                    .fill(tone.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(status.state.title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .healthRelayCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.metric.title)
        .accessibilityValue("\(status.state.title). \(detail)")
    }

    private var detail: String {
        switch status.state {
        case .checking:
            "Checking for a visible sample."
        case .notIncluded:
            "Disabled in Settings."
        case .notRequested:
            "Review Apple Health access to include this type."
        case .unavailable:
            "Apple Health is unavailable."
        case .noReadableData:
            "No visible sample."
        case .checkFailed:
            "Could not check this type."
        case .readable(let lastSampleAt):
            "Last sample \(lastSampleAt.formatted(date: .abbreviated, time: .omitted))."
        }
    }

    private var tone: StatusTone {
        switch status.state {
        case .checking:
            .accent
        case .notIncluded, .notRequested, .noReadableData:
            .neutral
        case .unavailable, .checkFailed:
            .warning
        case .readable:
            .success
        }
    }
}

private extension HealthMetric {
    var compactTitle: String {
        switch self {
        case .restingHeartRate:
            "Resting heart"
        case .hrvSDNN:
            "HRV"
        default:
            title
        }
    }
}
