import AppKit
import Combine

@MainActor
protocol HighlightService: ClaudeAuthentication {
    func highlights(context: ModelContext, prompt: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> HighlightMatches
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
        let note: String?

        init(text: String, occurrence: Int, note: String? = nil) {
            self.text = text
            self.occurrence = occurrence
            self.note = note
        }
    }
    let matches: [Match]

    func ranges(in text: String) throws -> [NSRange] {
        try intervals(in: text).map(\.range)
    }

    func intervals(in text: String) throws -> [HighlightInterval] {
        let source = text as NSString
        let boundaries = Set(text.indices.map { $0.utf16Offset(in: text) } + [source.length])
        var occurrences: [[UInt16]: [NSRange]] = [:]
        var result: [HighlightInterval] = []
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
            let note = match.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(HighlightInterval(range: range, note: note?.isEmpty == false ? note : nil))
        }
        return result.sorted {
            $0.range.location == $1.range.location ? $0.range.length < $1.range.length : $0.range.location < $1.range.location
        }
    }
}

struct HighlightInterval: Equatable {
    var range: NSRange
    let note: String?
}

struct HighlightEdit {
    let range: NSRange
    let replacementLength: Int

    func applying(to intervals: [NSRange]) -> [NSRange] {
        intervals.compactMap { applying(to: $0) }
    }

    func applying(to intervals: [HighlightInterval]) -> [HighlightInterval] {
        return intervals.compactMap { interval in
            guard let updated = applying(to: interval.range) else { return nil }
            return HighlightInterval(range: updated, note: interval.note)
        }
    }

    private func applying(to interval: NSRange) -> NSRange? {
        guard range.length != 0 || replacementLength != 0 else { return interval }
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

@MainActor
final class HighlightController: ObservableObject {
    enum State: Equatable { case idle, loading, signingIn, ready }
    @Published private(set) var state = State.idle
    @Published private(set) var activeButtonID: UUID?
    private(set) var intervals: [HighlightInterval] = []
    var ranges: [NSRange] { intervals.map(\.range) }
    var isLoading: Bool { state == .loading || state == .signingIn }
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    var onNote: ((String?) -> Void)?
    private let service: any HighlightService
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var activePrompt: String?
    private var pendingEdits: [HighlightEdit] = []
    private weak var editor: ComposerTextView?
    private var hoveredIndex: Int?

    init(service: any HighlightService) { self.service = service }

    func toggle(_ button: PromptButton, in editor: ComposerTextView, model: ClaudeModel, effort: ClaudeEffort) {
        if activeButtonID == button.id { dismiss(); return }
        dismiss()
        guard button.isConfigured else { onError?("Set a name and prompt for this button in Settings."); return }
        guard !editor.hasMarkedText(),
              let context = ModelContext.capture(text: editor.string, selection: editor.selectedRange()),
              !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError?("Place the cursor in a paragraph with text, or select text to highlight.")
            return
        }
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
                let matches = try await service.highlights(context: context, prompt: button.prompt, model: model, effort: effort)
                try Task.checkCancellation()
                guard requestID == id else { return }
                guard editor.window != nil else { dismiss(); return }
                let capturedIntervals = try matches.intervals(in: context.text).map {
                    HighlightInterval(range: NSRange(location: context.range.location + $0.range.location, length: $0.range.length),
                                      note: $0.note)
                }
                intervals = pendingEdits.reduce(capturedIntervals) { $1.applying(to: $0) }
                pendingEdits = []
                editor.highlightRanges = ranges
                editor.refreshHighlights()
                state = .ready
                task = nil
                updateNote()
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
        intervals = edit.applying(to: intervals)
        editor.highlightRanges = ranges
        clearInspection()
    }

    func selectionChanged(in editor: ComposerTextView) {
        guard self.editor === editor else { return }
        hoveredIndex = nil
        updateNote()
    }

    func hoverChanged(at index: Int?, in editor: ComposerTextView) {
        guard self.editor === editor else { return }
        hoveredIndex = index
        updateNote()
    }

    func clearInspection() {
        hoveredIndex = nil
        onNote?(nil)
    }

    private func updateNote() {
        guard state == .ready, let editor, editor.window?.isKeyWindow == true, !editor.hasMarkedText() else {
            onNote?(nil)
            return
        }
        let selection = editor.selectedRange()
        let caretNote = editor.window?.firstResponder === editor && selection.length == 0 ? note(at: selection.location) : nil
        onNote?(hoveredIndex.flatMap { note(at: $0) } ?? caretNote)
    }

    private func note(at index: Int) -> String? {
        intervals.filter { $0.note != nil && NSLocationInRange(index, $0.range) }
            .min { $0.range.length < $1.range.length }?.note
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
        intervals = []
        editor?.highlightRanges = []
        editor?.refreshHighlights()
        editor = nil
        activePrompt = nil
        activeButtonID = nil
        state = .idle
        clearInspection()
    }
}
