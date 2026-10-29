import SwiftUI

@MainActor
final class EchoBuffer: ObservableObject {
    @Published var message: String? {
        didSet {
            confirmation = nil
            if message != nil { onMessage?() }
        }
    }
    @Published private(set) var rejectedInputCount = 0
    var onMessage: (() -> Void)?
    var onInputChange: ((Bool) -> Void)?
    var expectsInput: Bool { confirmation != nil }
    private var confirmation: (() -> Void)? {
        didSet {
            if (oldValue != nil) != expectsInput { onInputChange?(expectsInput) }
        }
    }

    func confirm(_ prompt: String, onConfirm: @escaping () -> Void) {
        message = prompt
        confirmation = onConfirm
    }

    @discardableResult func respond(yes: Bool) -> Bool {
        guard let confirmation else { return false }
        clear()
        if yes { confirmation() }
        return true
    }

    func rejectInput() {
        rejectedInputCount += 1
    }

    func clear() {
        confirmation = nil
        if message != nil { message = nil }
    }
}

struct EchoArea: View {
    @ObservedObject var buffer: EchoBuffer
    var leadingInset: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Text(buffer.message?.components(separatedBy: .newlines).joined(separator: " ") ?? "")
                .font(.system(size: 12)).lineLimit(1)
                .keyframeAnimator(initialValue: 1.0, trigger: buffer.rejectedInputCount) { [expectsInput = buffer.expectsInput] content, opacity in
                    content.opacity(expectsInput ? opacity : 1)
                } keyframes: { _ in
                    LinearKeyframe(0.2, duration: 0.08)
                    LinearKeyframe(1, duration: 0.16)
                }
                .padding(.leading, leadingInset).padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ComposerWindowSizing.echoAreaHeight - 1)
        }
        .frame(height: ComposerWindowSizing.echoAreaHeight)
        .background(Theme.background).foregroundStyle(Theme.secondary)
        .help(buffer.message ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Echo area")
        .accessibilityValue(buffer.message ?? "No messages")
        .accessibilityIdentifier("echo-area")
    }
}
