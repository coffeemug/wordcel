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
        var targets: [String] = []
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
        func synonyms(for target: String, in sentence: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> SynonymLists {
            targets.append(target)
            sentences.append(sentence)
            models.append(model)
            efforts.append(effort)
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return Self.lists
        }
    }

    @MainActor final class HighlightStub: HighlightService {
        var authenticated = true
        var signIns = 0
        var texts: [String] = []
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
        func highlights(in text: String, prompt: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> HighlightMatches {
            texts.append(text); prompts.append(prompt); models.append(model); efforts.append(effort)
            let response = result
            do { try await Task.sleep(for: delay) }
            catch is CancellationError { if !ignoreCancellation { throw CancellationError() } }
            if let failure { throw failure }
            return response
        }
    }

    @MainActor static func interface(model: ComposerModel, window: NSWindow, synonymService: SynonymStub, highlightService: HighlightStub) {
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
                    window.sendEvent(event)
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
            await highlightInterface(model: model, window: window, service: highlightService) { require($0, $1) }
            await commandChecks { require($0, $1) }
            require(model.save(), "edited content persists")
            UserDefaults.standard.removePersistentDomain(forName: model.storage.directory.lastPathComponent)
            try? FileManager.default.removeItem(at: model.storage.directory)
            print("Passed \(checks) native UI checks: editing, drafts drawer, sizing, synonyms, highlights, settings, CLI lifecycle, focus, and persistence.")
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
        check(phrase?.query == "lend a hand" && phrase?.range == phraseRange && phrase?.sentence == phraseText,
              "phrase targeting trims only outer whitespace and preserves UTF-16 replacement offsets")
        check(phrase?.matches(text: phraseText, selection: phraseSelection) == true &&
              phrase?.matches(text: phraseText, selection: phraseRange) == true &&
              phrase?.matches(text: phraseText, selection: NSRange(location: phraseRange.location, length: 4)) == false,
              "phrase results stay valid for the same target and dismiss when selecting a different target")
        check(SynonymTarget.capture(text: "Lend a hand", selection: NSRange(location: 0, length: 11))?.replacement("assist") == "Assist" &&
              SynonymTarget.capture(text: "LEND A HAND", selection: NSRange(location: 0, length: 11))?.replacement("assist") == "ASSIST",
              "phrase replacement preserves initial and all-caps capitalization")
        let acrossSentences = "Before. Lend a hand.\nHelp out. After."
        let acrossRange = (acrossSentences as NSString).range(of: "a hand.\nHelp")
        check(SynonymTarget.capture(text: acrossSentences, selection: acrossRange)?.sentence == "Lend a hand.\nHelp out.",
              "context covers every selected sentence without adjacent sentences")
        check(SynonymTarget.capture(text: "  😀 123", selection: NSRange(location: 1, length: 0)) == nil,
              "synonyms reject whitespace and nonword targets")
        check(SynonymTarget.capture(text: "  😀 123", selection: NSRange(location: 0, length: 8)) == nil,
              "selected phrases must contain letters")
        for (text, expected) in [
            ("Earlier news. 😀 With each update add something nice. Keep it simple.", "😀 With each update add something nice."),
            ("First line.\n\nwith each update add something nice", "with each update add something nice"),
            ("We update the draft. Each update adds something nice.", "Each update adds something nice.")
        ] {
            let range = (text as NSString).range(of: "update", options: .backwards)
            let target = SynonymTarget.capture(text: text, selection: NSRange(location: NSMaxRange(range), length: 0))
            check(target?.query == "update" && target?.sentence == expected, "lookup extracts only the target sentence: \(expected)")
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
                #"{"type":"result","is_error":false,"structured_output":{"latin":["re-form"],"germanic":[]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["write-up"]}}"#,
                #"{"type":"result","is_error":false,"structured_output":{"latin":[],"germanic":["write\u2010up"]}}"#,
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
            model.deleteDraft(firstID)
            check(!model.draft.hasContent && model.drafts.count == 1, "delete current draft")
            let afterDelete = try store.read()
            check(afterDelete.drafts.allSatisfy { $0.id != firstID }, "deletion persists")
            try Data("bad json".utf8).write(to: store.file)
            let protected = ComposerModel(directory: directory, preferences: preferences)
            check(protected.error != nil && !protected.save(), "corrupt storage is protected")
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
            check(futureModel.error != nil && !futureModel.save(), "unsupported archive versions cannot be overwritten")
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
            check(protected.isReadOnly && protected.error != nil && defaults.data(forKey: PromptToolbarSettings.preferenceKey) == invalidData,
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

    @MainActor private static func highlightInterface(model: ComposerModel, window: NSWindow, service: HighlightStub,
                                                      check: (Bool, String) -> Void) async {
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        func firstIconBounds() -> NSRect? {
            guard let view = window.contentView else { return nil }
            let rect = view.convert(NSRect(x: 60, y: 4, width: 34, height: 50), from: nil)
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
        let first = NSPoint(x: 77, y: 29)
        let second = NSPoint(x: 111, y: 29)
        await click(first)
        check(model.highlights.state == .ready && model.highlights.activeButtonID == buttons[0].id && model.highlights.ranges.count == 3,
              "clicking a configured button highlights the post and stays pressed")
        guard let restingIcon = firstIconBounds() else { check(false, "active toolbar icon is visible"); return }
        check(service.texts == [source] && service.prompts == [buttons[0].prompt] &&
              service.models == [model.synonymModel] && service.efforts == [model.synonymEffort],
              "highlight request uses the whole post, configured prompt, and current model/effort")
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
        check(shortcut(",", code: 43, in: window), "Command-comma opens Settings")
        await settle()
        guard let settings = NSApp.windows.first(where: { $0.title == "Settings" && $0.isVisible }) else {
            check(false, "Settings window is visible"); return
        }
        check(model.highlights.ranges.count == 3 && window.attachedSheet == nil, "opening Settings preserves pressed highlights")
        await click(NSPoint(x: 28, y: 24), in: settings)
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
        await click(first)
        service.result = HighlightMatches(matches: [.init(text: "not in this post", occurrence: 1)])
        await click(first)
        check(model.highlights.state == .idle && model.error != nil, "invalid intervals are reported and never partially applied")
        model.error = nil
        await settle()
        service.result = HighlightMatches(matches: [.init(text: "clear", occurrence: 1)])
        await click(first)
        model.newDraft()
        await settle()
        check(model.highlights.state == .idle, "switching drafts clears document-specific highlights")
        highlightStyleRenderingChecks(check: check)
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
        check(editor.performKeyEquivalent(with: key(" ", code: 49)), "Control-Space is handled by the native editor")
        check(model.synonyms.state == .loading, "synonym lookup immediately shows loading")
        await settle()
        let ready = SynonymController.State.ready(SynonymStub.lists)
        check(model.synonyms.state == ready, "synonyms display both groups")
        check(service.targets.last == "Help" && service.sentences.last == "😀 Help, help.", "the word and its sentence are sent to Claude")
        check(window.frame == frame, "synonym rows preserve the composer frame")

        window.makeFirstResponder(nil)
        check(model.synonyms.state == ready, "synonyms survive the editor losing focus")
        window.makeFirstResponder(editor)
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

        let previousWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        await click(at: NSPoint(x: 110, y: 82))
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
        await click(at: NSPoint(x: 110, y: 82))
        guard let reopenedPicker = NSApp.windows.first(where: { $0.isVisible && !visibleWindows.contains($0.windowNumber) }) else {
            check(false, "model link reopens after Escape")
            return
        }
        await click(at: NSPoint(x: 30, y: 82))
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
        check(service.targets.last == "update" && service.sentences.last == "With each update add something nice.",
              "native lookups send the selected word's sentence without adjacent sentences")

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
        check(model.synonyms.state == ready && service.targets.last == "lend a hand" &&
              service.sentences.last == "😀 Please lend a hand with this, then lend a hand.",
              "selected phrases request single-word alternatives with sentence context")
        await click(at: NSPoint(x: 100, y: 40))
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
                    if grep -q '"rule"' "$CLAUDE_CONFIG_DIR/request.json"; then
                        printf '%s' '{"type":"result","is_error":false,"structured_output":{"matches":[{"text":"clear","occurrence":2}]}}'
                    else
                        printf '%s' '{"type":"result","is_error":false,"structured_output":{"latin":["assist"],"germanic":["back"]}}'
                    fi;;
                *) exit 5;;
            esac
            """
            try Data(source.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let cli = ClaudeCLI(configurationDirectory: fixture.appendingPathComponent("profile"), executable: script)
            check(try await !cli.isAuthenticated(), "signed-out CLI status requests login")
            try await cli.signIn()
            check(try await cli.isAuthenticated(), "CLI-owned sign-in is checked before lookup")
            let sentence = #"Please "lend a hand" with 😀 updates."#
            for (model, effort) in [(ClaudeModel.fable, ClaudeEffort.low), (.opus, .high), (.sonnet, .xhigh), (.haiku, .max), (.fable, .medium)] {
                check(try await cli.synonyms(for: "lend a hand", in: sentence, model: model, effort: effort) == SynonymLists(latin: ["assist"], germanic: ["back"]),
                      "CLI service reads structured results end to end")
                let arguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8).components(separatedBy: "\n")
                let options = Array(zip(arguments, arguments.dropFirst()))
                check(options.contains { $0.0 == "--model" && $0.1 == model.rawValue } &&
                      options.contains { $0.0 == "--effort" && $0.1 == effort.rawValue }, "CLI requests \(model.title) with \(effort.title) effort")
            }
            let request = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(request == ["target": "lend a hand", "sentence": sentence], "CLI sends the whole phrase and its context as safely encoded JSON")
            let highlightedText = "😀 clear and clear."
            let highlightPrompt = #"Highlight the second "clear"."#
            let highlights = try await cli.highlights(in: highlightedText, prompt: highlightPrompt, model: .opus, effort: .xhigh)
            check(try highlights.ranges(in: highlightedText) == [NSRange(location: 13, length: 5)], "CLI highlight response resolves exact Unicode-aware intervals")
            let highlightRequest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.appendingPathComponent("profile/request.json")))
            check(highlightRequest == ["rule": highlightPrompt, "text": highlightedText], "CLI encodes custom prompts and full text without shell interpolation")
            let highlightArguments = try String(contentsOf: fixture.appendingPathComponent("profile/arguments.txt"), encoding: .utf8).components(separatedBy: "\n")
            let highlightOptions = Array(zip(highlightArguments, highlightArguments.dropFirst()))
            check(highlightOptions.contains { $0 == "--model" && $1 == ClaudeModel.opus.rawValue } &&
                  highlightOptions.contains { $0 == "--effort" && $1 == ClaudeEffort.xhigh.rawValue } &&
                  highlightOptions.contains { $0 == "--json-schema" && $1 == ClaudeCLI.highlightSchema } &&
                  highlightOptions.contains { $0 == "--tools" && $1.isEmpty }, "highlight CLI uses current model, effort, interval schema, and no tools")
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
