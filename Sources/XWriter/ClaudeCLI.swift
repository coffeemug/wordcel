import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case fable = "claude-fable-5-1"
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fable: return "Fable 5.1"
        case .opus: return "Opus 5.5"
        case .sonnet: return "Sonnet 5.5"
        case .haiku: return "Haiku 5.5"
        }
    }
}

enum ClaudeEffort: String, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }
    var title: String { self == .xhigh ? "Extra high" : rawValue.capitalized }
}

@MainActor
protocol ClaudeAuthentication {
    func isAuthenticated() async throws -> Bool
    func signIn() async throws
}

@MainActor
protocol SynonymService: ClaudeAuthentication {
    func synonyms(context: ModelContext, model: ClaudeModel, effort: ClaudeEffort) async throws -> SynonymLists
}

enum ClaudeCLIError: LocalizedError {
    case unavailable, invalidResponse, timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Install the official Claude Code CLI from https://code.claude.com/docs/en/setup, then try again."
        case .invalidResponse:
            return "Claude did not return valid synonym lists. Please try again."
        case .timedOut:
            return "Claude took too long to respond. Please try again."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class ClaudeCLI: SynonymService, HighlightService, PromptService {
    let configurationDirectory: URL
    let log: ModelSessionLog
    private let executable: URL?

    init(configurationDirectory: URL, executable: URL? = nil, log: ModelSessionLog? = nil) {
        self.configurationDirectory = configurationDirectory
        self.executable = executable
        self.log = log ?? ModelSessionLog()
    }

    private static func findExecutable() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { "\($0)/claude" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClaudeCLIError.unavailable
        }
        return URL(fileURLWithPath: path)
    }

