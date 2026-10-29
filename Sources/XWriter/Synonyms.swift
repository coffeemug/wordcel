import AppKit
import Combine

struct SynonymLists: Codable, Equatable {
    static let maximumCount = 12
    var latin: [String]
    var germanic: [String]

    func validated() throws -> SynonymLists {
        let allowed = CharacterSet.letters.union(.nonBaseCharacters).union(CharacterSet(charactersIn: "'\u{2019}"))
        let words = latin + germanic
        guard latin.count <= Self.maximumCount, germanic.count <= Self.maximumCount,
              words.allSatisfy({ !$0.isEmpty && $0.count <= 48 &&
                  $0.unicodeScalars.contains(where: CharacterSet.letters.contains) &&
                  $0.unicodeScalars.allSatisfy(allowed.contains) }) else { throw ClaudeCLIError.invalidResponse }
        let normalized = words.map { $0.lowercased() }
        guard Set(normalized).count == normalized.count else { throw ClaudeCLIError.invalidResponse }
        return SynonymLists(latin: Array(normalized.prefix(latin.count)), germanic: Array(normalized.suffix(germanic.count)))
    }
}

struct SynonymTarget {
    let context: ModelContext
    let query: String
    let range: NSRange

    static func capture(text: String, selection: NSRange) -> SynonymTarget? {
        guard let context = ModelContext.capture(text: text, selection: selection),
              let target = context.target, let targetRange = context.targetRange,
              selection.length > 0 || targetRange.length <= 100 else { return nil }
        let phrase = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phrase.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        let phraseRange = (text as NSString).range(of: phrase, options: .literal, range: targetRange)
        return SynonymTarget(context: context, query: phrase, range: phraseRange)
    }

    func matches(text: String, selection: NSRange) -> Bool {
        guard let current = Self.capture(text: text, selection: selection) else { return false }
        return current.range == range && current.query == query
    }

    @MainActor func matches(_ editor: ComposerTextView) -> Bool {
        editor.window != nil && matches(text: editor.string, selection: editor.selectedRange())
    }

    func replacement(_ synonym: String) -> String {
        if query == query.uppercased() { return synonym.uppercased() }
        if query.first?.isUppercase == true && query.dropFirst() == query.dropFirst().lowercased() {
            return synonym.prefix(1).uppercased() + synonym.dropFirst()
        }
        return synonym
    }
}

@MainActor
final class SynonymController: ObservableObject {
    enum State: Equatable {
        case idle, loading, signingIn
        case ready(SynonymLists)
    }

    @Published private(set) var state = State.idle
    var hasResults: Bool {
        if case .ready = state { return true }
        return false
    }
    var onError: ((String) -> Void)?
    private let service: any SynonymService
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private weak var editor: ComposerTextView?
    private var target: SynonymTarget?

    init(service: any SynonymService) { self.service = service }

    func lookup(in editor: ComposerTextView, model: ClaudeModel, effort: ClaudeEffort) {
        dismiss()
        guard !editor.hasMarkedText(),
              let target = SynonymTarget.capture(text: editor.string, selection: editor.selectedRange()) else {
            onError?("Place the cursor in a word or select a phrase to find single-word alternatives.")
            return
        }
        let id = UUID()
        self.editor = editor
        self.target = target
        requestID = id
        state = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if try await !service.isAuthenticated() {
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    state = .signingIn
                    try await service.signIn()
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    guard target.matches(editor) else { dismiss(); return }
                    editor.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    state = .loading
                }
                let lists = try await service.synonyms(context: target.context, model: model, effort: effort).validated()
                try Task.checkCancellation()
                guard requestID == id else { return }
                guard target.matches(editor) else { dismiss(); return }
                state = .ready(lists)
                task = nil
            } catch is CancellationError {
                // A newer request or dismissal already cleared these results.
            } catch {
                guard requestID == id else { return }
                dismiss()
                onError?(error.localizedDescription)
            }
        }
    }

    func choose(_ word: String) -> Bool {
        guard case .ready(let lists) = state,
              (lists.latin + lists.germanic).contains(word),
              let editor, let target, target.matches(editor) else { return false }
        let replacement = target.replacement(word)
        dismiss()
        editor.window?.makeFirstResponder(editor)
        editor.breakUndoCoalescing()
        editor.insertText(replacement, replacementRange: target.range)
        editor.breakUndoCoalescing()
        editor.revealSelectionAfterLayout()
        return true
    }

    func invalidateIfChanged(in editor: ComposerTextView) {
        guard self.editor === editor else { return }
        invalidateIfChanged(text: editor.string)
    }

    func invalidateIfChanged(text: String?) {
        guard let target else { return }
        guard let text, let editor, target.matches(text: text, selection: editor.selectedRange()) else {
            dismiss()
            return
        }
    }

    func dismiss() {
        requestID = nil
        task?.cancel()
        task = nil
        target = nil
        editor = nil
        if state != .idle { state = .idle }
    }
}
