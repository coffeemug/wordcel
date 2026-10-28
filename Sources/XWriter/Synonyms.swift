import AppKit
import Combine
import NaturalLanguage

struct SynonymLists: Codable, Equatable {
    var latin: [String]
    var germanic: [String]

    func validated() throws -> SynonymLists {
        let allowed = CharacterSet.letters.union(.nonBaseCharacters).union(CharacterSet(charactersIn: " '-\u{2019}"))
        let words = latin + germanic
        guard latin.count <= 13, germanic.count <= 13,
              words.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 48 &&
                  $0.unicodeScalars.contains(where: CharacterSet.letters.contains) &&
                  $0.unicodeScalars.allSatisfy(allowed.contains) }) else { throw ClaudeCLIError.invalidResponse }
        let normalized = words.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard Set(normalized).count == normalized.count else { throw ClaudeCLIError.invalidResponse }
        return SynonymLists(latin: Array(normalized.prefix(latin.count)), germanic: Array(normalized.suffix(germanic.count)))
    }
}

struct SynonymTarget {
    let text: String
    let selection: NSRange
    let range: NSRange
    var word: String { (text as NSString).substring(with: range) }

    static func capture(text: String, selection: NSRange) -> SynonymTarget? {
        guard Range(selection, in: text) != nil else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let words = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .filter { text[$0].unicodeScalars.contains(where: CharacterSet.letters.contains) }
            .map { NSRange($0, in: text) }
        let range = words.first { $0.location <= selection.location && selection.location < NSMaxRange($0) && NSMaxRange(selection) <= NSMaxRange($0) }
            ?? words.first { selection.length == 0 && NSMaxRange($0) == selection.location }
        guard let range, range.length <= 100 else { return nil }
        return SynonymTarget(text: text, selection: selection, range: range)
    }

    @MainActor func matches(_ editor: ComposerTextView) -> Bool {
        editor.window != nil && editor.string == text && editor.selectedRange() == selection
    }

    func replacement(_ synonym: String) -> String {
        if word == word.uppercased() { return synonym.uppercased() }
        if word.first?.isUppercase == true && word.dropFirst() == word.dropFirst().lowercased() {
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
    var onError: ((String) -> Void)?
    private let service: any SynonymService
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private weak var editor: ComposerTextView?
    private var target: SynonymTarget?

    init(service: any SynonymService) { self.service = service }

    func lookup(in editor: ComposerTextView) {
        dismiss()
        guard !editor.hasMarkedText(),
              let target = SynonymTarget.capture(text: editor.string, selection: editor.selectedRange()) else {
            onError?("Place the cursor in a word to find synonyms.")
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
                let lists = try await service.synonyms(for: target.word).validated()
                try Task.checkCancellation()
                guard requestID == id else { return }
                guard target.matches(editor) else { dismiss(); return }
                state = .ready(lists)
                task = nil
            } catch is CancellationError {
                // A newer request or an editor interaction already restored the toolbar.
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
        if let target, self.editor !== editor || !target.matches(editor) { dismiss() }
    }

    func lostFocus() {
        if state != .signingIn { dismiss() }
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
