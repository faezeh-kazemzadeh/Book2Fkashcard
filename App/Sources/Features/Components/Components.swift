import SwiftUI
import B2FCore

/// Text that sets its own writing direction from its content, so Persian or
/// Arabic card text renders RTL inside an English UI and vice versa.
struct AdaptiveText: View {
    let text: String
    var font: Font = .body
    var alignment: TextAlignment = .center

    init(_ text: String, font: Font = .body, alignment: TextAlignment = .center) {
        self.text = text
        self.font = font
        self.alignment = alignment
    }

    private var isRTL: Bool { StudyLanguage.detectScript(of: text)?.isRightToLeft ?? false }

    var body: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(alignment)
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ToastView: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
                .task(id: message) {
                    UIAccessibility.post(notification: .announcement, argument: message)
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { self.message = nil }
                }
        }
    }
}

struct PriorityBadge: View {
    let priority: LearningPriority

    var body: some View {
        if priority >= .high {
            Text(priority == .essential ? "Essential" : "High")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priority == .essential ? Color.orange.opacity(0.2) : Color.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(priority == .essential ? Color.orange : Color.blue)
        }
    }
}

struct ConfidenceWarning: View {
    var body: some View {
        Label("Low OCR confidence – please check", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

extension CardKind {
    var systemImage: String {
        switch self {
        case .vocabulary: return "textformat.abc"
        case .grammar: return "text.book.closed"
        case .reading: return "doc.text.magnifyingglass"
        case .speaking: return "waveform"
        case .basic: return "rectangle.on.rectangle"
        }
    }
}

extension ProcessingStatus {
    var label: LocalizedStringKey {
        switch self {
        case .pending: return "Waiting"
        case .extracting: return "Reading file"
        case .recognizing: return "Recognising text"
        case .structuring: return "Detecting lessons"
        case .generating: return "Creating flashcards"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }
}
