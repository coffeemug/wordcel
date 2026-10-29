import AppKit
import Combine

@MainActor
protocol PromptService: ClaudeAuthentication {
    func reply(to prompt: String, text: String?, model: ClaudeModel, effort: ClaudeEffort) async throws -> String
}

enum PromptError: LocalizedError {
    case invalidResponse
    var errorDescription: String? { "Claude did not return a valid reply. Please try again." }
}

struct PromptReply: Decodable {
    let answer: String

    func validated() throws -> String {
        let result = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw PromptError.invalidResponse }
        return result
    }
}

@MainActor
final class PromptController: ObservableObject {
    enum State: Equatable { case idle, loading, signingIn }
    @Published private(set) var state = State.idle
    var onReply: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let service: any PromptService
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    var status: String? {
        switch state {
        case .idle: return nil
        case .loading: return "Thinking..."
        case .signingIn: return "Sign in in your browser"
        }
    }

    init(service: any PromptService) { self.service = service }

    static func context(text: String, selection: NSRange) -> String? {
        guard let range = Range(selection, in: text) else { return nil }
        if selection.length > 0 { return String(text[range]) }
        guard let word = SynonymTarget.wordRange(text: text, selection: selection) else { return nil }
        return (text as NSString).substring(with: word)
    }

    func send(_ prompt: String, text: String?, model: ClaudeModel, effort: ClaudeEffort) {
        dismiss()
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError?("Type a prompt before pressing Enter.")
            return
        }
        let id = UUID()
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
                let reply = try await service.reply(to: prompt, text: text, model: model, effort: effort)
                try Task.checkCancellation()
                guard requestID == id else { return }
                let message = try PromptReply(answer: reply).validated()
                requestID = nil
                task = nil
                state = .idle
                onReply?(message)
            } catch is CancellationError {
                // Dismissal or a newer minibuffer interaction owns the display now.
            } catch {
                guard requestID == id else { return }
                dismiss()
                onError?(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        requestID = nil
        task?.cancel()
        task = nil
        state = .idle
    }
}
