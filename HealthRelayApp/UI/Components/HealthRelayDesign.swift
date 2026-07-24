import SwiftUI

enum HealthRelayStyle {
    static let contentWidth: CGFloat = 720
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat = 20

    static var canvas: Color {
        Color(uiColor: .systemBackground)
    }

    static var surface: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var hairline: Color {
        Color.primary.opacity(0.07)
    }
}

enum StatusTone {
    case neutral
    case accent
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .accent:
            .accentColor
        case .success:
            .green
        case .warning:
            .orange
        case .danger:
            .red
        }
    }
}

struct StatusBadge: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.11), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineProgressLabel: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct OperationBanner: View {
    let state: OperationState

    var body: some View {
        if state != .idle {
            HStack(alignment: .center, spacing: 10) {
                if state.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tone.color)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: symbolName)
                        .foregroundStyle(tone.color)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .healthRelayCard(padding: 14)
            .background(tone.color.opacity(0.05), in: RoundedRectangle(
                cornerRadius: HealthRelayStyle.cardRadius,
                style: .continuous
            ))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("operation-status")
        }
    }

    private var message: String {
        switch state {
        case .idle:
            ""
        case .working(_, let message),
             .warning(_, let message),
             .succeeded(_, let message),
             .failed(_, let message):
            message
        }
    }

    private var tone: StatusTone {
        switch state {
        case .failed:
            .danger
        case .warning:
            .warning
        case .succeeded:
            .success
        case .idle, .working:
            .accent
        }
    }

    private var symbolName: String {
        switch state {
        case .failed:
            "exclamationmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .succeeded:
            "checkmark.circle.fill"
        case .idle, .working:
            "arrow.triangle.2.circlepath"
        }
    }
}

private struct HealthRelayCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                HealthRelayStyle.surface,
                in: RoundedRectangle(
                    cornerRadius: HealthRelayStyle.cardRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: HealthRelayStyle.cardRadius,
                    style: .continuous
                )
                .stroke(HealthRelayStyle.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func healthRelayCard(padding: CGFloat = 18) -> some View {
        modifier(HealthRelayCardModifier(padding: padding))
    }
}
