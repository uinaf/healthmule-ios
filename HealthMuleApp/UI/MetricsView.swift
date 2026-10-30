import SwiftUI

struct MetricsView: View {
    @Bindable var model: AppModel
    @State private var draftMetrics: Set<HealthMetric>?

    var body: some View {
        Form {
            if let note = OperationNote(state: model.presentedOperationState, includesSync: true) {
                Section { note }
            }

            Section {
                ForEach(model.metricStatuses) { status in
                    Toggle(isOn: Binding(
                        get: { shownMetrics.contains(status.metric) },
                        set: { setDraft(status.metric, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.metric.title)
                            Text(detail(for: status.state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("metric-toggle-\(status.metric.rawValue)")
                }
            } footer: {
                Text(
                    "Readable means Apple Health showed HealthMule at least one sample. Apple does not reveal denied read access."
                )
            }

            if let draftMetrics {
                Section {
                    Button("Apply and Sync") {
                        model.applyMetricSelection(draftMetrics)
                        self.draftMetrics = nil
                    }
                    .disabled(model.blocksSettingsChanges)
                    .accessibilityIdentifier("metrics-apply-action")
                    Button("Discard Changes", role: .cancel) {
                        self.draftMetrics = nil
                    }
                    .accessibilityIdentifier("metrics-discard-action")
                } footer: {
                    Text("Turned-off metrics are cleared from existing daily records.")
                }
            }
        }
        .pageStyle()
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("metrics-screen")
    }

    private var shownMetrics: Set<HealthMetric> {
        draftMetrics ?? model.enabledMetrics
    }

    private func setDraft(_ metric: HealthMetric, enabled: Bool) {
        var metrics = shownMetrics
        if enabled {
            metrics.insert(metric)
        } else {
            metrics.remove(metric)
        }
        draftMetrics = metrics == model.enabledMetrics ? nil : metrics
    }

    private func detail(for state: MetricReadState) -> String {
        if case .readable(let lastSampleAt) = state {
            return "Last sample \(lastSampleAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return state.title
    }
}
