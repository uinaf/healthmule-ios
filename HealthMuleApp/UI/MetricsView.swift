import SwiftUI

struct MetricsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: HealthMuleStyle.sectionSpacing) {
                authorizationNote

                VStack(spacing: 8) {
                    SectionHeading(title: "Included metrics")

                    VStack(spacing: 0) {
                        ForEach(Array(model.metricStatuses.enumerated()), id: \.element.id) { index, status in
                            MetricStatusRow(status: status)
                                .padding(16)

                            if index < model.metricStatuses.count - 1 {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .healthMuleCard(padding: 0)

                    SectionFooter(
                        text: "Readable means HealthKit exposed at least one matching sample to HealthMule."
                    )
                }
            }
            .frame(maxWidth: HealthMuleStyle.contentWidth)
            .padding(.horizontal, HealthMuleStyle.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(HealthMuleStyle.canvas)
        .navigationTitle("Health data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("metrics-screen")
    }

    private var authorizationNote: some View {
        HealthMuleNote(
            text: "Apple does not reveal whether read access was denied. “No readable data” can also mean that no matching sample exists."
        )
    }
}

private struct MetricStatusRow: View {
    let status: MetricStatus

    var body: some View {
        IconStatusRow(
            title: status.metric.title,
            status: status.state.title,
            detail: displayDetail,
            systemImage: status.metric.systemImage,
            tone: tone,
            accessibilityValue: "\(status.state.title). \(accessibilityDetail)"
        )
    }

    private var displayDetail: String? {
        if case .readable(let lastSampleAt) = status.state {
            return "Last sample \(lastSampleAt.formatted(date: .abbreviated, time: .omitted))."
        }
        return nil
    }

    private var accessibilityDetail: String {
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
    var systemImage: String {
        switch self {
        case .bodyMass:
            "scalemass.fill"
        case .stepCount:
            "figure.walk"
        case .activeEnergy:
            "flame.fill"
        case .restingEnergy:
            "bolt.heart.fill"
        case .restingHeartRate:
            "heart.fill"
        case .hrvSDNN:
            "waveform.path.ecg"
        case .vo2Max:
            "lungs.fill"
        case .sleep:
            "bed.double.fill"
        case .workouts:
            "figure.run"
        }
    }
}