    private var environment: [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var result = inherited.filter { ["HOME", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "TMPDIR"].contains($0.key) }
        result["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        result["PATH"] = result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Claude owns this separate profile, including its browser login and credential storage.
        result["CLAUDE_CONFIG_DIR"] = configurationDirectory.path
        result["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        return result
    }

    private func run(_ arguments: [String], input: String = "", timeout: TimeInterval = 90, captureOutput: Bool = true,
                     workingDirectory: URL? = nil, onResult: ((ClaudeCommand.Result) -> Void)? = nil) async throws -> ClaudeCommand.Result {
        let binary = try executable ?? Self.findExecutable()
        try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try await ClaudeCommand().run(executable: binary, arguments: arguments, environment: environment,
                                             input: input, timeout: timeout, captureOutput: captureOutput,
                                             workingDirectory: workingDirectory, onResult: onResult)
    }

    private static let settings = #"{"disableAllHooks":true,"autoMemoryEnabled":false,"claudeMdExcludes":["**"]}"#
    private static var configurationArguments: [String] {
        ["--setting-sources", "", "--settings", settings]
    }

    func isAuthenticated() async throws -> Bool {
        let response = try await run(Self.configurationArguments + ["auth", "status"], timeout: 15)
        struct Status: Decodable { let loggedIn: Bool; let authMethod: String }
        guard let status = try? JSONDecoder().decode(Status.self, from: response.output) else {
            throw ClaudeCLIError.failed("Couldn't check Claude Code sign-in. Update the Claude Code CLI and try again.")
        }
        guard response.status == 0 || (response.status == 1 && !status.loggedIn) else {
            throw ClaudeCLIError.failed("Claude Code couldn't check your account (exit \(response.status)).")
        }
        return status.loggedIn && status.authMethod == "claude.ai"
    }

    func signIn() async throws {
        // Let the official CLI open the browser and receive its own callback; never capture login URLs or codes.
        let response = try await run(Self.configurationArguments + ["auth", "login", "--claudeai"], timeout: 300, captureOutput: false)
        guard response.status == 0, try await isAuthenticated() else {
            throw ClaudeCLIError.failed("Claude subscription sign-in did not complete. Try your request again.")
        }
    }

    static let schema = #"{"type":"object","properties":{"latin":{"type":"array","items":{"type":"string","pattern":"^[^\\s-]+$"},"maxItems":\#(SynonymLists.maximumCount)},"germanic":{"type":"array","items":{"type":"string","pattern":"^[^\\s-]+$"},"maxItems":\#(SynonymLists.maximumCount)}},"required":["latin","germanic"],"additionalProperties":false}"#
    static let systemPrompt = """
    Find a broad set of English alternatives organized by etymology.
    \(ModelContext.instructions)
    Aim for \(SynonymLists.maximumCount) useful, context-appropriate single-word alternatives per group for the entire target, with the strongest fits first.
    Search broadly before returning fewer. Include fitting near-synonyms and words that capture the intended idea, not only exact dictionary synonyms.
    For a phrase, infer the idea it conveys and find one word that captures that idea, not separate synonyms for its individual words.
    Do not require exact equivalence. Allow modest changes in nuance, emphasis, or specificity while keeping the sentence's overall intent.
    Each suggestion must be one unhyphenated word, with no whitespace. Never return phrases, multiword compounds, or hyphenated forms such as "progress report" or "write-up".
    Each suggestion must replace the entire target, preserving its grammatical role and appropriate inflection without changing surrounding words.
    Exclude unrelated senses and alternatives that substantially change what the sentence says.
    For example, in "with each update add something nice", "update" is a noun; "revise" is not a valid replacement.
    In "They tend to put things off", "procrastinate" can replace the whole phrase "put things off".
    latin: words with Latin-derived roots, including borrowings through French.
    germanic: words with Germanic roots, including inherited Old English words, Old Norse borrowings, and other Germanic borrowings.
    Give the Germanic group a thorough, separate search: consider everyday verbs, concrete or figurative alternatives, and natural single-word derivatives.
    Classify by the main lexical root, not every prefix or suffix; a borrowed affix does not disqualify an otherwise Germanic root.
    Before finishing, make a second pass for overlooked Germanic alternatives. Do not stop after one or two obvious matches or after filling the Latin group.
    Exclude the original target and duplicates. Do not pad the list with grammatical variants that do not fit the sentence.
    Prefer short, familiar words, but include less-common words when they are natural and useful in this context.
    Do not invent etymologies, include uncertain roots, or sacrifice contextual fit to fill a group.
    Fewer than \(SynonymLists.maximumCount) words, or an empty group, is valid only when a broad search finds no further suitable alternatives.
    Return only the requested structured output. Do not use tools.
    """

    func synonyms(context: ModelContext, model: ClaudeModel, effort: ClaudeEffort) async throws -> SynonymLists {
        return try Self.decode(await structuredResponse(feature: "Synonyms", input: context.input(),
                                                       systemPrompt: Self.systemPrompt, schema: Self.schema, model: model, effort: effort))
    }

    static let highlightSchema = #"{"type":"object","properties":{"matches":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string","minLength":1},"occurrence":{"type":"integer","minimum":1}},"required":["text","occurrence"],"additionalProperties":false}}},"required":["matches"],"additionalProperties":false}"#
    static let highlightSystemPrompt = """
    Identify intervals within the supplied context according to the user's highlighting rule in "prompt".
    \(ModelContext.instructions)
    Use the target to interpret the rule, but highlight only within "text", never elsewhere in the post.
    Return matches as exact, case-sensitive, verbatim substrings of "text", preserving whitespace, punctuation, and Unicode.
    For each match, give "text" and "occurrence": its 1-based occurrence within the input's "text" field, counting exact occurrences from left to right, including overlapping occurrences. Do not count occurrences in "target" or "prompt".
    Each match identifies just the text to highlight. Do not include surrounding context unless it also qualifies.
    Identify all qualifying occurrences, including repeated words. Never rewrite, correct, normalize, or invent text.
    Do not return duplicate intervals. Return an empty matches array when nothing qualifies.
    Return only the requested structured output. Do not use tools.
    """

    func highlights(context: ModelContext, prompt: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> HighlightMatches {
        let response = try await structuredResponse(feature: "Highlights", input: context.input(prompt: prompt), systemPrompt: Self.highlightSystemPrompt,
                                                    schema: Self.highlightSchema, model: model, effort: effort)
        return try Self.decodeStructured(response, as: HighlightMatches.self, invalidResponse: HighlightError.invalidResponse)
    }

    static let promptSchema = #"{"type":"object","properties":{"answer":{"type":"string","minLength":1}},"required":["answer"],"additionalProperties":false}"#
    static let promptSystemPrompt = """
    You are a concise writing assistant whose reply appears in a small minibuffer.
    \(ModelContext.instructions)
    Answer the user's request in "prompt", using the target and surrounding text as context.
    Continue the conversation using earlier requests and replies; follow-up questions may refer to your previous answers.
    Keep the response short: prefer one short sentence and use no more than two short sentences.
    Use plain text without Markdown, headings, preambles, or line breaks.
    Return only the requested structured output, with your reply in "answer". Do not use tools.
    """

    func reply(to prompt: String, context: ModelContext, conversation: PromptConversation,
               model: ClaudeModel, effort: ClaudeEffort) async throws -> String {
        let response = try await structuredResponse(feature: "Conversation", input: context.input(prompt: prompt), systemPrompt: Self.promptSystemPrompt,
                                                    schema: Self.promptSchema, model: model, effort: effort, conversation: conversation)
        return try Self.decodePrompt(response, sessionID: conversation.id)
    }

    static func decodePrompt(_ response: ClaudeCommand.Result, sessionID: UUID? = nil) throws -> String {
        try decodeStructured(response, as: PromptReply.self, invalidResponse: PromptError.invalidResponse, sessionID: sessionID).validated()
    }

    private func structuredResponse(feature: String, input: String, systemPrompt: String, schema: String,
                                    model: ClaudeModel, effort: ClaudeEffort, conversation: PromptConversation? = nil) async throws -> ClaudeCommand.Result {
        var arguments = Self.configurationArguments + [
            "--print", "--model", model.rawValue, "--effort", effort.rawValue,
            "--output-format", "json", "--json-schema", schema,
            "--system-prompt", systemPrompt, "--tools", "",
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--disable-slash-commands"
        ]
        if let conversation {
            arguments += [conversation.hasReply ? "--resume" : "--session-id", conversation.id.uuidString]
        } else {
            arguments.append("--no-session-persistence")
        }
        let entry = log.begin(feature: feature, arguments: arguments, input: input)
        do {
            if let conversation {
                try FileManager.default.createDirectory(at: conversation.directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            return try await run(arguments, input: input, workingDirectory: conversation?.directory,
                                 onResult: { [log] in log.received($0, for: entry) })
        } catch {
            log.failed(error, for: entry)
            throw error
        }
    }

    private struct Envelope<Output: Decodable>: Decodable {
        let type: String
        let is_error: Bool
        let result: String?
        let structured_output: Output?
        let session_id: UUID?
    }

    static func decode(_ response: ClaudeCommand.Result) throws -> SynonymLists {
        try decodeStructured(response, as: SynonymLists.self, invalidResponse: ClaudeCLIError.invalidResponse).validated()
    }

    private static func decodeStructured<Output: Decodable>(_ response: ClaudeCommand.Result, as: Output.Type,
                                                            invalidResponse: Error, sessionID: UUID? = nil) throws -> Output {
        guard let envelope = try? JSONDecoder().decode(Envelope<Output>.self, from: response.output) else {
            if response.status != 0 {
                let detail = String(decoding: response.diagnostics, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ClaudeCLIError.failed("Claude Code failed (exit \(response.status)). \(String(detail.prefix(400)))")
            }
            throw invalidResponse
        }
        guard response.status == 0, !envelope.is_error else {
            throw ClaudeCLIError.failed(String((envelope.result ?? "Claude couldn't complete the request. Check your sign-in and subscription limits.").prefix(400)))
        }
        guard envelope.type == "result", let output = envelope.structured_output else { throw invalidResponse }
        guard sessionID == nil || envelope.session_id == sessionID else { throw invalidResponse }
        return output
    }
}

@MainActor
final class ClaudeCommand {
    struct Result {
        let status: Int32
        let output: Data
        var diagnostics = Data()
    }

    private let process = Process()
    private var continuation: CheckedContinuation<Int32, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var killTask: Task<Void, Never>?
    private var failure: Error?

    func run(executable: URL, arguments: [String], environment: [String: String], input: String,
             timeout: TimeInterval, captureOutput: Bool = true, workingDirectory: URL? = nil,
             onResult: ((Result) -> Void)? = nil) async throws -> Result {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-Claude-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { NSLog("Couldn't remove temporary Claude files: %@", error.localizedDescription) }
        }
        let inputURL = directory.appendingPathComponent("input")
        let outputURL = directory.appendingPathComponent("output")
        let errorURL = directory.appendingPathComponent("stderr")
        try Data(input.utf8).write(to: inputURL)
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)
        let stdin = try FileHandle(forReadingFrom: inputURL)
        let stdout = try FileHandle(forWritingTo: outputURL)
        let stderr = try FileHandle(forWritingTo: errorURL)
        defer { stdin.closeFile(); stdout.closeFile(); stderr.closeFile() }
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory ?? directory
        process.standardInput = stdin
        process.standardOutput = captureOutput ? stdout : FileHandle.nullDevice
        process.standardError = captureOutput ? stderr : FileHandle.nullDevice
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                process.terminationHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in self?.finished() }
                }
                do {
                    try process.run()
                    timeoutTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(timeout)) }
                        catch is CancellationError { return }
                        catch { self?.stop(error); return }
                        self?.stop(ClaudeCLIError.timedOut)
                    }
                } catch {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop(CancellationError()) }
        }
        for file in [outputURL, errorURL] {
            guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else {
                throw ClaudeCLIError.failed("Claude returned too much output.")
            }
        }
        let result = Result(status: status, output: try Data(contentsOf: outputURL), diagnostics: try Data(contentsOf: errorURL))
        onResult?(result)
        if let failure { throw failure }
        try Task.checkCancellation()
        return result
    }

    private func stop(_ error: Error) {
        guard continuation != nil, failure == nil else { return }
        failure = error
        if process.isRunning {
            process.terminate()
            killTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard let self, self.process.isRunning else { return }
                kill(self.process.processIdentifier, SIGKILL)
            }
        }
    }

    private func finished() {
        timeoutTask?.cancel()
        killTask?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: process.terminationStatus)
    }
}
