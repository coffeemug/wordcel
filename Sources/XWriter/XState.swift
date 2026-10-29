import AppKit
import Combine
import UniformTypeIdentifiers

enum ReplyAudience: String, Codable, CaseIterable, Identifiable {
    case everyone, following, verified, mentioned
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: return "Everyone"
        case .following: return "Accounts you follow"
        case .verified: return "Verified accounts"
        case .mentioned: return "Only accounts you mention"
        }
    }
    var label: String { self == .everyone ? "Everyone can reply" : "\(title) can reply" }
    var symbol: String {
        switch self {
        case .everyone: return "globe.americas.fill"
        case .following: return "person.fill.checkmark"
        case .verified: return "checkmark.seal.fill"
        case .mentioned: return "at"
        }
    }
}

struct Post: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var valid: Bool { hasContent && TweetLength.count(text) <= TweetLength.limit }
}

struct Draft: Codable, Identifiable, Equatable {
    var id = UUID()
    var posts = [Post()]
    var audience = ReplyAudience.everyone
    var modified = Date()
    var hasContent: Bool { posts.contains(where: \.hasContent) }
    var title: String {
        let text = posts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Untitled post" : text
    }
}

struct DraftArchive: Codable {
    var version = 2
    var current = Draft()
    var drafts: [Draft] = []
}

struct DraftStorage {
    let directory: URL
    var file: URL { directory.appendingPathComponent("drafts.json") }
    func read() throws -> DraftArchive {
        guard FileManager.default.fileExists(atPath: file.path) else { return DraftArchive() }
        var archive = try JSONDecoder().decode(DraftArchive.self, from: Data(contentsOf: file))
        guard (1...2).contains(archive.version), !archive.current.posts.isEmpty,
              archive.drafts.allSatisfy({ !$0.posts.isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if archive.version == 1 {
            // Re-encoding removes the retired media, poll, and planned-date fields.
            archive.version = 2
            archive.drafts.removeAll { !$0.hasContent }
            try write(archive)
        }
        return archive
    }
    func write(_ archive: DraftArchive) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: file, options: .atomic)
    }
}

@MainActor
final class ComposerModel: ObservableObject {
    @Published var draft: Draft {
        didSet {
            if draft.id != oldValue.id { synonyms.dismiss(); highlights.dismiss() }
            else { synonyms.invalidateIfChanged(text: draft.posts.first { $0.id == activePostID }?.text) }
            queueSave()
        }
    }
    @Published var drafts: [Draft]
    @Published var activePostID: UUID { didSet { if activePostID != oldValue { synonyms.dismiss(); highlights.dismiss() } } }
    @Published var composerWidth: CGFloat = 600
    @Published var showDrafts = false {
        didSet {
            if showDrafts != oldValue { onDraftsVisibilityChange?(showDrafts) }
        }
    }
    @Published var showHandoff = false
    @Published var synonymModel: ClaudeModel {
        didSet { preferences.set(synonymModel.rawValue, forKey: "synonymModel") }
    }
    @Published var synonymEffort: ClaudeEffort {
        didSet { preferences.set(synonymEffort.rawValue, forKey: "synonymEffort") }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }
    @Published var avatar: NSImage?
    let storage: DraftStorage
    let synonyms: SynonymController
    let toolbarSettings: PromptToolbarSettings
    let highlights: HighlightController
    let echo = EchoBuffer()
    private let preferences: UserDefaults
    private var saveWork: DispatchWorkItem?
    private var saveBlockReason: String?
    weak var activeEditor: ComposerTextView?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onDraftsVisibilityChange: ((Bool) -> Void)?
    var onShowSettings: (() -> Void)?

