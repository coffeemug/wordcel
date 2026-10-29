import AppKit
import Combine

@MainActor
protocol PromptService: ClaudeAuthentication {
    func reply(to prompt: String, context: ModelContext, conversation: PromptConversation,
               model: ClaudeModel, effort: ClaudeEffort) async throws -> String
}

@MainActor
final class PromptConversation {
    let id = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-conversation-\(UUID())")
    var hasReply = false

    deinit {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do { try FileManager.default.removeItem(at: directory) }
        catch { NSLog("Couldn't remove temporary conversation directory: %@", error.localizedDescription) }
    }
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

    func send(_ prompt: String, context: ModelContext, conversation: PromptConversation, model: ClaudeModel, effort: ClaudeEffort) {
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
                let reply = try await service.reply(to: prompt, context: context, conversation: conversation, model: model, effort: effort)
                try Task.checkCancellation()
                guard requestID == id else { return }
                let message = try PromptReply(answer: reply).validated()
                conversation.hasReply = true
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
