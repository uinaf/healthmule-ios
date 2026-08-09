import SwiftUI

struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HealthMuleStyle.Text.factLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(HealthMuleStyle.Text.factValue)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
