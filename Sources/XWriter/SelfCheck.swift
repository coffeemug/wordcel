import AppKit

enum SelfCheck {
    static func preferences(for directory: URL) -> UserDefaults {
        guard let preferences = UserDefaults(suiteName: directory.lastPathComponent) else {
            fputs("Could not create isolated test preferences.\n", stderr)
            exit(1)
        }
        return preferences
    }

    @MainActor final class SynonymStub: SynonymService {
        static let lists = SynonymLists(latin: ["assist", "aid", "support", "succor", "sustain", "facilitate"],
                                       germanic: ["back", "bolster", "uphold", "boost", "further", "foster"])
        static let expandedLists = SynonymLists(
            latin: lists.latin + ["reinforce", "abet", "benefit", "accommodate", "contribute", "serve"],
            germanic: lists.germanic + ["strengthen", "lift", "shield", "feed", "heal", "steady"])
        var result = lists
        var authenticated = true
        var signIns = 0
        var contexts: [ModelContext] = []
        var targets: [String?] { contexts.map(\.target) }
        var texts: [String] { contexts.map(\.text) }
        var models: [ClaudeModel] = []
        var efforts: [ClaudeEffort] = []
        var delay = Duration.milliseconds(100)
        var ignoreCancellation = false
        var failure: Error?
        func isAuthenticated() async throws -> Bool { authenticated }
        func signIn() async throws {
            signIns += 1
            try await Task.sleep(for: .milliseconds(100))
            authenticated = true
        }
        func synonyms(context: ModelContext, model: ClaudeModel, effort: ClaudeEffort) async throws -> SynonymLists {
            contexts.append(context)
            models.append(model)
            efforts.append(effort)
            let response = result
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return response
        }
    }

    @MainActor final class HighlightStub: HighlightService {
        var authenticated = true
        var signIns = 0
        var contexts: [ModelContext] = []
        var texts: [String] { contexts.map(\.text) }
        var prompts: [String] = []
        var models: [ClaudeModel] = []
        var efforts: [ClaudeEffort] = []
        var delay = Duration.milliseconds(100)
        var ignoreCancellation = false
        var failure: Error?
        var result = HighlightMatches(matches: [.init(text: "precise", occurrence: 1), .init(text: "clear", occurrence: 1),
                                               .init(text: "precise", occurrence: 2)])
        func isAuthenticated() async throws -> Bool { authenticated }
        func signIn() async throws { signIns += 1; authenticated = true }
        func highlights(context: ModelContext, prompt: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> HighlightMatches {
            contexts.append(context); prompts.append(prompt); models.append(model); efforts.append(effort)
            let response = result
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return response
        }
    }

    @MainActor final class PromptStub: PromptService {
        var authenticated = true
        var signIns = 0
        var prompts: [String] = []
        var contexts: [ModelContext] = []
        var targets: [String?] { contexts.map(\.target) }
        var texts: [String] { contexts.map(\.text) }
        var models: [ClaudeModel] = []
        var efforts: [ClaudeEffort] = []
        var conversationIDs: [UUID] = []
        var resumptions: [Bool] = []
        var delay = Duration.milliseconds(100)
        var ignoreCancellation = false
        var failure: Error?
        var result = "A brief answer."
        func isAuthenticated() async throws -> Bool { authenticated }
        func signIn() async throws { signIns += 1; authenticated = true }
        func reply(to prompt: String, context: ModelContext, conversation: PromptConversation,
                   model: ClaudeModel, effort: ClaudeEffort) async throws -> String {
            prompts.append(prompt); contexts.append(context); models.append(model); efforts.append(effort)
            conversationIDs.append(conversation.id); resumptions.append(conversation.hasReply)
            let answer = result
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return answer
        }
    }

