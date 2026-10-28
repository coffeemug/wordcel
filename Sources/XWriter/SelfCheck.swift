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
        var authenticated = true
        var signIns = 0
        var words: [String] = []
        var sentences: [String] = []
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
        func synonyms(for word: String, in sentence: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> SynonymLists {
            words.append(word)
            sentences.append(sentence)
            models.append(model)
            efforts.append(effort)
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return Self.lists
        }
    }

    @MainActor static func interface(model: ComposerModel, window: NSWindow, synonymService: SynonymStub) {
        Task { @MainActor in
            var checks = 0
            func require(_ condition: @autoclosure () -> Bool, _ name: String) {
                guard condition() else { fputs("UI FAIL: \(name)\n", stderr); exit(1) }
                checks += 1
            }
            func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
            @MainActor func clickHeader(at x: CGFloat) async {
                let location = NSPoint(x: x, y: window.contentView!.bounds.height - 26)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    window.sendEvent(event)
                }
                await settle()
            }
            guard let editor = model.activeEditor else { fputs("UI FAIL: no active editor\n", stderr); exit(1) }
            let initialFrame = window.frame
            let autosaveName = "XWriter-UI-\(UUID())"
            window.setFrameAutosaveName(autosaveName)
            window.saveFrame(usingName: autosaveName)
            require(model.avatar != nil, "profile photo loads")
            require(window.firstResponder === editor, "editor receives initial focus")
            require(editor.bounds.width > 400, "editor has usable width")
            editor.insertText("Hello #native", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(model.draft.posts[0].text == "Hello #native", "native typing updates the model")
            editor.breakUndoCoalescing()
            editor.undoManager?.undo()
            require(model.draft.posts[0].text.isEmpty, "native undo")
            editor.undoManager?.redo()
            require(model.draft.posts[0].text == "Hello #native", "native redo")
            let editorWidth = editor.bounds.width
            await clickHeader(at: initialFrame.width - 25)
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
            editor.selectAll(nil)
            editor.insertText("First post", replacementRange: editor.selectedRange())
            await settle()
            require(abs(window.frame.height - initialFrame.height) < 2, "deleting text shrinks the window")
            model.addPost()
            await settle()
            require(model.draft.posts.count == 2, "thread adds an editor")
            guard let second = model.activeEditor else { exit(1) }
            require(second !== editor && window.firstResponder === second, "new thread post receives focus")
            second.insertText("Second post", replacementRange: NSRange(location: NSNotFound, length: 0))
            require(model.draft.posts[1].text == "Second post" && model.canPost, "second editor binds to its own post")
            model.removePost(model.draft.posts[1].id)
            window.setContentSize(NSSize(width: 560, height: 300))
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
            window.setContentSize(NSSize(width: 1000, height: window.contentView!.bounds.height))
            window.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
            await settle()
            require(NSApp.mainMenu?.performKeyEquivalent(with: draftsShortcut) == true, "Command-D works with drawer open")
            await settle()
            require(!model.showDrafts, "Command-D closes the drawer")
            require(abs(window.frame.width - (1000 - ComposerWindowSizing.drawerWidth)) < 1, "closing respects resizing while drawer is open")
            await synonymInterface(model: model, window: window, service: synonymService) { require($0, $1) }
            await commandChecks { require($0, $1) }
            require(model.save(), "edited content persists")
            UserDefaults.standard.removePersistentDomain(forName: model.storage.directory.lastPathComponent)
            try? FileManager.default.removeItem(at: model.storage.directory)
            print("Passed \(checks) native UI checks: editing, drafts drawer, sizing, synonyms, CLI lifecycle, focus, and persistence.")
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
        check(!Poll().valid, "empty poll cannot be posted")
        check(Poll(choices: ["Yes", "No"]).valid, "completed poll")
        check(!Poll(choices: ["Yes", "No"], days: 7, hours: 1).valid, "poll maximum duration")
        check(!Poll(choices: ["Yes", "No"], days: 0, minutes: 4).valid, "poll minimum duration")
        check(!Poll(choices: [String(repeating: "x", count: 26), "No"]).valid, "poll choice limit")
        let original = "Hello & goodbye? #swift + 日本語 👋\nSecond line"
        let url = ComposerModel.intentURL(for: original)
        check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == original, "handoff URL encoding")
        let targetText = "😀 Help, help."
        let helpRange = (targetText as NSString).range(of: "Help")
        let target = SynonymTarget.capture(text: targetText, selection: NSRange(location: helpRange.location + 2, length: 0))
        check(target?.word == "Help" && target?.range == helpRange, "synonyms target the word under a UTF-16 cursor")
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
        check(SynonymTarget.capture(text: "help me", selection: NSRange(location: 0, length: 7)) == nil,
              "synonyms reject selections spanning words")
        check(SynonymTarget.capture(text: "  😀 123", selection: NSRange(location: 1, length: 0)) == nil,
              "synonyms reject whitespace and nonword targets")
        for (text, expected) in [
            ("Earlier news. 😀 With each update add something nice. Keep it simple.", "😀 With each update add something nice."),
            ("First line.\n\nwith each update add something nice", "with each update add something nice"),
            ("We update the draft. Each update adds something nice.", "Each update adds something nice.")
        ] {
            let range = (text as NSString).range(of: "update", options: .backwards)
            let target = SynonymTarget.capture(text: text, selection: NSRange(location: NSMaxRange(range), length: 0))
            check(target?.word == "update" && target?.sentence == expected, "lookup extracts only the target sentence: \(expected)")
        }
        do {
            let response = ClaudeCommand.Result(status: 0, output: Data(#"{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["back"]}}"#.utf8))
            let lists = try ClaudeCLI.decode(response)
            check(lists.latin == ["assist"] && lists.germanic == ["back"], "Claude structured synonym output is decoded")
            for invalid in [
                #"{"type":"result","is_error":false,"result":"No structured output"}"#,
                #"{"type":"result","is_error":true,"result":"Usage limit reached"}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["assist\nignore"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["progress report"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["prop up"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["progress\u00a0report"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["Assist"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":["a","b","c","d","e","f","g"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["a","b","c","d","e","f","g"]}}"#
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
        check(shrunk.height == 332 && shrunk.maxY == expanded.maxY, "shrinking preserves the top edge and minimum height")
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
            model.draft.plannedDate = Date(timeIntervalSince1970: 1800000000)
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
            check(restored.draft.audience == .following && restored.draft.plannedDate != nil, "restore metadata")
            model.addPost()
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
            model.draft.posts[0].attachments = [Attachment(name: "test.png", data: Data([1, 2, 3]), alt: "An image")]
            check(model.save(), "save attachments")
            let archive = try store.read()
            check(archive.current.posts[0].attachments.first?.alt == "An image", "attachment descriptions persist")
            model.deleteDraft(firstID)
            check(!model.draft.hasContent && model.drafts.count == 1, "delete current draft")
            let afterDelete = try store.read()
            check(afterDelete.drafts.allSatisfy { $0.id != firstID }, "deletion persists")
            try Data("bad json".utf8).write(to: store.file)
            let protected = ComposerModel(directory: directory, preferences: preferences)
            check(protected.error != nil && !protected.save(), "corrupt storage is protected")
            let untouched = try Data(contentsOf: store.file)
            check(untouched == Data("bad json".utf8), "corrupt file is not overwritten")
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        print("Passed \(count) checks: character weighting, post validation, URL encoding, drafts, threads, attachments, and storage recovery.")
    }

    @MainActor private static func synonymInterface(model: ComposerModel, window: NSWindow, service: SynonymStub,
                                                    check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
        @MainActor func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = .control) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
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
        check(editor.performKeyEquivalent(with: key(" ", code: 49)), "Control-Space is handled by the native editor")
        check(model.synonyms.state == .loading, "synonym lookup immediately shows loading")
        await settle()
        let ready = SynonymController.State.ready(SynonymStub.lists)
        check(model.synonyms.state == ready, "synonyms display both groups")
        check(service.words.last == "Help" && service.sentences.last == "😀 Help, help.", "the word and its sentence are sent to Claude")
        check(window.frame == frame, "synonym rows preserve the composer frame")

        window.makeFirstResponder(nil)
        check(model.synonyms.state == ready, "synonyms survive the editor losing focus")
        window.makeFirstResponder(editor)
        NSApp.hide(nil)
        await settle()
        check(NSApp.isHidden && !window.isKeyWindow && model.synonyms.state == ready, "synonyms survive switching away from the app")
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        check(window.isKeyWindow && model.synonyms.state == ready, "synonyms remain when returning to the app")

        let previousWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(at: NSPoint(x: 110, y: 82))
        guard let picker = NSApp.windows.first(where: { $0.isVisible && !previousWindows.contains($0.windowNumber) }),
              let pickerContent = picker.contentView else {
            check(false, "model link opens the model picker")
            return
        }
        await click(at: NSPoint(x: 70, y: pickerContent.bounds.height - 70), in: picker)
        check(model.synonymModel == .opus && !picker.isVisible, "model picker selects Opus and closes")
        check(window.firstResponder === editor && model.synonyms.state == ready, "changing models preserves editor focus and existing synonyms")
        let visibleWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(at: NSPoint(x: 110, y: 82))
        guard let effortPicker = NSApp.windows.first(where: { $0.isVisible && !visibleWindows.contains($0.windowNumber) }) else {
            check(false, "model link reopens to choose reasoning")
            return
        }
        await click(at: NSPoint(x: 70, y: 40), in: effortPicker)
        check(model.synonymEffort == .max && !effortPicker.isVisible, "reasoning picker selects Max and closes")
        check(window.firstResponder === editor && model.synonyms.state == ready, "changing reasoning preserves focus and existing synonyms")
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
        await click(at: NSPoint(x: 100, y: 40))
        check(editor.string == "😀 Assist, help." && model.draft.posts[0].text == editor.string, "replacement changes only the targeted occurrence")
        check(model.synonyms.state == .idle, "replacement restores the icons")
        editor.undoManager?.undo()
        check(editor.string == "😀 Help, help.", "synonym replacement supports undo")
        editor.undoManager?.redo()
        check(editor.string == "😀 Assist, help.", "synonym replacement supports redo")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "help").location + 1, length: 0))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(service.models.last == .opus && service.efforts.last == .max, "subsequent lookups use the selected model and reasoning")
        await click(at: NSPoint(x: 100, y: 18))
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
        editor.insertText("Skip this sentence. With each update add something nice. Skip this too.",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.setSelectedRange((editor.string as NSString).range(of: "update"))
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(service.words.last == "update" && service.sentences.last == "With each update add something nice.",
              "native lookups send the selected word's sentence without adjacent sentences")

        service.failure = ClaudeCLIError.failed("Synthetic Claude failure")
        editor.keyDown(with: key(" ", code: 49))
        await settle()
        check(model.error == "Synthetic Claude failure" && model.synonyms.state == .idle, "Claude errors restore the toolbar and are surfaced")
        model.error = nil
        service.failure = nil
        await settle()
    }

    @MainActor private static func commandChecks(check: (Bool, String) -> Void) async {
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
            for arg in "$@"; do
                case "$arg" in status|login|--print) action="$arg";; esac
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
                    printf '%s' '{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["back"]}}';;
                *) exit 5;;
            esac
            """
            try Data(source.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let cli = ClaudeCLI(configurationDirectory: fixture.appendingPathComponent("profile"), executable: script)
            check(try await !cli.isAuthenticated(), "signed-out CLI status requests login")
            try await cli.signIn()
            check(try await cli.isAuthenticated(), "CLI-owned sign-in is checked before lookup")
            let sentence = #"Please "help" me with 😀 updates."#
            for (model, effort) in [(ClaudeModel.fable, ClaudeEffort.low), (.opus, .high), (.sonnet, .xhigh), (.haiku, .max), (.fable, .medium)] {
                check(try await cli.synonyms(for: "help", in: sentence, model: model, effort: effort) == SynonymLists(latin: ["assist"], germanic: ["back"]),
                      "CLI service reads structured results end to end")
                let arguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8).components(separatedBy: "\n")
                let options = Array(zip(arguments, arguments.dropFirst()))
                check(options.contains { $0.0 == "--model" && $0.1 == model.rawValue } &&
                      options.contains { $0.0 == "--effort" && $0.1 == effort.rawValue }, "CLI requests \(model.title) with \(effort.title) effort")
            }
            let request = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(request == ["word": "help", "sentence": sentence], "CLI sends only the word and sentence as safely encoded JSON")
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
