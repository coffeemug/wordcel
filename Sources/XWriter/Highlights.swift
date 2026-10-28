import AppKit
import Combine

@MainActor
protocol HighlightService: ClaudeAuthentication {
    func highlights(in text: String, prompt: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> HighlightMatches
}

enum HighlightError: LocalizedError {
    case invalidResponse
    var errorDescription: String? {
        "Claude returned invalid highlighting intervals. Turn the button on again to retry."
    }
}

struct HighlightMatches: Codable, Equatable {
    struct Match: Codable, Equatable {
        let text: String
        let occurrence: Int
    }
    let matches: [Match]

    func ranges(in text: String) throws -> [NSRange] {
        let source = text as NSString
        let boundaries = Set(text.indices.map { $0.utf16Offset(in: text) } + [source.length])
        var occurrences: [[UInt16]: [NSRange]] = [:]
        var result: [NSRange] = []
        var seen = Set<NSRange>()
        for match in matches {
            guard !match.text.isEmpty, match.occurrence > 0 else { throw HighlightError.invalidResponse }
            let key = Array(match.text.utf16)
            if occurrences[key] == nil {
                var found: [NSRange] = []
                var start = 0
                while start < source.length {
                    let range = source.range(of: match.text, options: .literal, range: NSRange(location: start, length: source.length - start))
                    if range.location == NSNotFound { break }
                    found.append(range)
                    start = range.location + 1
                }
                occurrences[key] = found
            }
            guard let found = occurrences[key], match.occurrence <= found.count else { throw HighlightError.invalidResponse }
            let range = found[match.occurrence - 1]
            guard boundaries.contains(range.location), boundaries.contains(NSMaxRange(range)), seen.insert(range).inserted else {
                throw HighlightError.invalidResponse
            }
            result.append(range)
        }
        return result.sorted { $0.location == $1.location ? $0.length < $1.length : $0.location < $1.location }
    }
}

struct HighlightEdit {
    let range: NSRange
    let replacementLength: Int

    func applying(to intervals: [NSRange]) -> [NSRange] {
        guard range.length != 0 || replacementLength != 0 else { return intervals }
        return intervals.compactMap { interval in
            if range.length == 0 {
                // Typing at either edge can change the highlighted word or phrase too.
                if (interval.location...NSMaxRange(interval)).contains(range.location) { return nil }
            } else if NSIntersectionRange(range, interval).length > 0 { return nil }
            if NSMaxRange(range) <= interval.location {
                return NSRange(location: interval.location + replacementLength - range.length, length: interval.length)
            }
            return interval
        }
    }
}

@MainActor
final class HighlightController: ObservableObject {
    enum State: Equatable { case idle, loading, signingIn, ready }
    @Published private(set) var state = State.idle
    @Published private(set) var activeButtonID: UUID?
    private(set) var ranges: [NSRange] = []
    var isLoading: Bool { state == .loading || state == .signingIn }
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    private let service: any HighlightService
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var activePrompt: String?
    private var pendingEdits: [HighlightEdit] = []
    private weak var editor: ComposerTextView?

    init(service: any HighlightService) { self.service = service }

    func toggle(_ button: PromptButton, in editor: ComposerTextView, model: ClaudeModel, effort: ClaudeEffort) {
        if activeButtonID == button.id { dismiss(); return }
        dismiss()
        guard button.isConfigured else { onError?("Set a name and prompt for this button in Settings."); return }
        guard !editor.hasMarkedText(), !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError?("Write some text in the post before running a highlighting prompt.")
            return
        }
        let source = editor.string
        let id = UUID()
        self.editor = editor
        editor.highlightStyle = button.style
        activeButtonID = button.id
        activePrompt = button.prompt
        requestID = id
        state = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let authenticated = try await service.isAuthenticated()
                try Task.checkCancellation()
                guard requestID == id else { return }
                if !authenticated {
                    state = .signingIn
                    try await service.signIn()
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    state = .loading
                }
                let matches = try await service.highlights(in: source, prompt: button.prompt, model: model, effort: effort)
                try Task.checkCancellation()
                guard requestID == id else { return }
                guard editor.window != nil else { dismiss(); return }
                ranges = pendingEdits.reduce(try matches.ranges(in: source)) { $1.applying(to: $0) }
                pendingEdits = []
                editor.highlightRanges = ranges
                editor.refreshHighlights()
                state = .ready
                task = nil
                if ranges.isEmpty { onNotice?("No matching text remains.") }
            } catch is CancellationError {
                // A toggle, new request, or document change already cleared this request.
            } catch {
                guard requestID == id else { return }
                dismiss()
                onError?(error.localizedDescription)
            }
        }
    }

    func didEdit(_ edit: HighlightEdit, in editor: ComposerTextView) {
        guard self.editor === editor, activeButtonID != nil else { return }
        if isLoading { pendingEdits.append(edit) }
        ranges = edit.applying(to: ranges)
        editor.highlightRanges = ranges
    }

    func configurationChanged(_ buttons: [PromptButton]) {
        guard let activeButtonID else { return }
        guard let button = buttons.first(where: { $0.id == activeButtonID }), button.isConfigured, button.prompt == activePrompt else {
            dismiss()
            return
        }
        if editor?.highlightStyle != button.style {
            editor?.highlightStyle = button.style
            editor?.refreshHighlights()
        }
    }

    func dismiss() {
        requestID = nil
        task?.cancel()
        task = nil
        pendingEdits = []
        ranges = []
        editor?.highlightRanges = []
        editor?.refreshHighlights()
        editor = nil
        activePrompt = nil
        activeButtonID = nil
        state = .idle
    }
}