    init(directory: URL? = nil, synonymService: (any SynonymService)? = nil,
         highlightService: (any HighlightService)? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let savedModel = preferences.string(forKey: "synonymModel")
        synonymModel = savedModel.flatMap(ClaudeModel.init(rawValue:)) ?? .fable
        let savedEffort = preferences.string(forKey: "synonymEffort")
        synonymEffort = savedEffort.flatMap(ClaudeEffort.init(rawValue:)) ?? .medium
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XWriter", isDirectory: true)
        storage = DraftStorage(directory: base)
        let cli = ClaudeCLI(configurationDirectory: base.appendingPathComponent("claude-code"))
        synonyms = SynonymController(service: synonymService ?? cli)
        highlights = HighlightController(service: highlightService ?? cli)
        toolbarSettings = PromptToolbarSettings(preferences: preferences, echo: echo)
        var initial = DraftArchive()
        var readError: String?
        do { initial = try storage.read() }
        catch {
            readError = "Your draft file could not be loaded or upgraded: \(error.localizedDescription) It has been left untouched at \(storage.file.path). New drafts cannot be saved until this file is repaired or moved."
            saveBlockReason = readError
        }
        if let savedModel, ClaudeModel(rawValue: savedModel) == nil {
            readError = readError ?? "Your saved synonym model is no longer available. Using Fable 5.1; choose a model to save a new preference."
        }
        if let savedEffort, ClaudeEffort(rawValue: savedEffort) == nil {
            readError = readError ?? "Your saved reasoning level is no longer available. Using Medium; choose a reasoning level to save a new preference."
        }
        draft = initial.current
        drafts = initial.drafts
        activePostID = initial.current.posts[0].id
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "light"
        avatar = NSImage(contentsOf: base.appendingPathComponent("avatar.png"))
            ?? Bundle.main.url(forResource: "me", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(contentsOfFile: "me.png")
        echo.message = readError ?? toolbarSettings.error
        synonyms.onError = { [weak self] message in self?.notify(message) }
        highlights.onError = { [weak self] message in self?.notify(message) }
        highlights.onNotice = { [weak self] message in self?.notify(message) }
        toolbarSettings.onChange = { [weak self] buttons in self?.highlights.configurationChanged(buttons) }
    }

    var activeIndex: Int { draft.posts.firstIndex(where: { $0.id == activePostID }) ?? 0 }
    var canPost: Bool { draft.posts.allSatisfy(\.valid) }

    func toggleHighlights(_ button: PromptButton) {
        guard let editor = activeEditor, editor.window != nil else {
            notify("Place the cursor in a post to run a highlighting prompt.")
            return
        }
        synonyms.dismiss()
        highlights.toggle(button, in: editor, model: synonymModel, effort: synonymEffort)
    }

    func applyAppearance() {
        NSApp.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
    }

    private func queueSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @discardableResult func save() -> Bool {
        saveWork?.cancel()
        if let saveBlockReason {
            notify(saveBlockReason)
            return false
        }
        var current = draft
        current.modified = Date()
        var updated = drafts.filter { $0.id != current.id }
        if current.hasContent { updated.insert(current, at: 0) }
        do {
            try storage.write(DraftArchive(current: current, drafts: updated))
            drafts = updated
            return true
        } catch {
            notify("Couldn't save your draft: \(error.localizedDescription)")
            return false
        }
    }

    func toggleDrafts() {
        if !showDrafts { _ = save() }
        showDrafts.toggle()
    }

    func newDraft() {
        guard save() else { return }
        draft = Draft()
        activePostID = draft.posts[0].id
    }

    func load(_ item: Draft) {
        guard save() else { return }
        // Use the newest version if the currently edited draft was selected.
        draft = drafts.first(where: { $0.id == item.id }) ?? item
        activePostID = draft.posts[0].id
    }

    func deleteDraft(_ id: UUID) {
        let previousDraft = draft
        let previousDrafts = drafts
        drafts.removeAll { $0.id == id }
        if draft.id == id { draft = Draft(); activePostID = draft.posts[0].id }
        if !save() { draft = previousDraft; drafts = previousDrafts; activePostID = draft.posts[0].id }
    }

    func removePost(_ id: UUID) {
        guard draft.posts.count > 1 else { return }
        draft.posts.removeAll { $0.id == id }
        if activePostID == id { activePostID = draft.posts.last!.id }
    }

    func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.begin { [weak self] result in
            guard result == .OK, let self, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            let resized = NSImage(size: NSSize(width: 160, height: 160))
            resized.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: 160, height: 160))
            resized.unlockFocus()
            guard let data = resized.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }) else { return }
            do {
                try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
                try data.write(to: storage.directory.appendingPathComponent("avatar.png"), options: .atomic)
                avatar = resized
            } catch { self.notify("Couldn't save your profile photo: \(error.localizedDescription)") }
        }
    }

    func notify(_ message: String) {
        echo.message = message
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notify("Copied to clipboard")
    }

    func prepareHandoff() {
        guard canPost, save() else { return }
        showHandoff = true
    }

    static func intentURL(for text: String) -> URL {
        var url = URLComponents(string: "https://x.com/intent/tweet")!
        url.queryItems = [URLQueryItem(name: "text", value: text)]
        return url.url!
    }

    static func requiresClipboardHandoff(_ text: String) -> Bool {
        // Keep long Premium posts out of URLs that browsers or servers may truncate.
        intentURL(for: text).absoluteString.utf8.count > 7500
    }

    func openOnX(_ post: Post) {
        let useClipboard = Self.requiresClipboardHandoff(post.text)
        if useClipboard { copy(post.text) }
        let url = useClipboard ? URL(string: "https://x.com/compose/post")! : Self.intentURL(for: post.text)
        guard NSWorkspace.shared.open(url) else {
            notify("Couldn't open your browser. Copy your text and paste it into X.")
            return
        }
        if useClipboard { notify("Text copied — paste it into X with ⌘V") }
    }
}
