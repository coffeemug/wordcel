import SwiftUI

@MainActor
final class EchoBuffer: ObservableObject {
    @Published var message: String? {
        didSet {
            input = nil
            if message != nil { onMessage?() }
        }
    }
    @Published private(set) var rejectedInputCount = 0
    @Published var inputText = ""
    var onMessage: (() -> Void)?
    var onInputChange: ((Bool) -> Void)?
    weak var textField: NSTextField?
    var expectsInput: Bool { input != nil }
    var readsText: Bool {
        if case .text = input { return true }
        return false
    }
    private enum Input {
        case confirmation(() -> Void)
        case text((String) -> Void)
    }
    @Published private var input: Input? {
        didSet {
            if (oldValue != nil) != expectsInput { onInputChange?(expectsInput) }
        }
    }

    func confirm(_ prompt: String, onConfirm: @escaping () -> Void) {
        message = prompt
        input = .confirmation(onConfirm)
    }

    func read(onSubmit: @escaping (String) -> Void) {
        message = "> "
        inputText = ""
        input = .text(onSubmit)
    }

    func submit() {
        guard case .text(let onSubmit) = input else { return }
        let text = inputText
        clear()
        onSubmit(text)
    }

    @discardableResult func respond(yes: Bool) -> Bool {
        guard case .confirmation(let confirmation) = input else { return false }
        clear()
        if yes { confirmation() }
        return true
    }

    func rejectInput() {
        rejectedInputCount += 1
    }

    func clear() {
        input = nil
        if message != nil { message = nil }
    }
}

struct EchoArea: View {
    @ObservedObject var buffer: EchoBuffer
    var leadingInset: CGFloat = 12
    var status: String?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Group {
                if buffer.readsText {
                    HStack(spacing: 0) {
                        Text("> ").font(.system(size: 12))
                        EchoTextInput(buffer: buffer)
                    }
                } else {
                    Text((buffer.message ?? status)?.components(separatedBy: .newlines).joined(separator: " ") ?? "")
                        .font(.system(size: 12)).lineLimit(1)
                        .keyframeAnimator(initialValue: 1.0, trigger: buffer.rejectedInputCount) { [expectsInput = buffer.expectsInput] content, opacity in
                            content.opacity(expectsInput ? opacity : 1)
                        } keyframes: { _ in
                            LinearKeyframe(0.2, duration: 0.08)
                            LinearKeyframe(1, duration: 0.16)
                        }
                }
            }
            .padding(.leading, leadingInset).padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ComposerWindowSizing.echoAreaHeight - 1)
        }
        .frame(height: ComposerWindowSizing.echoAreaHeight)
        .background(Theme.background).foregroundStyle(Theme.secondary)
        .help(buffer.message ?? status ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Echo area")
        .accessibilityValue(buffer.message ?? status ?? "No messages")
        .accessibilityIdentifier("echo-area")
    }
}

private struct EchoTextInput: NSViewRepresentable {
    @ObservedObject var buffer: EchoBuffer

    func makeNSView(context: Context) -> InputField {
        let field = InputField()
        field.buffer = buffer
        field.delegate = context.coordinator
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = Theme.foregroundNS
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel("Model prompt")
        field.setAccessibilityIdentifier("minibuffer-input")
        buffer.textField = field
        return field
    }

    func updateNSView(_ field: InputField, context: Context) {
        if field.stringValue != buffer.inputText { field.stringValue = buffer.inputText }
    }

    func makeCoordinator() -> Coordinator { Coordinator(buffer: buffer) }

    final class InputField: NSTextField {
        weak var buffer: EchoBuffer?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let buffer, buffer.readsText, buffer.textField === self else { return }
                window?.makeFirstResponder(self)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let buffer: EchoBuffer
        init(buffer: EchoBuffer) { self.buffer = buffer }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            buffer.inputText = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() {
                buffer.submit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                buffer.clear()
                return true
            }
            return false
        }
    }
}
