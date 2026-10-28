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

struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var data: Data
    var alt = ""
    var isGIF: Bool { name.lowercased().hasSuffix(".gif") }
}

struct Poll: Codable, Equatable {
    var choices = ["", ""]
    var days = 1
    var hours = 0
    var minutes = 0
    var valid: Bool {
        choices.count >= 2 && choices.count <= 4 &&
        choices.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 25 } &&
        (5...10080).contains(days * 1440 + hours * 60 + minutes)
    }
}

struct Post: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var attachments: [Attachment] = []
    var poll: Poll?
    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || poll != nil }
    var valid: Bool { hasContent && TweetLength.count(text) <= TweetLength.limit && (poll?.valid ?? true) }
}

struct Draft: Codable, Identifiable, Equatable {
    var id = UUID()
    var posts = [Post()]
    var audience = ReplyAudience.everyone
    var plannedDate: Date?
    var modified = Date()
    var hasContent: Bool { posts.contains(where: \.hasContent) }
    var title: String {
        let text = posts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? (posts.first?.poll != nil ? "Untitled poll" : "Photo post") : text
    }
}

struct DraftArchive: Codable {
    var version = 1
    var current = Draft()
    var drafts: [Draft] = []
}

struct DraftStorage {
    let directory: URL
    var file: URL { directory.appendingPathComponent("drafts.json") }
    func read() throws -> DraftArchive {
        guard FileManager.default.fileExists(atPath: file.path) else { return DraftArchive() }
        let archive = try JSONDecoder().decode(DraftArchive.self, from: Data(contentsOf: file))
        guard archive.version == 1, !archive.current.posts.isEmpty,
              archive.drafts.allSatisfy({ !$0.posts.isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
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
    @Published var draft: Draft { didSet { queueSave() } }
    @Published var drafts: [Draft]
    @Published var activePostID: UUID
    @Published var composerWidth: CGFloat = 600
    @Published var showDrafts = false {
        didSet {
            if showDrafts != oldValue { onDraftsVisibilityChange?(showDrafts) }
        }
    }
    @Published var showHandoff = false
    @Published var error: String?
    @Published var toast: String?
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }
    @Published var avatar: NSImage?
    let storage: DraftStorage
    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var canSave = true
    weak var activeEditor: ComposerTextView?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onDraftsVisibilityChange: ((Bool) -> Void)?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XWriter", isDirectory: true)
        storage = DraftStorage(directory: base)
        var initial = DraftArchive()
        var readError: String?
        do { initial = try storage.read() }
        catch {
            readError = "Your draft file could not be read. It has been left untouched at \(storage.file.path). New drafts cannot be saved until this file is repaired or moved."
            canSave = false
        }
        draft = initial.current
        drafts = initial.drafts
        activePostID = initial.current.posts[0].id
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "light"
        avatar = NSImage(contentsOf: base.appendingPathComponent("avatar.png"))
            ?? Bundle.main.url(forResource: "me", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(contentsOfFile: "me.png")
        error = readError
    }

    var activeIndex: Int { draft.posts.firstIndex(where: { $0.id == activePostID }) ?? 0 }
    var canPost: Bool { draft.posts.allSatisfy(\.valid) }

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
        guard canSave else { return false }
        var current = draft
        current.modified = Date()
        var updated = drafts.filter { $0.id != current.id }
        if current.hasContent { updated.insert(current, at: 0) }
        do {
            try storage.write(DraftArchive(current: current, drafts: updated))
            drafts = updated
            return true
        } catch {
            self.error = "Couldn't save your draft: \(error.localizedDescription)"
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

    func addPost() {
        guard draft.posts.last?.valid == true else { return }
        let post = Post()
        draft.posts.append(post)
        activePostID = post.id
    }

    func removePost(_ id: UUID) {
        guard draft.posts.count > 1 else { return }
        draft.posts.removeAll { $0.id == id }
        if activePostID == id { activePostID = draft.posts.last!.id }
    }

    func pickImages(gifOnly: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = gifOnly ? [.gif] : [.png, .jpeg, .heic, .tiff, .gif, .webP]
        panel.allowsMultipleSelection = !gifOnly
        panel.prompt = "Add"
        panel.message = gifOnly ? "Choose a GIF to attach to your post." : "Choose up to four images."
        let postID = activePostID
        panel.begin { [weak self] result in
            guard result == .OK else { return }
            self?.addImages(panel.urls, to: postID)
        }
    }

    func addImages(_ urls: [URL], to postID: UUID) {
        guard let index = draft.posts.firstIndex(where: { $0.id == postID }) else { return }
        guard draft.posts[index].poll == nil else { error = "Remove the poll before adding images."; return }
        for url in urls {
            guard draft.posts[index].attachments.count < 4 else { notify("You can attach up to 4 images."); break }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 15 * 1024 * 1024 else { error = "\(url.lastPathComponent) is larger than 15 MB."; continue }
                let data = try Data(contentsOf: url)
                guard NSImage(data: data) != nil else { error = "\(url.lastPathComponent) isn't a supported image."; continue }
                draft.posts[index].attachments.append(Attachment(name: url.lastPathComponent, data: data))
            } catch { self.error = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }

    func pasteImage(_ image: NSImage, to postID: UUID) {
        guard let index = draft.posts.firstIndex(where: { $0.id == postID }),
              draft.posts[index].attachments.count < 4, draft.posts[index].poll == nil,
              let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            notify("Remove an attachment or poll before pasting an image.")
            return
        }
        guard data.count <= 15 * 1024 * 1024 else { error = "This image is larger than 15 MB."; return }
        draft.posts[index].attachments.append(Attachment(name: "Pasted image.png", data: data))
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
            } catch { self.error = "Couldn't save your profile photo: \(error.localizedDescription)" }
        }
    }

    func notify(_ message: String) {
        toastWork?.cancel()
        toast = message
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
            error = "Couldn't open your browser. Copy your text and paste it into X."
            return
        }
        if useClipboard { notify("Text copied — paste it into X with ⌘V") }
    }

    func exportImages(_ post: Post) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save images here"
        panel.begin { [weak self] result in
            guard result == .OK, let directory = panel.url, let self else { return }
            do {
                for (i, image) in post.attachments.enumerated() {
                    let ext = (image.name as NSString).pathExtension
                    let name = "XWriter-\(image.id.uuidString.prefix(8))-\(i + 1).\(ext.isEmpty ? "png" : ext)"
                    try image.data.write(to: directory.appendingPathComponent(name), options: .atomic)
                }
                NSWorkspace.shared.open(directory)
            } catch { self.error = "Couldn't export images: \(error.localizedDescription)" }
        }
    }
}
