import SwiftUI

@MainActor
final class EchoBuffer: ObservableObject {
    @Published var message: String?

    func clear() {
        if message != nil { message = nil }
    }
}

struct EchoArea: View {
    @ObservedObject var buffer: EchoBuffer

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Text(buffer.message?.components(separatedBy: .newlines).joined(separator: " ") ?? "")
                .font(.system(size: 12)).lineLimit(1)
                .padding(.horizontal, 12)
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
