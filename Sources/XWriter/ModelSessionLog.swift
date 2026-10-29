import SwiftUI

@MainActor
final class ModelSessionLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let feature: String
        let arguments: [String]
        let input: String
        var response: ClaudeCommand.Result?
        var error: String?

        var transcript: String {
            var result = "\(feature) | \(date.ISO8601Format())\n\nCLI arguments:\n\(arguments.joined(separator: "\n"))\n\nInput:\n\(input)"
            if let response {
                result += "\n\nResponse (exit \(response.status)):\n\(String(decoding: response.output, as: UTF8.self))"
                if !response.diagnostics.isEmpty {
                    result += "\n\nDiagnostics:\n\(String(decoding: response.diagnostics, as: UTF8.self))"
                }
            }
            if let error { result += "\n\nError: \(error)" }
            else if response == nil { result += "\n\nWaiting for response..." }
            return result
        }
    }

    @Published private(set) var entries: [Entry] = []

    func begin(feature: String, arguments: [String], input: String) -> UUID {
        let entry = Entry(feature: feature, arguments: arguments, input: input)
        entries.append(entry)
        return entry.id
    }

    func received(_ response: ClaudeCommand.Result, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].response = response
    }

    func failed(_ error: Error, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].error = error is CancellationError ? "Cancelled." : error.localizedDescription
    }

    var transcript: String {
        if entries.isEmpty { return "No model requests in this app session." }
        return entries.enumerated().map { "#\($0.offset + 1) \($0.element.transcript)" }
            .joined(separator: "\n\n----------------------------------------\n\n")
    }
}

struct ModelSessionLogView: View {
    @ObservedObject var log: ModelSessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This app session: complete XWriter requests and raw Claude CLI responses. Authentication is not logged.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(12)
            Divider()
            LogTextView(text: log.transcript)
        }
        .background(Theme.background)
    }
}

private struct LogTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.backgroundColor = Theme.backgroundNS
        let editor = context.coordinator.editor
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.backgroundColor = Theme.backgroundNS
        editor.textColor = Theme.foregroundNS
        editor.identifier = NSUserInterfaceItemIdentifier("model-session-log")
        editor.setAccessibilityIdentifier("model-session-log")
        editor.setAccessibilityLabel("Model session log")
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let editor = context.coordinator.editor
        guard editor.string != text else { return }
        let selection = editor.selectedRange()
        let origin = scroll.contentView.bounds.origin
        let followsTail = editor.string.isEmpty || NSMaxY(scroll.contentView.bounds) >= editor.bounds.height - 2
        editor.string = text
        let length = (text as NSString).length
        let start = min(selection.location, length)
        editor.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
        if followsTail { editor.scrollRangeToVisible(NSRange(location: length, length: 0)) }
        else { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
    }

    final class Coordinator {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 0))
    }
}