    @MainActor static func interface(model: ComposerModel, window: NSWindow, synonymService: SynonymStub,
                                    highlightService: HighlightStub, promptService: PromptStub) {
        Task { @MainActor in
            var checks = 0
            func require(_ condition: @autoclosure () -> Bool, _ name: String) {
                guard condition() else { fputs("UI FAIL: \(name)\n", stderr); exit(1) }
                checks += 1
            }
            func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
            @MainActor func click(at location: NSPoint) async {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    NSApp.postEvent(event, atStart: false)
                }
                await settle()
            }
            @MainActor func clickHeader(at x: CGFloat) async {
                await click(at: NSPoint(x: x, y: window.contentView!.bounds.height - 26))
            }
            guard let editor = model.activeEditor else { fputs("UI FAIL: no active editor\n", stderr); exit(1) }
            let initialFrame = window.frame
            let autosaveName = "XWriter-UI-\(UUID())"
            window.setFrameAutosaveName(autosaveName)
            window.saveFrame(usingName: autosaveName)
            require(model.avatar != nil, "profile photo loads")
            require(window.firstResponder === editor, "editor receives initial focus")
            require(editor.bounds.width > 400, "editor has usable width")
            let emptyEcho = echoSnapshot(in: window)
            model.synonyms.lookup(in: editor, model: model.synonymModel, effort: model.synonymEffort)
            await settle()
            let errorEcho = echoSnapshot(in: window)
            require(model.echo.message == "Place the cursor in a word or select a phrase to find single-word alternatives." &&
                    emptyEcho != nil && errorEcho != emptyEcho, "invalid input renders a message in the bottom echo area")
            require(window.attachedSheet == nil && NSApp.modalWindow == nil && window.firstResponder === editor && window.frame == initialFrame,
                    "echo errors do not open a dialog, steal focus, or resize the composer")
            let longMessage = String(repeating: "Additional error details. ", count: 60) + "\nLast line of the message."
            model.notify(longMessage)
            await settle()
            require(model.echo.message == longMessage && window.frame == initialFrame && window.firstResponder === editor,
                    "long multiline messages retain all details without changing the editor's layout or focus")
            model.notify("Draft saved")
            await settle()
            require(model.echo.message == "Draft saved" && echoSnapshot(in: window) != errorEcho,
                    "informational messages replace errors in the same echo area")
            let oldPhotoShortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                    context: nil, characters: "o", charactersIgnoringModifiers: "o", isARepeat: false, keyCode: 31)!
            require(NSApp.mainMenu?.performKeyEquivalent(with: oldPhotoShortcut) != true, "photo import has no menu shortcut")
            editor.insertText("Hello #native", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(model.draft.posts[0].text == "Hello #native",
                    "native typing updates the model (model=\(model.draft.posts[0].text.debugDescription), editor=\(editor.string.debugDescription), active=\(model.activeEditor === editor), attached=\(editor.window === window))")
            editor.breakUndoCoalescing()
            editor.undoManager?.undo()
            require(model.draft.posts[0].text.isEmpty, "native undo")
            editor.undoManager?.redo()
            require(model.draft.posts[0].text == "Hello #native", "native redo")
            let editorWidth = editor.bounds.width
            await clickHeader(at: initialFrame.width - 25)
            require(model.echo.message == nil, "clicking the drawer icon clears the previous message")
            require(model.showDrafts && window.attachedSheet == nil, "drafts open without a dialog")
            require(abs(window.frame.width - initialFrame.width - ComposerWindowSizing.drawerWidth) < 1, "drawer widens the window")
            require(abs(editor.bounds.width - editorWidth) < 1, "drawer preserves composer width")
            require(abs(window.frame.height - initialFrame.height) < 2, "drawer does not change composer height")
            require(model.drafts.first?.posts[0].text == "Hello #native", "opening the drawer saves current text")
            editor.insertText(" with drawer", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(model.draft.posts[0].text == "Hello #native with drawer", "composer remains editable with drawer open")
            window.setFrameOrigin(NSPoint(x: window.frame.minX - 20, y: window.frame.minY + 10))
            await settle()
            let movedOrigin = window.frame.origin
            var closingOrigins: [NSPoint] = []
            let moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { closingOrigins.append(window.frame.origin) }
            }
            await clickHeader(at: initialFrame.width - 25)
            NotificationCenter.default.removeObserver(moveObserver)
            closingOrigins.append(window.frame.origin)
            window.setFrameAutosaveName("")
            NSWindow.removeFrame(usingName: autosaveName)
            require(closingOrigins.allSatisfy { $0 == movedOrigin }, "closing drawer never moves a repositioned autosaved window")
            require(!model.showDrafts, "same icon closes the drawer")
            require(abs(window.frame.width - initialFrame.width) < 1, "closing restores the composer width")
            require(window.firstResponder === editor, "closing the drawer returns focus to the editor")
            editor.insertText(String(repeating: "\nA line of text", count: 12), replacementRange: NSRange(location: NSNotFound, length: 0))
            await settle()
            require(editor.bounds.height > 250, "multiline editor grows")
            require(window.frame.height > initialFrame.height + 100, "window expands with text")
            require(abs(window.frame.width - initialFrame.width) < 1, "automatic growth preserves width")

            editor.insertText(String(repeating: "\nA line of text that wraps across the composer and keeps the scrollbar visible while the drawer opens and closes.", count: 80),
                              replacementRange: NSRange(location: NSNotFound, length: 0))
            await settle()
            require(window.frame.height <= ComposerWindowSizing.maximumHeight + 1, "window growth is capped")
            require(editor.bounds.height > window.frame.height, "long text scrolls within the capped window")
            require(model.canPost, "Premium posts can exceed 280 characters")
            if let screen = window.screen {
                require(screen.visibleFrame.insetBy(dx: -1, dy: -1).contains(window.frame), "window stays on screen")
            }
            if let layout = editor.layoutManager, let container = editor.textContainer {
                let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: editor.string.utf16.count - 1, length: 1), actualCharacterRange: nil)
                let caret = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: 0, dy: editor.textContainerInset.height)
                require(editor.visibleRect.intersects(caret), "caret remains visible after reaching the height cap")
            }
            model.toggleDrafts()
            await settle()
            guard let scroll = editor.enclosingScrollView else {
                fputs("UI FAIL: no composer scroll view\n", stderr); exit(1)
            }
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: 300))
            scroll.reflectScrolledClipView(clip)
            await settle()
            let viewport = scroll.convert(scroll.bounds, to: window.contentView)
            let offset = clip.bounds.origin
            var viewports: [NSRect] = []
            var offsets: [NSPoint] = []
            let postedFrames = scroll.postsFrameChangedNotifications
            let postedBounds = clip.postsBoundsChangedNotifications
            scroll.postsFrameChangedNotifications = true
            clip.postsBoundsChangedNotifications = true
            let frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll, queue: .main) { _ in
                MainActor.assumeIsolated { viewports.append(scroll.convert(scroll.bounds, to: window.contentView)) }
            }
            let scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { _ in
                MainActor.assumeIsolated { offsets.append(clip.bounds.origin) }
            }
            await clickHeader(at: initialFrame.width - 25)
            NotificationCenter.default.removeObserver(frameObserver)
            NotificationCenter.default.removeObserver(scrollObserver)
            scroll.postsFrameChangedNotifications = postedFrames
            clip.postsBoundsChangedNotifications = postedBounds
            viewports.append(scroll.convert(scroll.bounds, to: window.contentView))
            offsets.append(clip.bounds.origin)
            require(viewports.allSatisfy { abs($0.minX - viewport.minX) < 1 && abs($0.minY - viewport.minY) < 1 &&
                abs($0.width - viewport.width) < 1 && abs($0.height - viewport.height) < 1 },
                    "closing drawer never changes the composer viewport size or position")
            require(offsets.allSatisfy { abs($0.x - offset.x) < 1 && abs($0.y - offset.y) < 1 },
                    "closing drawer never changes scroll position")
            let removedShortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                   context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            NSApp.postEvent(removedShortcut, atStart: false)
            await settle()
            require(model.draft.posts.count == 1 && !model.showHandoff, "retired thread shortcut neither adds a post nor opens publishing")
            editor.selectAll(nil)
            editor.insertText("First post", replacementRange: editor.selectedRange())
            await settle()
            require(abs(window.frame.height - initialFrame.height) < 2, "deleting text shrinks the window")
            let legacyPost = Post()
            model.draft.posts.append(legacyPost)
            model.activePostID = legacyPost.id
            await settle()
            require(model.draft.posts.count == 2, "existing threads still render multiple editors")
            guard let second = model.activeEditor else { exit(1) }
            require(second !== editor && window.firstResponder === second, "existing thread posts can receive focus")
            second.insertText("Second post", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(model.draft.posts[1].text == "Second post" && model.canPost, "second editor binds to its own post")
            model.removePost(model.draft.posts[1].id)
            window.setContentSize(NSSize(width: 560, height: 300 + ComposerWindowSizing.echoAreaHeight))
            await settle()
            require(model.activeEditor === editor, "focus returns after removing a post")
            require(abs(editor.bounds.width - (editorWidth + 560 - initialFrame.width)) < 1, "manual resizing still updates the editor width")
            let draftsShortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2)!
            require(NSApp.mainMenu?.performKeyEquivalent(with: draftsShortcut) == true, "Command-D activates the drafts menu action")
            await settle()
            require(model.showDrafts, "Command-D opens the drawer")
            let savedDraft = model.drafts.first(where: { $0.id == model.draft.id })!
            await clickHeader(at: window.contentView!.bounds.width - 46)
            require(model.showDrafts && !model.draft.hasContent, "new post link creates a draft and keeps drawer open")
            require(model.activeEditor === window.firstResponder, "new post link focuses the new editor")
            model.load(savedDraft)
            await settle()
            require(model.showDrafts && model.draft.posts[0].text == "First post", "switching drafts keeps drawer open")
            require(model.activeEditor === window.firstResponder, "restored draft receives editor focus")
            await drawerDeletionInterface(model: model, window: window) { require($0, $1) }
            window.setContentSize(NSSize(width: 1000, height: window.contentView!.bounds.height))
            window.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
            await settle()
            require(NSApp.mainMenu?.performKeyEquivalent(with: draftsShortcut) == true, "Command-D works with drawer open")
            await settle()
            require(!model.showDrafts, "Command-D closes the drawer")
            require(abs(window.frame.width - (1000 - ComposerWindowSizing.drawerWidth)) < 1, "closing respects resizing while drawer is open")
            let notesOnly = CommandLine.arguments.contains("--highlight-notes-only")
            if !notesOnly {
                await promptInterface(model: model, window: window, service: promptService) { require($0, $1) }
                await replyLayoutInterface(model: model, window: window, service: promptService) { require($0, $1) }
                await synonymInterface(model: model, window: window, service: synonymService) { require($0, $1) }
                await sharedContextInterface(model: model, window: window, synonyms: synonymService,
                                             highlights: highlightService, prompts: promptService) { require($0, $1) }
            }
            await highlightNotesInterface(model: model, window: window, service: highlightService) { require($0, $1) }
            let synonymsOnly = CommandLine.arguments.contains("--synonyms-only")
            if !synonymsOnly && !notesOnly {
                await highlightInterface(model: model, window: window, service: highlightService) { require($0, $1) }
            }
            if (!synonymsOnly && !notesOnly) || CommandLine.arguments.contains("--with-cli-checks") {
                await commandChecks(log: model.modelLog) { require($0, $1) }
            }
            if !notesOnly { await modelLogInterface(model: model, window: window) { require($0, $1) } }
            require(model.save(), "edited content persists")
            UserDefaults.standard.removePersistentDomain(forName: model.storage.directory.lastPathComponent)
            try? FileManager.default.removeItem(at: model.storage.directory)
            let coverage = notesOnly ? "editing, drafts drawer, sizing, highlight notes, minibuffer priority, and persistence" :
                synonymsOnly ? "editing, drafts drawer, sizing, minibuffer prompts, synonym overlay, and persistence" :
                "editing, drafts drawer, sizing, minibuffer prompts, synonyms, highlights, settings, CLI lifecycle, focus, and persistence"
            print("Passed \(checks) native UI checks: \(coverage).")
            exit(0)
        }
    }

    @MainActor static func run() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            count += 1
        }
        check(TweetLength.count("") == 0, "empty text")
        check(CharacterCounterState(count: 259).countdown == nil, "counter stays unnumbered before the last 20 standard characters")
        check(CharacterCounterState(count: 260).countdown == 20, "standard countdown begins at 20")
        check(CharacterCounterState(count: 279).countdown == 1, "standard countdown ends at 1")
        check(CharacterCounterState(count: 280).countdown == nil && CharacterCounterState(count: 280).fillProgress == 0,
              "280 switches immediately to unnumbered bottom fill")
        check(CharacterCounterState(count: 281).countdown == nil && CharacterCounterState(count: 281).fillProgress! > 0,
              "long posts fill without a negative standard countdown")
        check(CharacterCounterState(count: 281).isExpanded, "circle stays enlarged after the transition")
        check(CharacterCounterState(count: 24_980).countdown == 20, "Premium limit still warns at 20 remaining")
        check(CharacterCounterState(count: 25_001).countdown == -1, "Premium overflow remains visible")
        check(TweetLength.count(String(repeating: "a", count: 280)) == 280, "ASCII limit")
        check(TweetLength.count("你好世界") == 8, "CJK weighted characters")
        check(TweetLength.count("👨‍👩‍👧‍👦") == 2, "joined emoji")
        check(TweetLength.count("🇺🇸👍🏽❤️1️⃣") == 8, "flags, skin tones, variation and keycaps")
        check(TweetLength.count("e\u{301}") == 1, "Unicode normalization")
        check(TweetLength.count("Hello https://example.com/a/very/long/path") == 29, "URL shortening")
        check(TweetLength.count("https://a.com https://b.com") == 47, "multiple URLs")
        check(!Post().valid, "empty post cannot be posted")
        check(!Post(text: " \n\t ").valid, "whitespace cannot be posted")
        check(Post(text: String(repeating: "x", count: 281)).valid, "Premium accepts more than 280 characters")
        check(Post(text: String(repeating: "x", count: 25_000)).valid, "Premium accepts exactly 25,000 characters")
        check(!Post(text: String(repeating: "x", count: 25_001)).valid, "Premium rejects more than 25,000 characters")
        check(!Post(text: String(repeating: "界", count: 12_501)).valid, "Premium enforces weighted length")
        check(ComposerModel.requiresClipboardHandoff(String(repeating: "x", count: 25_000)), "long posts use clipboard handoff")
        check(!ComposerModel.requiresClipboardHandoff("Hello"), "short posts use direct handoff")
        check(Post(text: String(repeating: "x", count: 280)).valid, "exact limit can be posted")
        let original = "Hello & goodbye? #swift + 日本語 👋\nSecond line"
        let url = ComposerModel.intentURL(for: original)
        check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == original, "handoff URL encoding")
        let targetText = "😀 Help, help."
        let helpRange = (targetText as NSString).range(of: "Help")
        let target = SynonymTarget.capture(text: targetText, selection: NSRange(location: helpRange.location + 2, length: 0))
        check(target?.query == "Help" && target?.range == helpRange, "synonyms target the word under a UTF-16 cursor")
        check(ModelContext.capture(text: targetText, selection: NSRange(location: helpRange.location + 2, length: 0))?.target == "Help",
              "shared model context captures the word at a Unicode-aware cursor")
        check(ModelContext.capture(text: targetText, selection: NSRange(location: helpRange.location + 1, length: 2))?.target == "el" &&
              SynonymTarget.capture(text: targetText, selection: NSRange(location: helpRange.location + 1, length: 2))?.query == "el",
              "every feature uses an exact partial-word selection rather than expanding it")
        check(ModelContext.capture(text: "  😀 123\n", selection: NSRange(location: 0, length: 9))?.target == "  😀 123\n" &&
              ModelContext.capture(text: "", selection: NSRange(location: 0, length: 0))?.text == "" &&
              ModelContext.capture(text: targetText, selection: NSRange(location: 8, length: 0))?.target == nil &&
              ModelContext.capture(text: targetText, selection: NSRange(location: 8, length: 0))?.text == targetText,
              "shared context preserves arbitrary selections and still supplies a paragraph when there is no cursor word")
        for separator in ["\n", "\r\n", "\u{2029}"] {
            let paragraph = "😀 First sentence. Help again.\(separator)"
            let document = "Outside.\(separator)\(paragraph)Not sent."
            let selected = (document as NSString).range(of: "Help")
            let captured = ModelContext.capture(text: document, selection: selected)
            check(captured?.text == paragraph && captured?.range == (document as NSString).range(of: paragraph) &&
                  captured?.target == "Help", "context includes all sentences in just one paragraph with \(separator.debugDescription) boundaries")
            let span = (document as NSString).range(of: "again.\(separator)Not")
            let across = ModelContext.capture(text: document, selection: span)
            check(across?.text == "again.\(separator)Not" && across?.target == across?.text && across?.range == span,
                  "cross-paragraph selections send only their exact text and retain absolute UTF-16 offsets")
            let wholeParagraph = (document as NSString).range(of: paragraph)
            check(ModelContext.capture(text: document, selection: wholeParagraph)?.text == paragraph,
                  "a selection ending at the next paragraph's start does not include that paragraph")
        }
        check(ModelContext.capture(text: "First.\n\nLast.", selection: NSRange(location: 7, length: 0))?.text == "\n" &&
              ModelContext.capture(text: "First.\n", selection: NSRange(location: 7, length: 0))?.text == "",
              "blank paragraphs and end-of-document cursors do not borrow neighboring paragraphs")
        check(ModelContext.capture(text: "😀 word", selection: NSRange(location: 1, length: 0)) == nil &&
              ModelContext.capture(text: "word", selection: NSRange(location: NSNotFound, length: 0)) == nil &&
              ModelContext.capture(text: "word", selection: NSRange(location: 0, length: 5)) == nil,
              "invalid UTF-16 selections are rejected before paragraph extraction")
        check(target?.matches(text: targetText, selection: NSRange(location: helpRange.location, length: 0)) == true &&
              target?.matches(text: targetText, selection: NSRange(location: NSMaxRange(helpRange), length: 0)) == true &&
              target?.matches(text: targetText, selection: helpRange) == true,
              "synonyms survive cursor movement and selection within the target word")
        check(target?.matches(text: "😀 Help, someone.", selection: helpRange) == true,
              "changes outside the target word do not invalidate synonyms")
        check(target?.matches(text: "😀 Yelp, help.", selection: helpRange) == false,
              "changing the target word invalidates synonyms even at the same range")
        check(target?.matches(text: "😀 Help, Help.", selection: NSRange(location: 10, length: 0)) == false &&
              target?.matches(text: targetText, selection: NSRange(location: 8, length: 0)) == false &&
              target?.matches(text: targetText, selection: NSRange(location: helpRange.location, length: 8)) == false,
              "another occurrence, whitespace, or a selection beyond the word invalidates synonyms")
        check(target?.replacement("assist") == "Assist", "synonym replacement preserves capitalization")
        check(SynonymTarget.capture(text: "HELP", selection: NSRange(location: 4, length: 0))?.replacement("assist") == "ASSIST",
              "synonyms support end-of-word cursors and uppercase")
        let phraseText = "😀 Please lend a hand with this, then lend a hand."
        let phraseRange = (phraseText as NSString).range(of: "lend a hand")
        let phraseSelection = NSRange(location: phraseRange.location - 1, length: phraseRange.length + 2)
        let phrase = SynonymTarget.capture(text: phraseText, selection: phraseSelection)
        check(phrase?.query == "lend a hand" && phrase?.range == phraseRange && phrase?.context.text == phraseText &&
              phrase?.context.target == " lend a hand ",
              "model context keeps the exact selection while synonym replacement preserves its outer whitespace")
        check(phrase?.matches(text: phraseText, selection: phraseSelection) == true &&
              phrase?.matches(text: phraseText, selection: phraseRange) == true &&
              phrase?.matches(text: phraseText, selection: NSRange(location: phraseRange.location, length: 4)) == false,
              "phrase results stay valid for the same target and dismiss when selecting a different target")
        check(SynonymTarget.capture(text: "Lend a hand", selection: NSRange(location: 0, length: 11))?.replacement("assist") == "Assist" &&
              SynonymTarget.capture(text: "LEND A HAND", selection: NSRange(location: 0, length: 11))?.replacement("assist") == "ASSIST",
              "phrase replacement preserves initial and all-caps capitalization")
        let acrossSentences = "Before. Lend a hand.\nHelp out. After."
        let acrossRange = (acrossSentences as NSString).range(of: "a hand.\nHelp")
        check(SynonymTarget.capture(text: acrossSentences, selection: acrossRange)?.context.text == "a hand.\nHelp",
              "cross-paragraph synonym context contains only the selection")
        check(SynonymTarget.capture(text: "  😀 123", selection: NSRange(location: 1, length: 0)) == nil,
              "synonyms reject whitespace and nonword targets")
        check(SynonymTarget.capture(text: "  😀 123", selection: NSRange(location: 0, length: 8)) == nil,
              "selected phrases must contain letters")
        for (text, expected) in [
            ("Earlier news. 😀 With each update add something nice. Keep it simple.", "Earlier news. 😀 With each update add something nice. Keep it simple."),
            ("First line.\n\nwith each update add something nice", "with each update add something nice"),
            ("We update the draft. Each update adds something nice.", "We update the draft. Each update adds something nice.")
        ] {
            let range = (text as NSString).range(of: "update", options: .backwards)
            let target = SynonymTarget.capture(text: text, selection: NSRange(location: NSMaxRange(range), length: 0))
            check(target?.query == "update" && target?.context.text == expected, "lookup extracts the entire target paragraph: \(expected)")
        }
        do {
            let reply = try ClaudeCLI.decodePrompt(.init(status: 0, output: Data(#"{"type":"result","is_error":false,"structured_output":{"answer":" A short reply. "}}"#.utf8)))
            check(reply == "A short reply.",
                  "model replies decode structured output and trim surrounding whitespace")
            for invalid in [
                #"{"type":"result","is_error":false,"structured_output":{"answer":" \n "}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"answer":123}}"#,
                #"{"type":"result","is_error":false,"result":"Missing structured output"}"#,
                #"{"type":"result","is_error":true,"result":"Usage limit reached"}"#
            ] {
                do {
                    _ = try ClaudeCLI.decodePrompt(.init(status: 0, output: Data(invalid.utf8)))
                    check(false, "invalid model replies must fail")
                } catch { check(true, "invalid model replies are surfaced") }
            }
            let response = ClaudeCommand.Result(status: 0, output: Data(#"{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["back"]}}"#.utf8))
            let lists = try ClaudeCLI.decode(response)
            check(lists.latin == ["assist"] && lists.germanic == ["back"], "Claude structured synonym output is decoded")
            let expanded = SynonymStub.expandedLists
            let expandedData = try JSONSerialization.data(withJSONObject: [
                "type": "result", "is_error": false, "structured_output": ["latin": expanded.latin, "germanic": expanded.germanic]
            ])
            let expandedResult = try ClaudeCLI.decode(.init(status: 0, output: expandedData))
            check(expandedResult == expanded, "all twelve alternatives in each group survive decoding and validation")
            for invalid in [
                #"{"type":"result","is_error":false,"result":"No structured output"}"#,
                #"{"type":"result","is_error":true,"result":"Usage limit reached"}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["assist\nignore"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["progress report"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["prop up"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["re-form"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["write-up"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["write\u2010up"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["progress\u00a0report"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["Assist"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["a","b","c","d","e","f","g","h","i","j","k","l","m"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["a","b","c","d","e","f","g","h","i","j","k","l","m"]}}"#
            ] {
                do {
                    _ = try ClaudeCLI.decode(ClaudeCommand.Result(status: 0, output: Data(invalid.utf8)))
                    check(false, "invalid Claude output must fail")
                } catch { check(true, "invalid Claude output is surfaced") }
            }
        } catch { check(false, "valid Claude output failed: \(error)") }
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let frame = NSRect(x: 100, y: 500, width: 600, height: 332)
        let expanded = ComposerWindowSizing.frame(current: frame, contentHeight: 500, screen: screen)
        check(expanded.height == 500 && expanded.maxY == frame.maxY, "growth keeps the top edge anchored")
        let capped = ComposerWindowSizing.frame(current: frame, contentHeight: 2000, screen: screen)
        check(capped.height == 760, "growth caps at 760 points")
        let smallScreen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let fitted = ComposerWindowSizing.frame(current: frame, contentHeight: 2000, screen: smallScreen)
        check(fitted.height == 552 && smallScreen.contains(fitted), "growth fits smaller screens")
        let shrunk = ComposerWindowSizing.frame(current: expanded, contentHeight: 200, screen: screen)
        check(shrunk.height == ComposerWindowSizing.minimumHeight && shrunk.maxY == expanded.maxY, "shrinking preserves the top edge and minimum height")
        let drawerFrame = ComposerWindowSizing.frame(current: frame, composerWidth: frame.width, showingDrafts: true, screen: screen)
        check(drawerFrame.width == frame.width + ComposerWindowSizing.drawerWidth && drawerFrame.origin == frame.origin &&
              drawerFrame.height == frame.height, "drawer expands to the right without changing composer size")
        let edgeFrame = NSRect(x: 800, y: 500, width: 600, height: 332)
        let edgeDrawer = ComposerWindowSizing.frame(current: edgeFrame, composerWidth: edgeFrame.width, showingDrafts: true, screen: screen)
        check(screen.contains(edgeDrawer) && edgeDrawer.maxX == screen.maxX, "drawer shifts window left at the screen edge")
        let constrainedScreen = NSRect(x: -1024, y: 0, width: 1024, height: 1000)
        let wideFrame = NSRect(x: -1000, y: 500, width: 800, height: 332)
        let constrainedDrawer = ComposerWindowSizing.frame(current: wideFrame, composerWidth: wideFrame.width, showingDrafts: true, screen: constrainedScreen)
        check(constrainedScreen.contains(constrainedDrawer), "drawer fits the available screen width on another display")
        let closedDrawer = ComposerWindowSizing.frame(current: constrainedDrawer, composerWidth: wideFrame.width, showingDrafts: false, screen: constrainedScreen)
        check(closedDrawer.width == wideFrame.width && closedDrawer.height == wideFrame.height, "closing restores width after screen-constrained expansion")
        let movedDrawer = drawerFrame.offsetBy(dx: -150, dy: -30)
        let closedMovedDrawer = ComposerWindowSizing.frame(current: movedDrawer, composerWidth: frame.width, showingDrafts: false, screen: screen)
        check(closedMovedDrawer.origin == movedDrawer.origin, "closing preserves a moved window's origin even when partly offscreen")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-check-\(UUID())")
        defer {
            UserDefaults.standard.removePersistentDomain(forName: directory.lastPathComponent)
            try? FileManager.default.removeItem(at: directory)
        }
        let preferences = SelfCheck.preferences(for: directory)
        let store = DraftStorage(directory: directory)
        do {
            let fresh = try store.read()
            check(fresh.drafts.isEmpty, "fresh storage")
            let model = ComposerModel(directory: directory, preferences: preferences)
            check(model.synonymModel == .fable && model.synonymEffort == .medium, "new installs default to Fable 5.1 with medium effort")
            model.synonymModel = .sonnet
            model.synonymEffort = .high
            model.draft.posts[0].text = "First draft"
            model.draft.audience = .following
            let firstID = model.draft.id
            check(model.save(), "save first draft")
            check(model.drafts.count == 1, "saved draft appears in library")
            model.draft.posts[0].text = "Revised draft"
            model.toggleDrafts()
            check(model.showDrafts && model.drafts.first?.posts[0].text == "Revised draft", "opening drawer saves pending edits")
            model.toggleDrafts()
            check(!model.showDrafts, "drawer toggle closes an open drawer")
            check(model.save() && model.drafts.count == 1, "saving updates without duplication")
            let restored = ComposerModel(directory: directory, preferences: SelfCheck.preferences(for: directory))
            check(restored.synonymModel == .sonnet && restored.synonymEffort == .high, "model and reasoning restore from a fresh preferences instance")
            check(restored.draft.posts[0].text == "Revised draft", "restore text")
            check(restored.draft.audience == .following, "restore reply metadata")
            model.draft.posts.append(Post())
            check(model.draft.posts.count == 2 && !model.canPost, "empty thread post prevents handoff")
            model.draft.posts[1].text = "Second post"
            check(model.canPost, "completed thread allows handoff")
            model.toggleDrafts()
            model.newDraft()
            check(!model.draft.hasContent && model.drafts.count == 1, "new draft preserves old draft")
            check(model.showDrafts, "creating a draft keeps drawer open")
            model.draft.posts[0].text = "Another draft"
            check(model.save() && model.drafts.count == 2, "multiple saved drafts")
            model.load(model.drafts.first(where: { $0.id == firstID })!)
            check(model.synonymModel == .sonnet && model.synonymEffort == .high, "model and reasoning are independent of the active draft")
            check(model.draft.posts.count == 2 && model.draft.posts[1].text == "Second post", "restore thread")
            check(model.showDrafts, "loading a draft keeps drawer open")
            model.removePost(model.draft.posts[1].id)
            check(model.draft.posts.count == 1 && model.activePostID == model.draft.posts[0].id, "remove thread post")
            model.requestDeleteDraft(firstID)
            check(model.echo.expectsInput && model.echo.message?.contains("(y/n)") == true && model.drafts.contains(where: { $0.id == firstID }),
                  "requesting deletion asks in the echo area without deleting")
            check(model.echo.respond(yes: false) && !model.echo.expectsInput && model.draft.id == firstID && model.echo.message == nil,
                  "a negative answer cancels deletion")
            model.requestDeleteDraft(firstID)
            model.echo.clear()
            check(!model.echo.expectsInput && !model.echo.respond(yes: true) && model.draft.id == firstID, "clearing a prompt cancels its pending deletion")
            model.requestDeleteDraft(firstID)
            model.notify("A newer message")
            check(!model.echo.expectsInput && !model.echo.respond(yes: true) && model.draft.id == firstID, "a replacement message cannot leave a hidden deletion pending")
            model.requestDeleteDraft(firstID)
            check(model.echo.respond(yes: true) && !model.echo.respond(yes: true), "affirmative confirmation performs the deletion exactly once")
            check(!model.draft.hasContent && model.drafts.count == 1, "delete current draft")
            let afterDelete = try store.read()
            check(afterDelete.drafts.allSatisfy { $0.id != firstID }, "deletion persists")
            let remainingID = model.drafts[0].id
            try FileManager.default.removeItem(at: store.file)
            try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: false)
            model.requestDeleteDraft(remainingID)
            check(model.echo.respond(yes: true) && model.drafts.contains(where: { $0.id == remainingID }) &&
                  model.echo.message?.hasPrefix("Couldn't save your draft:") == true,
                  "failed confirmed deletion rolls back and keeps its error in the echo area")
            try FileManager.default.removeItem(at: store.file)
            try Data("bad json".utf8).write(to: store.file)
            let protected = ComposerModel(directory: directory, preferences: preferences)
            check(protected.echo.message != nil && !protected.save(), "corrupt storage is protected and reported in the echo area")
            protected.notify("Another message")
            check(!protected.save() && protected.echo.message != "Another message", "blocked saves repeat the storage error rather than failing silently")
            let untouched = try Data(contentsOf: store.file)
            check(untouched == Data("bad json".utf8), "corrupt file is not overwritten")

            let legacyStore = DraftStorage(directory: directory.appendingPathComponent("legacy"))
            let legacyPost: [String: Any] = [
                "id": UUID().uuidString, "text": "Keep this writing",
                "attachments": [["id": UUID().uuidString, "name": "old.gif", "data": "AQID", "alt": "Old image"]],
                "poll": ["choices": ["Yes", "No"], "days": 1, "hours": 0, "minutes": 0]
            ]
            let legacyID = UUID()
            let legacyDraft: [String: Any] = [
                "id": legacyID.uuidString,
                "posts": [legacyPost, ["id": UUID().uuidString, "text": "Second post", "attachments": []]],
                "audience": "following", "plannedDate": 12345, "modified": 0
            ]
            var mediaOnlyPost = legacyPost
            mediaOnlyPost["text"] = ""
            let mediaOnlyDraft: [String: Any] = [
                "id": UUID().uuidString, "posts": [mediaOnlyPost], "audience": "everyone", "modified": 0
            ]
            let legacyData = try JSONSerialization.data(withJSONObject: [
                "version": 1, "current": legacyDraft, "drafts": [legacyDraft, mediaOnlyDraft]
            ])
            try FileManager.default.createDirectory(at: legacyStore.directory, withIntermediateDirectories: true)
            try legacyData.write(to: legacyStore.file)
            let migrated = try legacyStore.read()
            check(migrated.version == 2 && migrated.current.id == legacyID &&
                  migrated.current.posts.map(\.text) == ["Keep this writing", "Second post"] && migrated.current.audience == .following,
                  "archive migration preserves writing, thread posts, identities, and reply metadata")
            check(migrated.drafts.map(\.id) == [legacyID], "migration removes saved drafts whose only content was retired feature data")
            func containsRetiredFields(_ value: Any) -> Bool {
                if let object = value as? [String: Any] {
                    return object.keys.contains { ["attachments", "poll", "plannedDate"].contains($0) } ||
                        object.values.contains(where: containsRetiredFields)
                }
                if let array = value as? [Any] { return array.contains(where: containsRetiredFields) }
                return false
            }
            let migratedData = try Data(contentsOf: legacyStore.file)
            let migratedJSON = try JSONSerialization.jsonObject(with: migratedData)
            check(!containsRetiredFields(migratedJSON),
                  "migration permanently removes retired data from current and saved drafts")
            _ = try legacyStore.read()
            let rereadData = try Data(contentsOf: legacyStore.file)
            check(rereadData == migratedData, "current archives do not repeat the migration")
            let emptyLegacyData = try JSONSerialization.data(withJSONObject: [
                "version": 1, "current": mediaOnlyDraft, "drafts": [mediaOnlyDraft]
            ])
            try emptyLegacyData.write(to: legacyStore.file)
            let emptyMigrated = try legacyStore.read()
            check(emptyMigrated.current.posts.count == 1 && !emptyMigrated.current.hasContent && emptyMigrated.drafts.isEmpty,
                  "retiring media-only content preserves an empty current editor")
            let futureData = try JSONSerialization.data(withJSONObject: [
                "version": 3, "current": legacyDraft, "drafts": [legacyDraft]
            ])
            try futureData.write(to: legacyStore.file)
            let futureModel = ComposerModel(directory: legacyStore.directory, preferences: preferences)
            check(futureModel.echo.message != nil && !futureModel.save(), "unsupported archive versions cannot be overwritten")
            let untouchedFuture = try Data(contentsOf: legacyStore.file)
            check(untouchedFuture == futureData, "unsupported archive remains untouched")
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        highlightChecks { check($0, $1) }
        print("Passed \(count) checks: character weighting, post validation, URL encoding, drafts, threads, archive migration, highlights, settings, and storage recovery.")
    }

    @MainActor private static func highlightChecks(check: (Bool, String) -> Void) {
        do {
            let text = "😀 clear, clear; é e\u{301}."
            let matches = HighlightMatches(matches: [.init(text: "clear", occurrence: 2), .init(text: "é", occurrence: 1),
                                                     .init(text: "e\u{301}", occurrence: 1)])
            let ranges = try matches.ranges(in: text)
            check(ranges == [NSRange(location: 10, length: 5), NSRange(location: 17, length: 1), NSRange(location: 19, length: 2)],
                  "highlight quotes resolve repeated text, emoji offsets, and distinct Unicode encodings")
            let annotated = try JSONDecoder().decode(HighlightMatches.self, from: Data("""
            {"matches":[{"text":"clear","occurrence":2,"note":" Second occurrence. "},{"text":"é","occurrence":1},
                        {"text":"clear","occurrence":1,"note":"First occurrence."},{"text":"é","occurrence":1,"note":"  \\n "}]}
            """.utf8))
            let resolved = try annotated.intervals(in: text)
            check(resolved.map(\.note) == ["First occurrence.", "Second occurrence.", nil, nil] &&
                  resolved.map(\.range) == [NSRange(location: 3, length: 5)] + ranges,
                  "optional interval notes stay paired with exact occurrences when results are sorted; empty notes are omitted")
            let shifted = HighlightEdit(range: NSRange(location: 0, length: 0), replacementLength: 3).applying(to: resolved)
            let edited = HighlightEdit(range: NSRange(location: 7, length: 1), replacementLength: 2).applying(to: shifted)
            check(shifted[1].note == "Second occurrence." && shifted[1].range.location == 13 &&
                  edited.first?.note == "Second occurrence." && edited.first?.range.location == 14,
                  "edits shift notes with their intervals and remove the note when its span is invalidated")
            do {
                _ = try JSONDecoder().decode(HighlightMatches.self, from: Data(#"{"matches":[{"text":"clear","occurrence":1,"note":12}]}"#.utf8))
                check(false, "non-text interval notes must fail")
            } catch { check(true, "wrongly typed interval notes fail decoding instead of losing their metadata") }
            for invalid in [
                HighlightMatches(matches: [.init(text: "absent", occurrence: 1)]),
                HighlightMatches(matches: [.init(text: "clear", occurrence: 3)]),
                HighlightMatches(matches: [.init(text: "clear", occurrence: 0)]),
                HighlightMatches(matches: [.init(text: "", occurrence: 1)]),
                HighlightMatches(matches: [.init(text: "\u{301}", occurrence: 1)]),
                HighlightMatches(matches: [.init(text: "clear", occurrence: 1), .init(text: "clear", occurrence: 1)])
            ] {
                do { _ = try invalid.ranges(in: text); check(false, "invalid intervals must fail") }
                catch HighlightError.invalidResponse { check(true, "invalid, duplicate, or split-grapheme intervals are rejected") }
            }
            check(try HighlightMatches(matches: []).ranges(in: text).isEmpty, "no matches is a valid response")
            check(try HighlightMatches(matches: [.init(text: "ana", occurrence: 1), .init(text: "ana", occurrence: 2)]).ranges(in: "banana") ==
                  [NSRange(location: 1, length: 3), NSRange(location: 3, length: 3)], "overlapping quoted occurrences resolve independently")
            let spans = [NSRange(location: 4, length: 3), NSRange(location: 12, length: 4), NSRange(location: 20, length: 2)]
            check(HighlightEdit(range: NSRange(location: 5, length: 0), replacementLength: 0).applying(to: spans) == spans,
                  "empty edits leave highlights unchanged")
            check(HighlightEdit(range: NSRange(location: 5, length: 0), replacementLength: 2).applying(to: spans) ==
                  [NSRange(location: 14, length: 4), NSRange(location: 22, length: 2)],
                  "inserting inside a highlight removes it and shifts later intervals")
            check(HighlightEdit(range: NSRange(location: 0, length: 3), replacementLength: 0).applying(to: spans) ==
                  [NSRange(location: 1, length: 3), NSRange(location: 9, length: 4), NSRange(location: 17, length: 2)],
                  "deletion before highlights shifts them without clearing them")
            check(HighlightEdit(range: NSRange(location: 6, length: 8), replacementLength: 1).applying(to: spans) ==
                  [NSRange(location: 13, length: 2)],
                  "selection replacement removes every intersecting interval and shifts the rest")
            check(HighlightEdit(range: NSRange(location: 7, length: 0), replacementLength: 1).applying(to: spans).count == 2 &&
                  HighlightEdit(range: NSRange(location: 12, length: 0), replacementLength: 1).applying(to: spans).count == 2,
                  "typing at a highlight edge clears the affected span")
            check(PromptIcon.allCases.flatMap(\.symbolNames).allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil },
                  "every toolbar library icon is available on this Mac")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-toolbar-\(UUID())")
            let defaults = preferences(for: directory)
            defer { UserDefaults.standard.removePersistentDomain(forName: directory.lastPathComponent) }
            let settings = PromptToolbarSettings(preferences: defaults)
            check(settings.buttons.count == 2 && settings.buttons.allSatisfy(\.isConfigured), "toolbar starts with two editable examples")
            var legacyButtons = settings.buttons
            legacyButtons[0].name = "Roots"
            legacyButtons[0].icon = .leaf
            legacyButtons.append(PromptButton(name: "Custom", icon: .leaf, prompt: "Highlight concrete nouns."))
            legacyButtons.append(PromptButton(name: "Latin words", icon: .book, prompt: "Highlight borrowed terms."))
            guard let objects = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyButtons)) as? [[String: Any]] else {
                throw CocoaError(.coderReadCorrupt)
            }
            let legacyData = try JSONSerialization.data(withJSONObject: objects.map { object in
                var legacy = object
                legacy.removeValue(forKey: "style")
                return legacy
            })
            defaults.set(legacyData, forKey: PromptToolbarSettings.preferenceKey)
            defaults.removeObject(forKey: PromptToolbarSettings.latinIconMigrationKey)
            let migrated = PromptToolbarSettings(preferences: defaults)
            check(migrated.buttons.map(\.id) == legacyButtons.map(\.id) && migrated.buttons[0].name == "Roots" &&
                  migrated.buttons[0].style == .latin && migrated.buttons[1].style == .cuts &&
                  migrated.buttons[2].style == HighlightStyle(), "legacy buttons preserve their identity and receive appropriate styles")
            check(migrated.buttons[0].icon == .laurel && migrated.buttons[2].icon == .leaf && migrated.buttons[3].icon == .book,
                  "the old Latin leaf becomes a laurel without changing unrelated or customized icons")
            let savedObjects = try JSONSerialization.jsonObject(with: defaults.data(forKey: PromptToolbarSettings.preferenceKey)!) as? [[String: Any]]
            check(savedObjects?.allSatisfy { $0["style"] != nil } == true, "migrated styles are persisted")
            migrated.buttons[0].style = HighlightStyle(fontColor: .rgba(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
                                                      strikethrough: true, underline: .wiggly, backgroundColor: .yellow)
            migrated.buttons[0].icon = .leaf
            let styled = PromptToolbarSettings(preferences: defaults)
            check(styled.buttons == migrated.buttons, "style choices, opacity, and an explicitly reselected leaf survive a restart without preset overrides")
            let invalid = PromptButton(name: "Invalid color", prompt: "Highlight words.",
                                       style: HighlightStyle(fontColor: .rgba(red: 2, green: 0, blue: 0, alpha: 1)))
            let invalidData = try JSONEncoder().encode([invalid])
            defaults.set(invalidData, forKey: PromptToolbarSettings.preferenceKey)
            let protected = PromptToolbarSettings(preferences: defaults)
            check(protected.isReadOnly && protected.error != nil && protected.echo.message == protected.error &&
                  defaults.data(forKey: PromptToolbarSettings.preferenceKey) == invalidData,
                  "invalid saved color components are reported without overwriting settings")
            settings.buttons.append(PromptButton(name: "Custom", icon: .fish, prompt: "Highlight concrete nouns."))
            settings.buttons[0].prompt = "Highlight verbs."
            settings.buttons.swapAt(0, 2)
            let restored = PromptToolbarSettings(preferences: preferences(for: directory))
            check(restored.buttons == settings.buttons, "custom prompts, names, icons, and order survive a fresh settings instance")
            settings.buttons.removeAll()
            check(PromptToolbarSettings(preferences: defaults).buttons.isEmpty, "removing every button persists an empty toolbar")
            let bad = Data("broken".utf8)
            defaults.set(bad, forKey: PromptToolbarSettings.preferenceKey)
            let unreadable = PromptToolbarSettings(preferences: defaults)
            check(unreadable.isReadOnly && unreadable.error != nil && defaults.data(forKey: PromptToolbarSettings.preferenceKey) == bad,
                  "unreadable toolbar settings are surfaced and protected")
            unreadable.reset()
            check(!unreadable.isReadOnly && PromptToolbarSettings(preferences: defaults).buttons.count == 2, "explicit reset repairs toolbar settings")
        } catch { check(false, "highlight model check failed: \(error)") }
    }

    @MainActor private static func promptInterface(model: ComposerModel, window: NSWindow, service: PromptStub,
                                                   check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func press(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], delay: Duration = .milliseconds(100)) async {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            try? await Task.sleep(for: delay)
        }
        func begin(_ text: String) async {
            if model.echo.readsText { await press("\u{1b}", code: 53) }
            await press("\r", code: 36, modifiers: .control)
            guard let input = model.echo.textField?.currentEditor() as? NSTextView else {
                check(false, "minibuffer has a native text editor for '\(text)' (readsText: \(model.echo.readsText), waiting: \(model.echo.isWaiting), field: \(String(describing: model.echo.textField)), responder: \(String(describing: window.firstResponder)))")
                return
            }
            input.insertText(text, replacementRange: input.selectedRange())
        }
        func click(_ point: NSPoint) async {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            await settle()
        }
        model.newDraft()
        await settle()
        guard let editor = model.activeEditor else { check(false, "prompt command has a post editor"); return }
        let paragraph = "😀 A little help goes a long way. Another sentence.\n"
        let source = "Before.\n\n\(paragraph)\nAfter."
        editor.insertText(source, replacementRange: NSRange(location: NSNotFound, length: 0))
        let word = (source as NSString).range(of: "help")
        let selection = NSRange(location: word.location + 1, length: 2)
        editor.setSelectedRange(selection)
        await settle()
        let frame = window.frame
        let selectionRect = editor.firstRect(forCharacterRange: selection, actualRange: nil)
        await begin("")
        check(model.echo.readsText && model.echo.message == "> " && model.echo.textField?.currentEditor() === window.firstResponder &&
              window.firstResponder !== editor && !model.showHandoff && window.frame == frame &&
              editor.firstRect(forCharacterRange: selection, actualRange: nil) == selectionRect,
              "Control-Enter opens a focused native minibuffer input without publishing or moving the post text")
        await press("x", code: 7)
        await press("y", code: 16)
        await press("\u{7f}", code: 51)
        check(model.echo.inputText == "x" && editor.string == source && editor.selectedRange() == selection,
              "typing and backspace edit only the minibuffer, including Y/N characters")
        await press("\u{1b}", code: 53)
        check(!model.echo.expectsInput && model.echo.message == nil && window.firstResponder === editor &&
              editor.selectedRange() == selection && service.prompts.isEmpty,
              "Escape cancels freeform input without a model request and restores the post selection")

        await begin("Cancel by clicking")
        guard let field = model.echo.textField else { check(false, "minibuffer field exists for mouse editing"); return }
        await click(field.convert(NSPoint(x: 12, y: field.bounds.midY), to: nil))
        check(model.echo.readsText && model.echo.inputText == "Cancel by clicking" && field.currentEditor() === window.firstResponder,
              "clicking within the minibuffer edits its input instead of dismissing it")
        await click(editor.convert(NSPoint(x: 12, y: 12), to: nil))
        check(!model.echo.expectsInput && model.echo.message == nil && window.firstResponder === editor && service.prompts.isEmpty,
              "clicking the post cancels freeform input without invoking the model")
        editor.setSelectedRange(selection)
        await begin("Replace this")
        await press("a", code: 0, modifiers: .command)
        guard let input = model.echo.textField?.currentEditor() as? NSTextView else { check(false, "prompt remains editable after Command-A"); return }
        check(input.selectedRange().length == ("Replace this" as NSString).length && model.echo.readsText,
              "native text editing menu commands do not dismiss the prompt")
        input.insertText("Explain this", replacementRange: input.selectedRange())
        service.delay = .milliseconds(600)
        await press("\r", code: 36)
        check(model.prompts.state == .loading && model.echo.isWaiting && model.echo.expectsInput && window.firstResponder !== editor &&
              service.prompts == ["Explain this"] && service.targets == ["el"] && service.texts == [paragraph] &&
              service.models == [model.synonymModel] && service.efforts == [model.synonymEffort] && editor.string == source,
              "Enter submits the exact selection and prompt using the configured model without editing the post")
        await press("x", code: 7)
        try? await Task.sleep(for: .milliseconds(600))
        check(model.echo.message == service.result && model.prompts.state == .idle && model.echo.readsText && !model.echo.isWaiting &&
              model.echo.inputText.isEmpty && model.echo.textField?.currentEditor() === window.firstResponder &&
              editor.string == source && editor.selectedRange() == selection &&
              window.attachedSheet == nil && NSApp.modalWindow == nil,
              "a reply appears above a fresh focused prompt; keys during the request cannot edit the post")
        if let area = model.echo.areaView {
            await click(area.convert(NSPoint(x: ComposerWindowSizing.textLeading + 20, y: area.bounds.height - 12), to: nil))
        }
        check(model.echo.readsText && model.echo.message == service.result && model.echo.textField?.currentEditor() === window.firstResponder,
              "clicking the displayed reply leaves the conversation and prompt focus intact")
        let firstConversation = service.conversationIDs[0]
        service.result = "A follow-up answer."
        service.delay = .milliseconds(100)
        if let followUp = model.echo.textField?.currentEditor() as? NSTextView {
            followUp.insertText("Why?", replacementRange: followUp.selectedRange())
        } else { check(false, "follow-up prompt has a native editor") }
        await press("\r", code: 36)
        await settle()
        check(service.prompts == ["Explain this", "Why?"] && service.targets == ["el", "el"] && service.texts == [paragraph, paragraph] &&
              service.conversationIDs == [firstConversation, firstConversation] && service.resumptions == [false, true] &&
              model.echo.message == service.result && model.echo.inputText.isEmpty && model.echo.readsText,
              "a follow-up resumes the same conversation with the original exact selection and replaces the displayed reply")
        await press("\u{1b}", code: 53)
        check(model.echo.message == nil && !model.echo.expectsInput && window.firstResponder === editor && editor.selectedRange() == selection,
              "Escape ends a completed conversation and restores the original editor selection")
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.setSelectedRange(NSRange(location: word.location + 2, length: 0))
        service.delay = .milliseconds(100)
        service.authenticated = false
        await begin("Define it")
        await press("\r", code: 36)
        await settle()
        check(service.targets.last == "help" && service.texts.last == paragraph && service.signIns == 1 && model.echo.message == service.result &&
              service.conversationIDs.last != firstConversation && service.resumptions.last == false,
              "a new conversation starts fresh with the cursor word and subscription sign-in when needed")

        service.delay = .seconds(1)
        service.ignoreCancellation = true
        service.result = "A stale reply"
        await begin("Old request")
        await press("\r", code: 36)
        await begin("New request")
        await settle()
        check(model.echo.readsText && model.echo.inputText == "New request" && model.echo.message == "> ",
              "a new command cancels an older request and stale results cannot replace its input")
        await press("\u{1b}", code: 53)
        await begin("Cancel while waiting")
        await press("\r", code: 36)
        await press("\u{1b}", code: 53)
        await settle()
        check(model.prompts.state == .idle && model.echo.message == nil && window.firstResponder === editor,
              "Escape also cancels a running prompt and suppresses late replies")
        await begin("Cancel pending by clicking")
        await press("\r", code: 36)
        await click(editor.convert(NSPoint(x: 12, y: 12), to: nil))
        check(model.prompts.state == .idle && !model.echo.expectsInput && model.echo.message == nil && window.firstResponder === editor,
              "clicking the editor cancels a pending conversation even when the service ignores cancellation")
        await begin("Replaced request")
        await press("\r", code: 36)
        model.notify("A different operation")
        await settle()
        check(model.echo.message == "A different operation" && !model.echo.expectsInput && model.prompts.state == .idle,
              "an unrelated message ends the conversation and cannot be overwritten by its pending reply")
        service.ignoreCancellation = false
        service.delay = .milliseconds(100)
        let requests = service.prompts.count
        await begin("")
        let rejections = model.echo.rejectedInputCount
        await press("\r", code: 36)
        check(service.prompts.count == requests && model.echo.readsText && !model.echo.isWaiting &&
              model.echo.rejectedInputCount == rejections + 1,
              "an empty command blinks the prompt without invoking the model or discarding the conversation")
        service.failure = ClaudeCLIError.failed("Synthetic prompt failure")
        await begin("Fail")
        await press("\r", code: 36)
        await settle()
        check(model.echo.message == "Synthetic prompt failure" && model.prompts.state == .idle && window.firstResponder === editor,
              "model prompt failures appear in the minibuffer without retaining input focus")
        service.failure = nil
        editor.insertText("", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await begin("Suggest a topic")
        await press("\r", code: 36)
        await settle()
        check(service.targets.last == .some(nil) && service.texts.last == "" && model.echo.message == service.result,
              "an empty editor sends a prompt with empty context and no target")
    }

    @MainActor private static func replyLayoutInterface(model: ComposerModel, window: NSWindow, service: PromptStub,
                                                        check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        guard let editor = model.activeEditor, let scroll = editor.enclosingScrollView else {
            check(false, "reply layout has an editor viewport"); return
        }
        model.echo.clear()
        let source = String(repeating: "A line with help.\n", count: 80)
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await settle()
        editor.setSelectedRange((source as NSString).range(of: "help", range: NSRange(location: 200, length: (source as NSString).length - 200)))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        func geometry() -> [NSRect] {
            [editor.convert(editor.bounds, to: window.contentView),
             scroll.convert(scroll.bounds, to: window.contentView), scroll.contentView.bounds]
        }
        let frame = window.frame
        let originalGeometry = geometry()
        let originalToolbar = toolbarSnapshot(in: window, width: model.composerWidth, above: ComposerWindowSizing.echoAreaHeight)
        let reply = "A clear sentence gives the reader one idea at a time, choosing familiar words and placing the important point early. " +
            "Remove repeated qualifications and unnecessary introductions, but keep enough detail to preserve the meaning, rhythm, and tone of the original thought."
        service.result = reply
        model.readPrompt()
        model.echo.inputText = "Explain clear writing"
        model.echo.submit()
        try? await Task.sleep(for: .milliseconds(600))
        guard let expanded = echoHeight(in: window) else {
            check(false, "expanded reply has a visible minibuffer separator"); return
        }
        check(model.echo.message == reply && expanded > SynonymEchoArea.minimumResultsHeight,
              "a model reply word-wraps into as many lines as needed instead of truncating or stopping at two lines")
        check(originalToolbar != nil && toolbarSnapshot(in: window, width: model.composerWidth, above: expanded) == originalToolbar,
              "the unchanged toolbar rises above the expanded reply")
        check(window.frame == frame && geometry() == originalGeometry && model.echo.textField?.currentEditor() === window.firstResponder,
              "conversation expansion preserves window size, editor layout, and scroll position while focusing the fresh prompt")
        service.result = "A short follow-up."
        model.echo.inputText = "Shorter?"
        model.echo.submit()
        await settle()
        check(model.echo.message == service.result && echoHeight(in: window) == 2 * ComposerWindowSizing.echoAreaHeight - 1 &&
              model.echo.readsText && window.frame == frame && geometry() == originalGeometry,
              "a shorter follow-up shrinks to one reply and one prompt instead of retaining earlier replies")
        service.result = reply
        model.echo.inputText = "Explain further"
        model.echo.submit()
        try? await Task.sleep(for: .milliseconds(600))
        check(model.echo.message == reply && echoHeight(in: window) == expanded &&
              window.frame == frame && geometry() == originalGeometry,
              "additional turns show only the latest response and prompt without accumulating visible history")
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        NSApp.postEvent(escape, atStart: false)
        await settle()
        check(model.echo.message == nil && echoHeight(in: window) == ComposerWindowSizing.echoAreaHeight &&
              toolbarSnapshot(in: window, width: model.composerWidth, above: ComposerWindowSizing.echoAreaHeight) == originalToolbar,
              "dismissing a reply returns the unchanged footer to its resting position")
        check(window.frame == frame && geometry() == originalGeometry,
              "dismissing a reply preserves the window and scrolled document")
        model.readPrompt()
        model.echo.continueConversation(with: reply)
        await settle()
        window.setContentSize(NSSize(width: frame.width + 300, height: window.contentView!.bounds.height))
        await settle()
        check((echoHeight(in: window) ?? expanded) < expanded &&
              window.frame.height == frame.height, "a wider window reflows the reply into fewer lines")
        window.setFrame(frame, display: true)
        await settle()
        model.echo.continueConversation(with: "A short reply.")
        await settle()
        check(echoHeight(in: window) == 2 * ComposerWindowSizing.echoAreaHeight - 1,
              "a short conversational reply occupies just one response line and one prompt line")
        model.echo.continueConversation(with: reply)
        await settle()
        model.notify(reply)
        await settle()
        check(!model.echo.wrapsMessage && echoHeight(in: window) == ComposerWindowSizing.echoAreaHeight,
              "ordinary status messages retain their single-line layout after a wrapped reply")
        model.echo.clear()
    }

    @MainActor private static func drawerDeletionInterface(model: ComposerModel, window: NSWindow,
                                                          check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
        func click(_ point: NSPoint) async {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            await settle()
        }
        func request() async {
            await click(NSPoint(x: window.contentView!.bounds.width - 33, y: window.contentView!.bounds.height - 86))
        }
        func press(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false,
                   delay: Duration = .milliseconds(300)) async {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: repeating, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            try? await Task.sleep(for: delay)
        }
        guard let editor = model.activeEditor else { check(false, "drawer deletion has an editor"); return }
        let id = model.draft.id
        let text = editor.string
        let frame = window.frame
        let selection = editor.selectedRange()
        await request()
        editor.onFocusRequest?()
        check(model.echo.message?.contains("(y/n)") == true && model.drafts.contains(where: { $0.id == id }) &&
              window.attachedSheet == nil && NSApp.modalWindow == nil && window.frame == frame && window.firstResponder !== editor,
              "a drawer question removes editor focus without a dialog, resize, or deletion, even after a queued focus request")
        let question = model.echo.message
        let visiblePrompt = echoSnapshot(in: window)
        await press("x", code: 7, delay: .milliseconds(100))
        check(model.echo.expectsInput && model.echo.message == question && editor.string == text &&
              editor.selectedRange() == selection && window.firstResponder !== editor,
              "unrelated typing leaves the question active without editing or moving the cursor")
        check(visiblePrompt != nil && echoSnapshot(in: window) != visiblePrompt, "invalid input visibly blinks the question")
        await settle()
        check(echoSnapshot(in: window) == visiblePrompt, "the question returns to full visibility after blinking")
        await press("n", code: 45)
        check(model.echo.message == nil && model.draft.id == id && editor.string == text &&
              window.firstResponder === editor && editor.selectedRange() == selection,
              "N cancels and restores editor focus and selection without typing into the post")
        await request()
        let invalidKeys: [(String, UInt16, NSEvent.ModifierFlags, Bool)] = [
            ("n", 45, .command, false), ("y", 16, .command, false), ("y", 16, .option, false),
            ("\t", 48, [], false), ("\u{f702}", 123, [], false), ("\r", 36, [], false),
            ("\u{7f}", 51, [], false), (" ", 49, .control, false), ("y", 16, [], true)
        ]
        for (characters, code, modifiers, repeating) in invalidKeys {
            await press(characters, code: code, modifiers: modifiers, repeating: repeating)
            check(model.echo.expectsInput && model.echo.message == question && model.draft.id == id &&
                  editor.string == text && editor.selectedRange() == selection &&
                  window.firstResponder !== editor && !model.showHandoff && model.synonyms.state == .idle,
                  "invalid key \(code) with modifiers \(modifiers.rawValue) cannot edit, move focus, run commands, or answer")
        }
        await press("\u{1b}", code: 53)
        check(model.echo.message == nil && model.draft.id == id && editor.string == text &&
              window.firstResponder === editor && editor.selectedRange() == selection,
              "Escape cancels the question and restores editor focus and selection")
        await request()
        model.notify("A newer message")
        await settle()
        check(!model.echo.expectsInput && model.echo.message == "A newer message" && window.firstResponder === editor &&
              !model.echo.respond(yes: true), "replacing a question restores editor focus and cancels its response")
        await request()
        await click(editor.convert(NSPoint(x: 12, y: 12), to: nil))
        check(!model.echo.expectsInput && model.echo.message == nil && model.draft.id == id && window.firstResponder === editor,
              "clicking the input box dismisses the question and focuses the editor")
        let editedText = (text as NSString).replacingCharacters(in: editor.selectedRange(), with: "x")
        await press("x", code: 7)
        check(editor.string == editedText && model.draft.id == id, "typing after clicking the input box edits normally")
        editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await request()
        await press("Y", code: 16, modifiers: .shift)
        check(model.echo.message == nil && !model.drafts.contains(where: { $0.id == id }) && !model.draft.hasContent &&
              model.showDrafts && window.firstResponder === model.activeEditor,
              "Y deletes the requested draft without typing Y, restores editor focus, and leaves the drawer open")
    }

    @MainActor private static func sharedContextInterface(model: ComposerModel, window: NSWindow, synonyms: SynonymStub,
                                                          highlights: HighlightStub, prompts: PromptStub,
                                                          check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        model.echo.clear()
        model.synonyms.dismiss()
        model.newDraft()
        await settle()
        guard let editor = model.activeEditor, let button = model.toolbarSettings.buttons.first else {
            check(false, "shared context has an editor and highlight button"); return
        }
        let previousMatches = highlights.result
        defer {
            model.highlights.dismiss()
            highlights.result = previousMatches
            highlights.delay = .milliseconds(100)
            highlights.contexts.removeAll()
            highlights.prompts.removeAll()
            highlights.models.removeAll()
            highlights.efforts.removeAll()
        }
        let paragraph = "First mark sentence. More mark words.\n"
        let source = "😀 Outside mark.\n\n\(paragraph)\nLast mark paragraph."
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        let scope = (source as NSString).range(of: paragraph)
        let first = (source as NSString).range(of: "mark", range: scope)
        let across = (source as NSString).range(of: "mark words.\n\nLast mark")
        highlights.result = HighlightMatches(matches: [.init(text: "mark", occurrence: 1), .init(text: "mark", occurrence: 2)])
        for selection in [NSRange(location: first.location + 2, length: 0),
                          NSRange(location: first.location + 1, length: 2), across] {
            editor.setSelectedRange(selection)
            let expected = ModelContext.capture(text: source, selection: selection)!
            model.synonyms.lookup(in: editor, model: model.synonymModel, effort: model.synonymEffort)
            await settle()
            check(synonyms.contexts.last == expected && model.synonyms.hasResults,
                  "synonyms use shared cursor/selection and paragraph context")
            model.readPrompt()
            model.echo.inputText = "Explain this context"
            model.echo.submit()
            await settle()
            check(prompts.contexts.last == expected && model.echo.readsText && !model.echo.isWaiting,
                  "conversations use exactly the same captured context as synonyms")
            model.echo.clear()
            model.toggleHighlights(button)
            await settle()
            let expectedScope = selection == across ? across : scope
            let expectedRanges = try! highlights.result.ranges(in: (source as NSString).substring(with: expectedScope))
                .map { NSRange(location: expectedScope.location + $0.location, length: $0.length) }
            check(highlights.contexts.last == expected && model.highlights.ranges == expectedRanges &&
                  model.highlights.ranges.allSatisfy { NSIntersectionRange($0, expectedScope) == $0 },
                  "button highlights use that same context and only mark the captured paragraph or multi-paragraph selection")
            model.highlights.dismiss()
        }
        editor.setSelectedRange(NSRange(location: first.location, length: 0))
        highlights.delay = .milliseconds(600)
        model.toggleHighlights(button)
        try? await Task.sleep(for: .milliseconds(50))
        editor.insertText("Prefix 😀 ", replacementRange: NSRange(location: 0, length: 0))
        let shiftedFirst = (editor.string as NSString).range(of: "mark sentence")
        editor.insertText("x", replacementRange: NSRange(location: shiftedFirst.location + 1, length: 0))
        try? await Task.sleep(for: .milliseconds(700))
        let remaining = (editor.string as NSString).range(of: "mark words")
        check(model.highlights.ranges == [NSRange(location: remaining.location, length: 4)],
              "pending paragraph-relative matches are translated before global edits shift and invalidate them")
        model.highlights.dismiss()
        highlights.delay = .milliseconds(100)
        highlights.result = HighlightMatches(matches: [.init(text: "Outside", occurrence: 1)])
        editor.setSelectedRange(remaining)
        model.toggleHighlights(button)
        await settle()
        check(model.highlights.state == .idle && model.echo.message == HighlightError.invalidResponse.localizedDescription,
              "matches that exist only outside the captured paragraph are rejected")
        let requests = highlights.contexts.count
        let blank = (editor.string as NSString).range(of: "\n\n").location + 1
        editor.setSelectedRange(NSRange(location: blank, length: 0))
        model.toggleHighlights(button)
        check(highlights.contexts.count == requests && model.highlights.state == .idle && model.echo.message != nil,
              "an empty paragraph reports an error instead of silently highlighting the whole post")
        model.echo.clear()
    }

    @MainActor private static func highlightNotesInterface(model: ComposerModel, window: NSWindow, service: HighlightStub,
                                                          check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func activateWindow() async {
            if !window.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                await settle()
            }
            check(window.isKeyWindow, "native highlight-note input requires a key window; macOS must allow app activation")
        }
        func press(_ text: String, code: UInt16) async {
            await activateWindow()
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            await settle()
        }
        func hover(_ point: NSPoint) async {
            await activateWindow()
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            NSApp.postEvent(event, atStart: false)
            await settle()
        }
        model.echo.clear()
        model.newDraft()
        await settle()
        guard let editor = model.activeEditor, let button = model.toolbarSettings.buttons.first else {
            check(false, "interval notes have a native editor and button"); return
        }
        let oldResult = service.result
        defer {
            model.highlights.dismiss()
            service.result = oldResult
            service.delay = .milliseconds(100)
            service.contexts.removeAll(); service.prompts.removeAll(); service.models.removeAll(); service.efforts.removeAll()
        }
        let source = "😀 Often we look for a silver bullet. Then we try to move the needle."
        let first = (source as NSString).range(of: "silver bullet")
        let second = (source as NSString).range(of: "move the needle")
        let inner = (source as NSString).range(of: "needle")
        let firstNote = "Describe the specific solution instead of promising a silver bullet. " +
            "For example, name the change, explain which problem it solves, and acknowledge the trade-off that remains."
        let secondNote = "Say what will improve and by how much."
        let innerNote = "Name the metric you mean."
        service.result = HighlightMatches(matches: [
            .init(text: "move the needle", occurrence: 1, note: secondNote),
            .init(text: "silver bullet", occurrence: 1, note: firstNote),
            .init(text: "Often", occurrence: 1),
            .init(text: "needle", occurrence: 1, note: innerNote)
        ])
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        await settle()
        let frame = window.frame
        let textRect = editor.firstRect(forCharacterRange: first, actualRange: nil)
        model.toggleHighlights(button)
        await settle()
        check(model.highlights.state == .ready && model.echo.message == nil && model.highlights.intervals.count == 4,
              "intervals with and without optional notes coexist without displaying an unrelated note")
        func point(at index: Int) -> NSPoint {
            let layout = editor.layoutManager!, container = editor.textContainer!
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            return editor.convert(NSPoint(x: rect.midX + editor.textContainerOrigin.x, y: rect.midY + editor.textContainerOrigin.y), to: nil)
        }
        editor.setSelectedRange(NSRange(location: first.location - 1, length: 0))
        await press("\u{f703}", code: 124)
        check(model.echo.message == firstNote && model.echo.wrapsMessage && window.firstResponder === editor &&
              window.frame == frame && editor.string == source && editor.firstRect(forCharacterRange: first, actualRange: nil) == textRect &&
              (echoHeight(in: window) ?? 0) > ComposerWindowSizing.echoAreaHeight,
              "moving the caret into an interval shows its wrapped note without changing text, window geometry, or focus")
        await press("\u{1b}", code: 53)
        check(model.echo.message == nil && editor.selectedRange().location == first.location &&
              model.highlights.activeButtonID == button.id,
              "Escape keeps a caret note dismissed through footer layout without moving the cursor or disabling highlights")
        editor.setSelectedRange(NSRange(location: NSMaxRange(first), length: 0))
        await settle()
        check(model.echo.message == nil, "the interval's end boundary is outside the caret note")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        check(model.echo.message == nil, "an unannotated highlight does not display another interval's note")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        await hover(point(at: NSMaxRange(first) - 1))
        check(model.echo.message == firstNote, "hovering the last character shows its wrapped interval note through footer layout")
        await hover(point(at: second.location + 1))
        check(model.echo.message == secondNote && editor.selectedRange().location == 0 && window.firstResponder === editor,
              "native mouse movement over a highlighted glyph shows its own note without moving the caret")
        await hover(point(at: inner.location + 1))
        check(model.echo.message == innerNote, "overlapping annotations show the most specific matching interval")
        let linePoint = editor.convert(point(at: second.location), from: nil)
        await hover(editor.convert(NSPoint(x: editor.bounds.maxX - 1, y: linePoint.y), to: nil))
        check(model.echo.message == nil, "empty space after a line does not count as hovering its nearest glyph")
        await hover(point(at: first.location + 1))
        await press("\u{1b}", code: 53)
        check(model.echo.message == nil && model.highlights.activeButtonID == button.id,
              "Escape clears the note without disabling highlights")
        await hover(point(at: second.location + 1))
        await hover(NSPoint(x: 16, y: 40))
        check(model.echo.message == nil, "leaving the editor clears a hover note when the caret is outside annotations")
        editor.setSelectedRange(NSRange(location: first.location + 1, length: 0))
        model.notify("Keep this error")
        await hover(point(at: second.location + 1))
        await hover(NSPoint(x: 16, y: 40))
        check(model.echo.message == "Keep this error", "hover notes neither overwrite nor clear an unrelated status or error")
        model.echo.clear()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        model.echo.confirm("Keep this question (y/n)") {}
        await hover(point(at: first.location + 1))
        check(model.echo.expectsInput && !model.echo.readsText && model.echo.message == "Keep this question (y/n)",
              "hovering annotations cannot replace a minibuffer confirmation")
        model.echo.clear()
        await settle()
        model.readPrompt()
        model.echo.inputText = "Keep this prompt"
        await hover(point(at: second.location + 1))
        check(model.echo.readsText && model.echo.inputText == "Keep this prompt" && model.echo.message == "> ",
              "hovering annotations cannot cancel or replace an interactive conversation")
        model.echo.clear()
        editor.setSelectedRange(NSRange(location: first.location + 1, length: 0))
        model.echo.clear()
        model.synonyms.lookup(in: editor, model: model.synonymModel, effort: model.synonymEffort)
        await settle()
        await hover(point(at: second.location + 1))
        check(model.synonyms.hasResults && model.echo.message == nil, "passive notes do not dismiss synonym results")
        model.synonyms.dismiss()
        editor.insertText("New ", replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing()
        let shifted = (editor.string as NSString).range(of: "silver bullet")
        editor.setSelectedRange(NSRange(location: shifted.location + 1, length: 0))
        check(model.echo.message == firstNote, "a note follows its interval after preceding text is inserted")
        editor.insertText("fresh idea", replacementRange: shifted)
        editor.breakUndoCoalescing()
        editor.setSelectedRange(NSRange(location: shifted.location + 1, length: 0))
        check(model.echo.message == nil && !model.highlights.intervals.contains { $0.note == firstNote },
              "replacing an annotated interval removes its note as well as its highlight")
        editor.undoManager?.undo()
        editor.setSelectedRange(NSRange(location: shifted.location + 1, length: 0))
        check(model.echo.message == nil && !model.highlights.intervals.contains { $0.note == firstNote },
              "undo does not resurrect invalidated interval notes")
        check(service.contexts.count == 1, "caret, hover, and edit inspection never reruns the model")
        let currentSecond = (editor.string as NSString).range(of: "move the needle")
        editor.setSelectedRange(NSRange(location: currentSecond.location + 1, length: 0))
        model.toggleHighlights(button)
        check(model.echo.message == nil && model.highlights.intervals.isEmpty, "unpressing the button clears its visible note")
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        service.delay = .milliseconds(600)
        model.toggleHighlights(button)
        try? await Task.sleep(for: .milliseconds(50))
        editor.insertText("New ", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("x", replacementRange: NSRange(location: first.location + 5, length: 0))
        try? await Task.sleep(for: .milliseconds(700))
        let finalSecond = (editor.string as NSString).range(of: "move the needle")
        editor.setSelectedRange(NSRange(location: finalSecond.location + 1, length: 0))
        check(model.echo.message == secondNote && !model.highlights.intervals.contains { $0.note == firstNote },
              "pending results preserve notes on shifted intervals and discard notes on spans edited while waiting")
        model.newDraft()
        await settle()
        check(model.echo.message == nil && model.highlights.state == .idle, "switching drafts clears interval notes")
    }

    @MainActor private static func modelLogInterface(model: ComposerModel, window: NSWindow,
                                                    check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func press(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in target: NSWindow) async {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                        context: nil, characters: text, charactersIgnoringModifiers: text,
                                        isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            await settle()
        }
        func logEditor(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView, editor.identifier?.rawValue == "model-session-log" { return editor }
            return view.subviews.lazy.compactMap { logEditor(in: $0) }.first
        }
        model.readPrompt()
        model.echo.inputText = "Keep this conversation"
        let composerFrame = window.frame
        await press("<", code: 43, modifiers: [.command, .shift], in: window)
        guard let dialog = NSApp.windows.first(where: { $0.isVisible && $0.title == "Model Log" }),
              let content = dialog.contentView, let textView = logEditor(in: content) else {
            check(false, "Command-Shift-comma opens a dedicated model-log dialog"); return
        }
        check(dialog !== window && dialog.isKeyWindow && window.frame == composerFrame &&
              textView.string == model.modelLog.transcript && !textView.isEditable && textView.isSelectable,
              "Command-less-than opens a separate selectable, scrollable session log without changing the composer")
        check(model.echo.readsText && model.echo.inputText == "Keep this conversation",
              "opening the log does not dismiss an existing conversation")
        let entry = model.modelLog.begin(feature: "Live log check", arguments: ["--print", "--system-prompt", "A test instruction"],
                                         input: #"{"target":"😀","text":"a paragraph","prompt":"keep it short"}"#)
        await settle()
        check(textView.string.contains("Waiting for response...") && textView.string == model.modelLog.transcript,
              "an open log updates when a request starts")
        model.echo.submit()
        model.modelLog.received(.init(status: 0, output: Data("A live response with 😀.".utf8)), for: entry)
        await settle()
        check(dialog.isKeyWindow && model.echo.readsText && !model.echo.isWaiting &&
              textView.string.contains("A live response with 😀.") && textView.string == model.modelLog.transcript,
              "responses update the dialog live without interrupting the conversation or stealing log focus")
        dialog.makeFirstResponder(textView)
        await press("a", code: 0, modifiers: .command, in: dialog)
        check(textView.selectedRange().length == (textView.string as NSString).length && model.echo.readsText,
              "native Select All works in the log without clearing the conversation")
        let transcript = textView.string
        await press("\u{1b}", code: 53, in: dialog)
        check(!dialog.isVisible && model.echo.readsText, "Escape closes only the log dialog")
        let shortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: "<", charactersIgnoringModifiers: "<", isARepeat: false, keyCode: 43)!
        check(NSApp.mainMenu?.performKeyEquivalent(with: shortcut) == true, "the model log also has a working menu shortcut")
        await settle()
        check(dialog.isVisible && textView.string == transcript && model.echo.readsText,
              "closing and reopening the dialog preserves all current-session exchanges")
        await press("w", code: 13, modifiers: .command, in: dialog)
        check(!dialog.isVisible && model.echo.readsText, "Command-W closes the log without ending the conversation")
        model.echo.clear()
        window.makeKeyAndOrderFront(nil)
        await settle()
    }

    @MainActor private static func highlightInterface(model: ComposerModel, window: NSWindow, service: HighlightStub,
                                                      check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func firstIconBounds() -> NSRect? {
            guard let view = window.contentView else { return nil }
            let rect = view.convert(NSRect(x: 60, y: 4 + ComposerWindowSizing.echoAreaHeight, width: 34, height: 50), from: nil)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
            view.cacheDisplay(in: rect, to: bitmap)
            var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.blueComponent - color.redComponent > 0.25,
                          color.blueComponent - color.greenComponent > 0.1 else { continue }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        @MainActor func click(_ point: NSPoint, in target: NSWindow? = nil) async {
            let target = target ?? window
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            await settle()
        }
        func shortcut(_ text: String, code: UInt16, in target: NSWindow) -> Bool {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        }
        model.synonyms.dismiss()
        model.newDraft()
        await settle()
        guard let editor = model.activeEditor else { check(false, "highlight editor exists"); return }
        let source = "😀 A precise line, a clear point, and precise words."
        editor.insertText(source, replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        let buttons = model.toolbarSettings.buttons
        let first = NSPoint(x: 77, y: 29 + ComposerWindowSizing.echoAreaHeight)
        let second = NSPoint(x: 111, y: 29 + ComposerWindowSizing.echoAreaHeight)
        model.notify("Previous message")
        await click(first)
        check(model.echo.message == nil, "clicking a highlight icon clears the previous message")
        check(model.highlights.state == .ready && model.highlights.activeButtonID == buttons[0].id && model.highlights.ranges.count == 3,
              "clicking a configured button highlights the post and stays pressed")
        guard let restingIcon = firstIconBounds() else { check(false, "active toolbar icon is visible"); return }
        check(service.texts == [source] && service.prompts == [buttons[0].prompt] &&
              service.models == [model.synonymModel] && service.efforts == [model.synonymEffort],
              "highlight request uses the captured paragraph, configured prompt, and current model/effort")
        let precise = (source as NSString).range(of: "precise")
        let layout = editor.layoutManager!
        check(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: precise.location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue &&
              layout.temporaryAttribute(.underlineColor, atCharacterIndex: precise.location, effectiveRange: nil) as? NSColor == HighlightColor.underlineBlue.nsColor &&
              layout.temporaryAttribute(.foregroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.backgroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              editor.textStorage?.attribute(.underlineStyle, at: precise.location, effectiveRange: nil) == nil,
              "Latin styling uses only a blue temporary underline without changing text or background")
        layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.double.rawValue, forCharacterRange: NSRange(location: 0, length: 2))
        model.toolbarSettings.buttons[0].style = HighlightStyle(fontColor: .iconGray, strikethrough: true, underline: .dotted)
        check(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: precise.location, effectiveRange: nil) as? NSColor == Theme.toolbarIconNS &&
              layout.temporaryAttribute(.backgroundColor, atCharacterIndex: precise.location, effectiveRange: nil) != nil &&
              layout.temporaryAttribute(.underlineStyle, atCharacterIndex: precise.location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.union(.patternDot).rawValue &&
              service.texts.count == 1 && model.highlights.activeButtonID == buttons[0].id, "style changes update current highlights without rerunning or unpressing")
        model.toolbarSettings.buttons[0].style = .latin
        check(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.strikethroughStyle, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.backgroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.double.rawValue,
              "changing styles clears only our previous decorations and preserves unrelated temporary attributes")
        layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: NSRange(location: 0, length: 2))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        model.toggleDrafts()
        model.toggleDrafts()
        await settle()
        check(model.highlights.ranges.count == 3, "selection and drawer changes preserve highlights")
        editor.insertText("x", replacementRange: NSRange(location: precise.location + 2, length: 0))
        editor.breakUndoCoalescing()
        check(model.highlights.ranges.count == 2 && model.highlights.ranges[0] == (editor.string as NSString).range(of: "clear"),
              "native typing removes only the edited span and shifts later highlights")
        editor.undoManager?.undo()
        check(editor.string == source && model.highlights.ranges.count == 2 &&
              model.highlights.ranges[0] == (source as NSString).range(of: "clear"), "native undo shifts retained highlights without restoring invalidated spans")
        editor.insertText("", replacementRange: NSRange(location: 0, length: 3))
        check(model.highlights.ranges.count == 2 && model.highlights.ranges[0] == (editor.string as NSString).range(of: "clear"),
              "deleting an emoji prefix preserves and shifts later highlights")
        let current = editor.string as NSString
        let start = current.range(of: "clear").location
        let end = NSMaxRange(current.range(of: "precise", options: .backwards))
        editor.insertText("one", replacementRange: NSRange(location: start, length: end - start))
        check(model.highlights.ranges.isEmpty && model.highlights.activeButtonID == buttons[0].id && service.texts.count == 1,
              "selection replacement removes intersecting highlights without rerunning or unpressing")
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await click(second)
        check(model.highlights.activeButtonID == buttons[1].id && model.highlights.ranges.count == 3, "another button replaces the active highlight mode")
        check(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: precise.location, effectiveRange: nil) as? NSColor == Theme.toolbarIconNS &&
              layout.temporaryAttribute(.strikethroughStyle, atCharacterIndex: precise.location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue &&
              layout.temporaryAttribute(.underlineStyle, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.backgroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              editor.textStorage?.attribute(.strikethroughStyle, at: precise.location, effectiveRange: nil) == nil,
              "removable wording uses icon-gray text and solid strikethrough only")
        await click(second)
        check(model.highlights.state == .idle && editor.highlightRanges.isEmpty && service.texts.count == 2, "unpressing hides highlights without another request")
        check(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: precise.location, effectiveRange: nil) == nil &&
              layout.temporaryAttribute(.strikethroughStyle, atCharacterIndex: precise.location, effectiveRange: nil) == nil,
              "unpressing restores normal text color and removes strikethrough")
        service.delay = .seconds(1)
        await click(first)
        check(model.highlights.isLoading, "a pending button remains pressed")
        editor.insertText("x", replacementRange: NSRange(location: precise.location + 2, length: 0))
        model.toolbarSettings.buttons[0].style.underline = .wiggly
        var bouncingFrames: [NSRect] = []
        for _ in 0..<6 {
            if let bounds = firstIconBounds() { bouncingFrames.append(bounds) }
            try? await Task.sleep(for: .milliseconds(75))
        }
        check(bouncingFrames.count == 6 &&
              bouncingFrames.allSatisfy { abs($0.minX - restingIcon.minX) <= 1 &&
                  abs($0.width - restingIcon.width) <= 1 && abs($0.height - restingIcon.height) <= 2 },
              "loading preserves the icon's size and horizontal position")
        let heights = bouncingFrames.map(\.minY)
        check(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || (heights.max()! - heights.min()! > 3),
              "the loading icon moves vertically rather than zooming")
        await settle()
        check(model.highlights.ranges.count == 2 && model.highlights.ranges[0] == (editor.string as NSString).range(of: "clear") && service.texts.count == 3,
              "edits during a request transform returned intervals without a second call")
        check(layout.temporaryAttribute(HighlightStyle.wigglyUnderline, atCharacterIndex: model.highlights.ranges[0].location, effectiveRange: nil) as? Bool == true,
              "pending results use the latest style rather than the style at request start")
        model.toolbarSettings.buttons[0].style = .latin
        check(model.highlights.state == .ready && firstIconBounds() == restingIcon, "the completed icon returns to its resting position")
        await settle()
        check(firstIconBounds() == restingIcon, "the completed icon stays still")
        await click(first)
        editor.insertText(source, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        service.delay = .milliseconds(600)
        service.ignoreCancellation = true
        await click(first)
        await click(second)
        await settle()
        check(model.highlights.activeButtonID == buttons[1].id && model.highlights.state == .ready, "late cancelled results cannot reactivate an old button")
        await click(second)
        service.delay = .milliseconds(100)
        service.ignoreCancellation = false
        service.authenticated = false
        await click(first)
        check(service.signIns == 1 && model.highlights.state == .ready, "highlighting uses subscription sign-in when necessary")
        model.notify("Before opening Settings")
        check(shortcut(",", code: 43, in: window), "Command-comma opens Settings")
        await settle()
        check(model.echo.message == nil, "menu commands clear the previous message before performing their action")
        guard let settings = NSApp.windows.first(where: { $0.title == "Settings" && $0.isVisible }) else {
            check(false, "Settings window is visible"); return
        }
        check(model.highlights.ranges.count == 3 && window.attachedSheet == nil, "opening Settings preserves pressed highlights")
        let settingsResponder = settings.firstResponder
        let settingsEcho = echoSnapshot(in: settings)
        let composerEcho = echoSnapshot(in: window)
        model.toolbarSettings.error = "Synthetic settings failure"
        await settle()
        check(model.echo.message == "Synthetic settings failure" && echoSnapshot(in: settings) == settingsEcho &&
              echoSnapshot(in: window) != composerEcho &&
              settings.attachedSheet == nil && NSApp.modalWindow == nil && settings.firstResponder === settingsResponder,
              "Settings has no echo area; its errors appear only in the composer without a modal")
        model.toolbarSettings.error = nil
        await click(NSPoint(x: 28, y: 24), in: settings)
        check(model.echo.message == nil, "operations in Settings also clear the previous message")
        check(model.toolbarSettings.buttons.count == 3 && !model.toolbarSettings.buttons[2].isConfigured, "Settings adds an initially unconfigured button")
        await click(NSPoint(x: 425, y: settings.contentView!.bounds.height - 80), in: settings)
        if let field = settings.firstResponder as? NSTextView {
            field.selectAll(nil)
            field.insertText("Custom highlight", replacementRange: field.selectedRange())
        } else { check(false, "Settings name field accepts native editing") }
        await click(NSPoint(x: 330, y: settings.contentView!.bounds.height - 200), in: settings)
        if let field = settings.firstResponder as? NSTextView {
            field.insertText("Highlight concrete nouns.", replacementRange: NSRange(location: 0, length: (field.string as NSString).length))
        } else { check(false, "Settings prompt accepts native editing") }
        await settle()
        check(model.toolbarSettings.buttons[2].name == "Custom highlight" && model.toolbarSettings.buttons[2].prompt == "Highlight concrete nouns.",
              "Settings edits button names and prompts")
        let previousWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(NSPoint(x: 235, y: settings.contentView!.bounds.height - 80), in: settings)
        guard let picker = NSApp.windows.first(where: { $0.isVisible && !previousWindows.contains($0.windowNumber) }) else {
            check(false, "Settings opens the icon library"); return
        }
        await click(NSPoint(x: 46, y: picker.contentView!.bounds.height - 45), in: picker)
        check(model.toolbarSettings.buttons[2].icon == .leaf && !picker.isVisible,
              "choosing a library icon updates the button (icon=\(model.toolbarSettings.buttons[2].icon), visible=\(picker.isVisible))")
        let restored = PromptToolbarSettings(preferences: preferences(for: model.storage.directory))
        check(restored.buttons == model.toolbarSettings.buttons, "Settings edits persist immediately")
        await click(NSPoint(x: 70, y: 24), in: settings)
        check(model.toolbarSettings.buttons.count == 2, "Settings removes the selected button")
        check(shortcut("w", code: 13, in: settings), "Command-W closes Settings")
        await settle()
        check(!settings.isVisible && window.isVisible && model.highlights.activeButtonID == buttons[0].id,
              "closing Settings leaves the composer and its highlights intact")
        window.makeKeyAndOrderFront(nil)
        model.toolbarSettings.buttons[0].prompt += " Be conservative."
        check(model.highlights.state == .idle, "editing the active prompt clears its outdated results")
        await click(first)
        model.toolbarSettings.buttons.removeFirst()
        check(model.highlights.state == .idle && editor.highlightRanges.isEmpty, "removing an active button clears its highlights")
        service.delay = .milliseconds(600)
        service.ignoreCancellation = true
        await click(first)
        await click(first)
        check(model.highlights.state == .idle && editor.highlightRanges.isEmpty, "unpressing a pending button rejects its late response")
        service.delay = .milliseconds(100)
        service.ignoreCancellation = false
        service.result = HighlightMatches(matches: [])
        await click(first)
        check(model.highlights.state == .ready && model.highlights.activeButtonID != nil && editor.highlightRanges.isEmpty,
              "an empty response leaves the button pressed without fake highlights")
        check(model.echo.message == "No matching text remains.", "empty model results are reported in the echo area")
        await click(first)
        service.result = HighlightMatches(matches: [.init(text: "not in this post", occurrence: 1)])
        await click(first)
        check(model.highlights.state == .idle && model.echo.message == HighlightError.invalidResponse.localizedDescription &&
              window.attachedSheet == nil && NSApp.modalWindow == nil && window.firstResponder === editor,
              "invalid intervals are reported non-modally and never partially applied")
        model.echo.message = nil
        await settle()
        service.result = HighlightMatches(matches: [.init(text: "clear", occurrence: 1)])
        await click(first)
        model.newDraft()
        await settle()
        check(model.highlights.state == .idle, "switching drafts clears document-specific highlights")
        highlightStyleRenderingChecks(check: check)
        guard let handoffEditor = model.activeEditor else { check(false, "publishing preview has an editor"); return }
        handoffEditor.insertText("A post to review.", replacementRange: NSRange(location: NSNotFound, length: 0))
        model.prepareHandoff()
        await settle()
        guard let handoff = window.attachedSheet else { check(false, "publishing review opens"); return }
        let previousEcho = echoSnapshot(in: handoff)
        model.notify("A message while reviewing the post.")
        await settle()
        check(previousEcho != nil && echoSnapshot(in: handoff) != previousEcho && window.attachedSheet === handoff &&
              handoff.attachedSheet == nil, "publishing messages appear inside its echo area without opening another dialog")
        model.showHandoff = false
        await settle()
    }

    @MainActor private static func highlightStyleRenderingChecks(check: (Bool, String) -> Void) {
        let view = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 150))
        view.textContainer?.replaceLayoutManager(HighlightLayoutManager())
        view.isEditable = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 20)
        view.textColor = .black
        view.string = "Careful wording wraps across several lines with accents e\u{301} and emoji 😀."
        view.highlightRanges = [NSRange(location: 0, length: (view.string as NSString).length)]
        func bluePixels(_ style: HighlightUnderline) -> [(x: Int, y: Int)] {
            view.highlightStyle = HighlightStyle(underline: style, backgroundColor: nil)
            view.refreshHighlights()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { check(false, "style bitmap is available"); return [] }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var pixels: [(x: Int, y: Int)] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.5, color.blueComponent - color.redComponent > 0.3,
                          color.blueComponent - color.greenComponent > 0.15 else { continue }
                    pixels.append((x, y))
                }
            }
            return pixels
        }
        let solid = bluePixels(.solid)
        let dotted = bluePixels(.dotted)
        let wiggly = bluePixels(.wiggly)
        check(!solid.isEmpty && dotted.count < solid.count,
              "dotted underlines render separate dots instead of a solid stroke")
        let dottedRows = Set(dotted.map(\.y)).sorted()
        if let top = dottedRows.first {
            var bottom = top
            for row in dottedRows.dropFirst() {
                guard row == bottom + 1 else { break }
                bottom = row
            }
            let columns = Set(dotted.filter { $0.y <= bottom }.map(\.x)).sorted()
            if let left = columns.first {
                var right = left
                for column in columns.dropFirst() {
                    guard column == right + 1 else { break }
                    right = column
                }
                check(abs((right - left) - (bottom - top)) <= 1, "dotted underlines use round dots rather than short dashes")
            } else { check(false, "dotted underline has visible dots") }
        } else { check(false, "dotted underline has visible dots") }
        let wigglyRows = Set(wiggly.map(\.y))
        check(wigglyRows.count > Set(solid.map(\.y)).count, "wiggly underlines visibly oscillate rather than drawing a straight line")
        var lineCount = 0
        view.layoutManager!.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: view.layoutManager!.numberOfGlyphs)) { _, _, _, _, _ in lineCount += 1 }
        let rows = wigglyRows.sorted()
        let groups = rows.isEmpty ? 0 : 1 + zip(rows, rows.dropFirst()).filter { $1 - $0 > 2 }.count
        check(lineCount > 1 && groups == lineCount, "wiggly underlines follow every wrapped line, including Unicode")
        view.highlightRanges = []
        check(bluePixels(.wiggly).isEmpty, "clearing highlights removes custom wiggly rendering")
    }

    @MainActor private static func synonymInterface(model: ComposerModel, window: NSWindow, service: SynonymStub,
                                                    check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
        @MainActor func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = .control,
                            in targetWindow: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: (targetWindow ?? window).windowNumber, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        @MainActor func click(at location: NSPoint, in targetWindow: NSWindow? = nil) async {
            let targetWindow = targetWindow ?? window
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: targetWindow.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            await settle()
        }
        model.newDraft()
        await settle()
        guard let editor = model.activeEditor else { check(false, "synonyms require an editor"); return }
        editor.insertText("😀 Help, help.", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        let target = (editor.string as NSString).range(of: "Help")
        editor.setSelectedRange(NSRange(location: target.location + 2, length: 0))
        await settle()
        let frame = window.frame
        guard let scroll = editor.enclosingScrollView else { check(false, "synonyms have an editor viewport"); return }
        func geometry() -> [NSRect] {
            [editor.convert(editor.bounds, to: window.contentView),
             scroll.convert(scroll.bounds, to: window.contentView), scroll.contentView.bounds]
        }
        func toolbarSnapshot(above height: CGFloat) -> Data? {
            Self.toolbarSnapshot(in: window, width: model.composerWidth, above: height)
        }
        let originalGeometry = geometry()
        let originalToolbar = toolbarSnapshot(above: ComposerWindowSizing.echoAreaHeight)
        let originalEcho = echoSnapshot(in: window)
        var layoutSamples: [[NSRect]] = []
        let editorPostedFrames = editor.postsFrameChangedNotifications
        let scrollPostedFrames = scroll.postsFrameChangedNotifications
        let clipPostedBounds = scroll.contentView.postsBoundsChangedNotifications
        editor.postsFrameChangedNotifications = true
        scroll.postsFrameChangedNotifications = true
        scroll.contentView.postsBoundsChangedNotifications = true
        let observations: [(Notification.Name, NSView)] = [
            (NSView.frameDidChangeNotification, editor),
            (NSView.frameDidChangeNotification, scroll),
            (NSView.boundsDidChangeNotification, scroll.contentView)
        ]
        let observers = observations.map { name, view in
            NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { _ in
                MainActor.assumeIsolated { layoutSamples.append(geometry()) }
            }
        }
        service.delay = .milliseconds(600)
        check(editor.performKeyEquivalent(with: key(" ", code: 49)), "Control-Space is handled by the native editor")
        check(model.synonyms.state == .loading, "synonym lookup immediately shows loading")
        await settle()
        check(model.synonyms.state == .loading && toolbarSnapshot(above: ComposerWindowSizing.echoAreaHeight) == originalToolbar &&
              echoSnapshot(in: window) != originalEcho, "loading appears in the minibuffer while the toolbar remains unchanged")
        try? await Task.sleep(for: .milliseconds(600))
        service.delay = .milliseconds(100)
        let ready = SynonymController.State.ready(SynonymStub.lists)
        check(model.synonyms.state == ready, "synonyms display both groups")
        check(service.targets.last == "Help" && service.texts.last == "😀 Help, help.", "the word and its paragraph are sent to Claude")
        check(originalToolbar != nil && toolbarSnapshot(above: SynonymEchoArea.minimumResultsHeight) == originalToolbar,
              "the unchanged toolbar, counter, and Post button shift above the two-line minibuffer")
        check(window.frame == frame && geometry() == originalGeometry, "synonym rows preserve the window, editor frame, viewport, and scroll position")
        NSApp.postEvent(key("\u{1b}", code: 53, modifiers: []), atStart: false)
        await settle()
        check(model.synonyms.state == .idle && toolbarSnapshot(above: ComposerWindowSizing.echoAreaHeight) == originalToolbar &&
              window.frame == frame && geometry() == originalGeometry, "Escape lowers the footer without moving the editor")
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        editor.postsFrameChangedNotifications = editorPostedFrames
        scroll.postsFrameChangedNotifications = scrollPostedFrames
        scroll.contentView.postsBoundsChangedNotifications = clipPostedBounds
        check(layoutSamples.allSatisfy { $0 == originalGeometry }, "the editor never shifts during footer expansion or collapse")

        service.result = SynonymStub.expandedLists
        editor.keyDown(with: key(" ", code: 49))
        try? await Task.sleep(for: .milliseconds(600))
        guard let expandedHeight = echoHeight(in: window) else { check(false, "wrapped synonyms have a visible separator"); return }
        check(model.synonyms.state == .ready(SynonymStub.expandedLists) && expandedHeight > SynonymEchoArea.minimumResultsHeight,
              "twelve suggestions per group wrap onto extra lines (height: \(expandedHeight))")
        let expandedToolbar = toolbarSnapshot(above: expandedHeight)
        check(expandedToolbar == originalToolbar,
              "the unchanged toolbar rises above the wrapped suggestions (height: \(expandedHeight))")
        check(window.frame == frame && geometry() == originalGeometry && window.firstResponder === editor,
              "wrapped synonyms preserve the editor, viewport, window, and focus")
        window.setContentSize(NSSize(width: frame.width + 300, height: window.contentView!.bounds.height))
        await settle()
        check((echoHeight(in: window) ?? expandedHeight) < expandedHeight && model.synonyms.state == .ready(SynonymStub.expandedLists),
              "wider windows fit more synonyms per line without another lookup")
        window.setFrame(frame, display: true)
        await settle()
        await click(at: NSPoint(x: ComposerWindowSizing.textLeading + 43, y: 12))
        let replacement = SynonymTarget.capture(text: editor.string, selection: NSRange(location: target.location + 1, length: 0))?.query ?? ""
        check(SynonymStub.expandedLists.germanic.dropFirst(6).contains(replacement.lowercased()) &&
              editor.string == "😀 \(replacement), help." && model.synonyms.state == .idle,
              "clicking a Germanic suggestion on a wrapped line replaces only the selected word")
        let replacedText = editor.string
        editor.undoManager?.undo()
        check(editor.string == "😀 Help, help.", "wrapped suggestions preserve native undo")
        editor.undoManager?.redo()
        check(editor.string == replacedText, "wrapped suggestions preserve native redo")
        editor.undoManager?.undo()
        editor.setSelectedRange(NSRange(location: target.location + 2, length: 0))
        service.result = SynonymLists(latin: [], germanic: ["back"])
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(model.synonyms.state == .ready(service.result) && echoHeight(in: window) == SynonymEchoArea.minimumResultsHeight,
              "short and empty groups return to the compact two-row layout")
        service.result = SynonymStub.lists
        editor.keyDown(with: key(" ", code: 49))
        await settle()

        window.makeFirstResponder(nil)
        check(model.synonyms.state == ready, "synonyms survive the editor losing focus")
        window.makeFirstResponder(editor)
        if CommandLine.arguments.contains("--skip-activation-check") {
            print("Skipped app-switch activation checks: explicitly disabled for an unattended desktop.")
        } else {
            NSApp.hide(nil)
            await settle()
            check(NSApp.isHidden && !window.isKeyWindow && model.synonyms.state == ready, "synonyms survive switching away from the app")
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            await settle()
            window.makeKeyAndOrderFront(nil)
            await settle()
            check(window.isKeyWindow && model.synonyms.state == ready,
                  "synonyms remain when returning to the app (key=\(window.isKeyWindow), active=\(NSApp.isActive), unchanged=\(model.synonyms.state == ready), keyWindow=\(NSApp.keyWindow?.className ?? "none"))")
        }

        let previousWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(at: NSPoint(x: 110, y: 82 + ComposerWindowSizing.echoAreaHeight))
        guard let picker = NSApp.windows.first(where: { $0.isVisible && !previousWindows.contains($0.windowNumber) }),
              let pickerContent = picker.contentView else {
            check(false, "model link opens the model picker")
            return
        }
        await click(at: NSPoint(x: 70, y: pickerContent.bounds.height - 70), in: picker)
        check(model.synonymModel == .opus && picker.isVisible, "model picker remains open after selecting Opus")
        check(window.firstResponder === editor && model.synonyms.state == ready, "changing models preserves editor focus and existing synonyms")
        await click(at: NSPoint(x: 70, y: 40), in: picker)
        check(model.synonymEffort == .max && picker.isVisible, "reasoning can be selected without reopening the model picker")
        check(model.synonyms.state == ready, "changing reasoning preserves existing synonyms")
        NSApp.postEvent(key("\u{1b}", code: 53, modifiers: [], in: picker), atStart: false)
        await settle()
        check(!picker.isVisible && window.firstResponder === editor && model.synonyms.state == ready,
              "Escape closes the picker without dismissing synonyms")
        let visibleWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(at: NSPoint(x: 110, y: 82 + ComposerWindowSizing.echoAreaHeight))
        guard let reopenedPicker = NSApp.windows.first(where: { $0.isVisible && !visibleWindows.contains($0.windowNumber) }) else {
            check(false, "model link reopens after Escape")
            return
        }
        await click(at: NSPoint(x: 30, y: 82 + ComposerWindowSizing.echoAreaHeight))
        check(!reopenedPicker.isVisible && model.synonyms.state == ready, "clicking outside closes the picker without dismissing synonyms")
        let restored = ComposerModel(directory: model.storage.directory, preferences: preferences(for: model.storage.directory))
        check(restored.synonymModel == .opus && restored.synonymEffort == .max, "model and reasoning picker selections persist outside the view")

        await click(at: NSPoint(x: model.composerWidth - 25, y: window.contentView!.bounds.height - 26))
        check(model.showDrafts && model.synonyms.state == ready, "clicking the drawer icon preserves synonyms")
        NSApp.postEvent(key("d", code: 2, modifiers: .command), atStart: false)
        await settle()
        check(!model.showDrafts && model.synonyms.state == ready, "Command-D closes the drawer without dismissing synonyms")
        model.draft.modified = Date()
        await settle()
        check(model.synonyms.state == ready, "draft metadata changes preserve synonyms")

        NSApp.postEvent(key("\u{f702}", code: 123, modifiers: []), atStart: false)
        await settle()
        check(editor.selectedRange().location == target.location + 1 && model.synonyms.state == ready,
              "arrow keys within the word preserve synonyms")
        editor.setSelectedRange(target)
        check(model.synonyms.state == ready, "selecting only the target word preserves synonyms")
        await click(at: NSPoint(x: ComposerWindowSizing.textLeading + 43, y: 34))
        check(editor.string == "😀 Assist, help." && model.draft.posts[0].text == editor.string, "replacement changes only the targeted occurrence")
        check(model.synonyms.state == .idle && window.frame == frame, "replacement collapses the minibuffer without resizing the window")
        editor.undoManager?.undo()
        check(editor.string == "😀 Help, help.", "synonym replacement supports undo")
        editor.undoManager?.redo()
        check(editor.string == "😀 Assist, help.", "synonym replacement supports redo")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "help").location + 1, length: 0))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(service.models.last == .opus && service.efforts.last == .max, "subsequent lookups use the selected model and reasoning")
        await click(at: NSPoint(x: ComposerWindowSizing.textLeading + 43, y: 12))
        check(editor.string == "😀 Assist, back.", "clicking a Germanic synonym replaces the word")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "back").location + 1, length: 0))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        editor.keyDown(with: key("z", code: 6, modifiers: []))
        check(model.synonyms.state == .idle && editor.string.contains("bzack"), "ordinary typing dismisses synonyms without swallowing input")

        service.ignoreCancellation = true
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.keyDown(with: key(" ", code: 49))
        try? await Task.sleep(for: .milliseconds(20))
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        check(model.synonyms.state == .loading, "movement inside the word preserves a pending lookup")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "bzack").location + 1, length: 0))
        check(model.synonyms.state == .idle, "leaving the word cancels a pending lookup")
        await settle()
        check(model.synonyms.state == .idle, "late cancelled results cannot reappear")
        editor.keyDown(with: key(" ", code: 49))
        try? await Task.sleep(for: .milliseconds(20))
        NSApp.postEvent(key("\u{1b}", code: 53, modifiers: []), atStart: false)
        await settle()
        check(model.synonyms.state == .idle, "Escape cancels pending lookups and suppresses late results")
        service.ignoreCancellation = false

        service.authenticated = false
        editor.keyDown(with: key(" ", code: 49))
        try? await Task.sleep(for: .milliseconds(20))
        check(model.synonyms.state == .signingIn, "first use starts Claude's sign-in flow")
        window.makeFirstResponder(nil)
        check(model.synonyms.state == .signingIn, "browser sign-in can temporarily take focus")
        await settle()
        check(service.signIns == 1 && model.synonyms.state == ready, "lookup completes after sign-in without editor focus")
        window.makeFirstResponder(editor)
        let selection = editor.selectedRange()
        NSApp.postEvent(key("\u{1b}", code: 53, modifiers: []), atStart: false)
        await settle()
        check(model.synonyms.state == .idle && editor.selectedRange() == selection, "Escape dismisses results without moving the cursor")

        editor.keyDown(with: key(" ", code: 49))
        await settle()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        check(model.synonyms.state == .idle, "moving outside the word dismisses ready results")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        model.newDraft()
        check(model.synonyms.state == .idle, "switching drafts dismisses results for the previous editor")
        await settle()
        guard let editor = model.activeEditor else { check(false, "new draft requires an editor"); return }
        editor.insertText("Skip this paragraph.\n\nFirst sentence. With each update add something nice. Last sentence.\n\nSkip this too.",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.setSelectedRange((editor.string as NSString).range(of: "update"))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(service.targets.last == "update" && service.texts.last == "First sentence. With each update add something nice. Last sentence.\n",
              "native lookups send the selected word and its whole paragraph without neighboring paragraphs")

        let phraseText = "😀 Please lend a hand with this, then lend a hand. Keep this sentence."
        editor.selectAll(nil)
        editor.insertText(phraseText, replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        let phraseRange = (phraseText as NSString).range(of: "lend a hand")
        let phraseSelection = NSRange(location: phraseRange.location - 1, length: phraseRange.length + 2)
        editor.setSelectedRange(phraseSelection)
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(model.synonyms.state == ready && service.targets.last == " lend a hand " &&
              service.texts.last == phraseText,
              "selected phrases request single-word alternatives with exact selection and full paragraph context")
        await click(at: NSPoint(x: ComposerWindowSizing.textLeading + 43, y: 34))
        let replacedPhrase = "😀 Please assist with this, then lend a hand. Keep this sentence."
        check(editor.string == replacedPhrase && model.draft.posts[0].text == replacedPhrase,
              "clicking a synonym replaces the whole phrase once and preserves surrounding whitespace")
        editor.undoManager?.undo()
        check(editor.string == phraseText, "undo restores the complete phrase")
        editor.undoManager?.redo()
        check(editor.string == replacedPhrase, "redo reapplies the single-word phrase replacement")
        editor.undoManager?.undo()
        editor.setSelectedRange(phraseSelection)
        service.ignoreCancellation = true
        editor.keyDown(with: key(" ", code: 49))
        try? await Task.sleep(for: .milliseconds(20))
        editor.setSelectedRange(NSRange(location: phraseRange.location, length: 4))
        check(model.synonyms.state == .idle, "changing the selected phrase cancels a pending lookup")
        await settle()
        check(model.synonyms.state == .idle, "late phrase results cannot replace a newly selected target")
        service.ignoreCancellation = false

        service.failure = ClaudeCLIError.failed("Synthetic Claude failure")
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(model.echo.message == "Synthetic Claude failure" && model.synonyms.state == .idle &&
              window.attachedSheet == nil && NSApp.modalWindow == nil && window.firstResponder === editor,
              "Claude errors replace the synonym view in the echo area without taking focus")
        let textBeforeError = editor.string
        editor.setSelectedRange(NSRange(location: (textBeforeError as NSString).length, length: 0))
        NSApp.postEvent(key("x", code: 7, modifiers: []), atStart: false)
        await settle()
        check(editor.string == textBeforeError + "x" && model.echo.message == nil,
              "typing after a model error clears the message without swallowing input")
        let end = editor.selectedRange().location
        model.notify("Before moving the cursor")
        NSApp.postEvent(key("\u{f702}", code: 123, modifiers: []), atStart: false)
        await settle()
        check(model.echo.message == nil && editor.selectedRange().location == end - 1,
              "moving the text cursor clears the message without swallowing the movement")
        let selectionBeforeEscape = editor.selectedRange()
        model.notify("Before Escape")
        NSApp.postEvent(key("\u{1b}", code: 53, modifiers: []), atStart: false)
        await settle()
        check(model.echo.message == nil && editor.selectedRange() == selectionBeforeEscape && window.firstResponder === editor,
              "Escape clears the message without changing the selection or focus")
        model.notify("Before scrolling")
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0),
           let scroll = NSEvent(cgEvent: event) {
            NSApp.postEvent(scroll, atStart: false)
            await settle()
            check(model.echo.message == nil, "scrolling clears the message")
        } else { check(false, "scroll event can be constructed") }
        model.notify("Before saving")
        NSApp.postEvent(key("s", code: 1, modifiers: .command), atStart: false)
        await settle()
        check(model.echo.message == "Draft saved", "a command's new message survives the action that produced it")
        service.failure = nil
        let longText = String(repeating: "A line with help.\n", count: 80)
        editor.insertText(longText, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        await settle()
        guard let longScroll = editor.enclosingScrollView else { check(false, "long post has a viewport"); return }
        let longSource = longText as NSString
        editor.setSelectedRange(longSource.range(of: "help", range: NSRange(location: 200, length: longSource.length - 200)))
        longScroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        longScroll.reflectScrolledClipView(longScroll.contentView)
        await settle()
        let longFrame = window.frame
        let longViewport = longScroll.convert(longScroll.bounds, to: window.contentView)
        let longOffset = longScroll.contentView.bounds
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(model.synonyms.state == ready && window.frame == longFrame &&
              longScroll.convert(longScroll.bounds, to: window.contentView) == longViewport &&
              longScroll.contentView.bounds == longOffset, "expanding over a long post preserves its viewport and scrolled position")
        model.notify("A new status message")
        await settle()
        check(model.synonyms.state == .idle && model.echo.message == "A new status message" && window.frame == longFrame &&
              longScroll.convert(longScroll.bounds, to: window.contentView) == longViewport &&
              longScroll.contentView.bounds == longOffset, "new messages replace synonyms and lower the overlay without moving the text")
        await settle()
    }

    @MainActor private static func echoHeight(in window: NSWindow) -> CGFloat? {
        guard let view = window.contentView else { return nil }
        // Only the minibuffer separator crosses the left gutter, outside the toolbar's padding.
        let rect = view.convert(NSRect(x: 4, y: 0, width: 1, height: view.bounds.height), from: nil)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        var border: NSColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { border = Theme.borderNS.usingColorSpace(.sRGB) }
        guard let border else { return nil }
        let scale = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let margin = Int(12 * scale)
        for y in margin..<(bitmap.pixelsHigh - margin) {
            guard let color = bitmap.colorAt(x: 0, y: y)?.usingColorSpace(.sRGB) else { continue }
            if abs(color.redComponent - border.redComponent) < 0.025 &&
               abs(color.greenComponent - border.greenComponent) < 0.025 &&
               abs(color.blueComponent - border.blueComponent) < 0.025 {
                return CGFloat(bitmap.pixelsHigh - y) / scale
            }
        }
        return nil
    }

    @MainActor private static func toolbarSnapshot(in window: NSWindow, width: CGFloat, above height: CGFloat) -> Data? {
        guard let view = window.contentView else { return nil }
        let rect = view.convert(NSRect(x: 0, y: height, width: width, height: ComposerWindowSizing.toolbarHeight), from: nil)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor private static func echoSnapshot(in window: NSWindow) -> Data? {
        guard let view = window.contentView else { return nil }
        let rect = view.convert(NSRect(x: 0, y: 0, width: view.bounds.width, height: ComposerWindowSizing.echoAreaHeight), from: nil)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor private static func commandChecks(log: ModelSessionLog, check: (Bool, String) -> Void) async {
        let environment = ["PATH": "/usr/bin:/bin"]
        do {
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-CLI-check-\(UUID())")
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            defer {
                do { try FileManager.default.removeItem(at: fixture) }
                catch { check(false, "could not remove CLI fixture: \(error)") }
            }
            let script = fixture.appendingPathComponent("claude")
            let source = """
            #!/bin/sh
            set -eu
            [ -n "$CLAUDE_CONFIG_DIR" ] || exit 2
            [ -z "${ANTHROPIC_API_KEY-}" ] || exit 3
            action=
            schema=
            session=
            resume=false
            previous=
            for arg in "$@"; do
                case "$previous" in
                    --session-id) session="$arg";;
                    --resume) session="$arg"; resume=true;;
                    --json-schema) schema="$arg";;
                esac
                case "$arg" in status|login|--print) action="$arg";; esac
                previous="$arg"
            done
            case "$action" in
                status)
                    if [ -f "$CLAUDE_CONFIG_DIR/signed-in" ]; then
                        printf '%s' '{"loggedIn":true,"authMethod":"claude.ai"}'
                    else
                        printf '%s' '{"loggedIn":false,"authMethod":"none"}'
                        exit 1
                    fi;;
                login)
                    touch "$CLAUDE_CONFIG_DIR/signed-in";;
                --print)
                    cat > "$CLAUDE_CONFIG_DIR/request.json"
                    printf '%s\\n' "$@" > "$CLAUDE_CONFIG_DIR/arguments.txt"
                    if grep -q 'CANCEL_LOG' "$CLAUDE_CONFIG_DIR/request.json"; then
                        printf '%s' 'Partial model output'
                        printf '%s' 'Partial diagnostic' >&2
                        exec sleep 5
                    elif grep -q 'BAD_OUTPUT_LOG' "$CLAUDE_CONFIG_DIR/request.json"; then
                        printf '%s' 'Malformed model output'
                        printf '%s' 'Full diagnostic output' >&2
                    elif printf '%s' "$schema" | grep -q '"matches"'; then
                        printf '%s' '{"type":"result","is_error":false,"structured_output":{"matches":[{"text":"clear","occurrence":2,"note":"Try a more specific word."}]}}'
                    elif printf '%s' "$schema" | grep -q '"answer"'; then
                        [ -n "$session" ] || exit 6
                        transcript="$CLAUDE_CONFIG_DIR/session-$session"
                        if [ "$resume" = true ]; then
                            [ -f "$transcript" ] || exit 7
                            [ "$(cat "$transcript.cwd")" = "$PWD" ] || exit 8
                            cp "$transcript" "$CLAUDE_CONFIG_DIR/resumed.jsonl"
                            answer='A continued response.'
                        else
                            [ ! -e "$transcript" ] || exit 9
                            printf '%s' "$PWD" > "$transcript.cwd"
                            answer='A short response.'
                        fi
                        cat "$CLAUDE_CONFIG_DIR/request.json" >> "$transcript"
                        printf '\\n{"answer":"%s"}\\n' "$answer" >> "$transcript"
                        printf '{"type":"result","is_error":false,"session_id":"%s","structured_output":{"answer":"%s"}}' "$session" "$answer"
                    else
                        printf '%s' '{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["back"]}}'
                    fi;;
                *) exit 5;;
            esac
            """
            try Data(source.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let cli = ClaudeCLI(configurationDirectory: fixture.appendingPathComponent("profile"), executable: script, log: log)
            let initialLogCount = log.entries.count
            check(try await !cli.isAuthenticated(), "signed-out CLI status requests login")
            try await cli.signIn()
            check(try await cli.isAuthenticated(), "CLI-owned sign-in is checked before lookup")
            check(log.entries.count == initialLogCount, "authentication status and browser sign-in are never included in the model log")
            let sentence = #"Please "lend a hand" with 😀 updates."#
            let synonymContext = ModelContext.capture(text: sentence, selection: (sentence as NSString).range(of: "lend a hand"))!
            for (model, effort) in [(ClaudeModel.fable, ClaudeEffort.low), (.opus, .high), (.sonnet, .xhigh), (.haiku, .max), (.fable, .medium)] {
                check(try await cli.synonyms(context: synonymContext, model: model, effort: effort) == SynonymLists(latin: ["assist"], germanic: ["back"]),
                      "CLI service reads structured results end to end")
                let arguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8).components(separatedBy: "\n")
                let options = Array(zip(arguments, arguments.dropFirst()))
                check(options.contains { $0.0 == "--model" && $0.1 == model.rawValue } &&
                      options.contains { $0.0 == "--effort" && $0.1 == effort.rawValue } &&
                      arguments.contains("--no-session-persistence") && !arguments.contains("--resume"),
                      "CLI requests \(model.title) with \(effort.title) effort without persisting synonym sessions")
            }
            let request = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(request == ["target": "lend a hand", "text": sentence], "CLI sends the whole phrase and its paragraph using the shared JSON envelope")
            let highlightedText = "😀 clear and clear."
            let highlightPrompt = #"Highlight the second "clear"."#
            let highlightContext = ModelContext.capture(text: highlightedText, selection: (highlightedText as NSString).range(of: "clear"))!
            let highlights = try await cli.highlights(context: highlightContext, prompt: highlightPrompt, model: .opus, effort: .xhigh)
            check(try highlights.ranges(in: highlightedText) == [NSRange(location: 13, length: 5)], "CLI highlight response resolves exact Unicode-aware intervals")
            check(try highlights.intervals(in: highlightedText).first?.note == "Try a more specific word.",
                  "the CLI decodes optional per-interval notes without confusing them with quoted text")
            let highlightRequest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(highlightRequest == ["prompt": highlightPrompt, "target": "clear", "text": highlightedText],
                  "highlight CLI uses the shared prompt, target, and paragraph envelope without shell interpolation")
            let highlightArguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8).components(separatedBy: "\n")
            let highlightOptions = Array(zip(highlightArguments, highlightArguments.dropFirst()))
            check(highlightOptions.contains { $0 == "--model" && $1 == ClaudeModel.opus.rawValue } &&
                  highlightOptions.contains { $0 == "--effort" && $1 == ClaudeEffort.xhigh.rawValue } &&
                  highlightOptions.contains { $0 == "--json-schema" && $1 == ClaudeCLI.highlightSchema } &&
                  highlightOptions.contains { $0 == "--tools" && $1.isEmpty } &&
                  highlightArguments.contains("--no-session-persistence"), "highlight CLI uses current model, effort, interval schema, no tools, and no persisted session")
            let prompt = #"Explain "this" briefly."#
            let selectedText = "😀 selected text\nwith a second line"
            let promptContext = ModelContext.capture(text: selectedText, selection: NSRange(location: 0, length: (selectedText as NSString).length))!
            let conversation = PromptConversation()
            let reply = try await cli.reply(to: prompt, context: promptContext, conversation: conversation, model: .haiku, effort: .low)
            let promptRequest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(reply == "A short response." && promptRequest == ["prompt": prompt, "target": selectedText, "text": selectedText],
                  "prompt CLI sends the user's exact request and selected Unicode text as JSON and decodes the reply")
            let promptArguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8)
            check(promptArguments.contains(ClaudeCLI.promptSystemPrompt) && promptArguments.contains(ClaudeCLI.promptSchema) &&
                  promptArguments.contains("--model\n\(ClaudeModel.haiku.rawValue)") && promptArguments.contains("--effort\nlow") &&
                  promptArguments.contains("--tools\n\n") && !promptArguments.contains("--no-session-persistence") &&
                  promptArguments.contains("--session-id\n\(conversation.id.uuidString)") && !promptArguments.contains("--resume") &&
                  promptArguments.contains("--strict-mcp-config"),
                  "prompt CLI starts an explicit isolated conversation with the configured model, short response schema, and no tools")
            conversation.hasReply = true
            let followUp = "Explain further"
            let continued = try await cli.reply(to: followUp, context: promptContext, conversation: conversation, model: .haiku, effort: .low)
            let resumeArguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8)
            func resumedHistory() throws -> [[String: String]] {
                try String(contentsOf: fixture.appendingPathComponent("profile/resumed.jsonl"), encoding: .utf8)
                    .split(separator: "\n").map { try JSONDecoder().decode([String: String].self, from: Data($0.utf8)) }
            }
            let previousTurns = [["prompt": prompt, "target": selectedText, "text": selectedText], ["answer": reply]]
            check(try continued == "A continued response." && resumedHistory() == previousTurns &&
                  resumeArguments.contains("--resume\n\(conversation.id.uuidString)") &&
                  !resumeArguments.contains("--session-id") && !resumeArguments.contains("--continue"),
                  "follow-up CLI invocation resumes the explicit session in the same directory with the original prompt, context, and assistant reply")
            _ = try await cli.reply(to: "And why?", context: promptContext, conversation: conversation, model: .haiku, effort: .low)
            check(try resumedHistory() == previousTurns + [["prompt": followUp, "target": selectedText, "text": selectedText], ["answer": continued]],
                  "third CLI turn restores every earlier user and assistant turn, not just the previous response")
            let cleanupDirectory: URL
            do {
                let fresh = PromptConversation()
                cleanupDirectory = fresh.directory
                let emptyContext = ModelContext.capture(text: "", selection: NSRange(location: 0, length: 0))!
                let freshReply = try await cli.reply(to: prompt, context: emptyContext, conversation: fresh, model: .sonnet, effort: .medium)
                let freshArguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8)
                check(freshReply == reply && freshArguments.contains("--session-id\n\(fresh.id.uuidString)") &&
                      !freshArguments.contains("--resume") && fresh.directory != conversation.directory,
                      "a new conversation cannot inherit the previous conversation's transcript or working directory")
            }
            check(!FileManager.default.fileExists(atPath: cleanupDirectory.path), "ending a conversation removes its isolated temporary working directory")
            let noContext = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(noContext == ["prompt": prompt, "text": ""], "prompt CLI omits the target but still includes shared context for an empty editor")
            let entries = Array(log.entries.dropFirst(initialLogCount))
            check(entries.count == 10 && Set(entries.map(\.feature)) == ["Synonyms", "Highlights", "Conversation"] &&
                  entries.allSatisfy { $0.response?.status == 0 && $0.error == nil },
                  "one shared log records every synonym, highlight, and conversation request and response")
            check(try entries[0].arguments.contains(ClaudeCLI.systemPrompt) && entries[0].arguments.contains(ClaudeCLI.schema) &&
                  entries[5].arguments.contains(ClaudeCLI.highlightSystemPrompt) && entries[5].input == highlightContext.input(prompt: highlightPrompt) &&
                  entries[6].input == promptContext.input(prompt: prompt) &&
                  String(decoding: entries[6].response!.output, as: UTF8.self).contains(conversation.id.uuidString) &&
                  entries[7].arguments.contains("--resume"),
                  "the log retains exact system prompts, schemas, payloads, raw responses, and conversation-resume arguments")
            do {
                _ = try await cli.reply(to: "BAD_OUTPUT_LOG", context: promptContext, conversation: PromptConversation(), model: .haiku, effort: .low)
                check(false, "malformed output must fail")
            } catch PromptError.invalidResponse {
                check(log.entries.last?.response?.output == Data("Malformed model output".utf8) &&
                      log.entries.last?.response?.diagnostics == Data("Full diagnostic output".utf8),
                      "malformed responses and full diagnostics remain visible in the log even when decoding fails")
            }
            let cancelled = Task {
                try await cli.reply(to: "CANCEL_LOG", context: promptContext, conversation: PromptConversation(), model: .haiku, effort: .low)
            }
            try await Task.sleep(for: .milliseconds(150))
            check(log.entries.last?.response == nil && log.entries.last?.input.contains("CANCEL_LOG") == true,
                  "pending requests are logged before a response arrives")
            cancelled.cancel()
            do { _ = try await cancelled.value; check(false, "cancelled logged request must fail") }
            catch is CancellationError {
                check(log.entries.last?.error == "Cancelled." &&
                      log.entries.last?.response?.output == Data("Partial model output".utf8) &&
                      log.entries.last?.response?.diagnostics == Data("Partial diagnostic".utf8),
                      "cancelled requests retain partial output and diagnostics instead of losing the exchange")
            }
            check(ModelSessionLog().entries.isEmpty, "a new app-session log does not restore previous requests")
            do {
                let wrongSession = Data("""
                {"type":"result","is_error":false,"session_id":"\(UUID())","structured_output":{"answer":"Wrong conversation."}}
                """.utf8)
                _ = try ClaudeCLI.decodePrompt(.init(status: 0, output: wrongSession), sessionID: conversation.id)
                check(false, "a reply from an unexpected session must fail")
            } catch PromptError.invalidResponse { check(true, "a reply from an unexpected session is rejected") }
            let echo = try await ClaudeCommand().run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                                                     environment: environment, input: #"{"word":"help"}"#, timeout: 5)
            check(echo.status == 0 && String(decoding: echo.output, as: UTF8.self) == #"{"word":"help"}"#, "CLI input and output are piped without a shell")
            do {
                _ = try await ClaudeCommand().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"],
                                                   environment: environment, input: "", timeout: 0.05)
                check(false, "CLI timeout must fail")
            } catch ClaudeCLIError.timedOut { check(true, "timed-out CLI processes are terminated") }
            let pending = Task {
                try await ClaudeCommand().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"],
                                               environment: environment, input: "", timeout: 10)
            }
            try await Task.sleep(for: .milliseconds(30))
            pending.cancel()
            do { _ = try await pending.value; check(false, "cancelled CLI must not return output") }
            catch is CancellationError { check(true, "cancelled CLI processes are terminated") }
        } catch { check(false, "CLI lifecycle check failed: \(error)") }
    }
}
