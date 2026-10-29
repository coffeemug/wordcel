import AppKit
import SwiftUI

@main
enum XWriterApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfCheck.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > index + 1 {
            makeIcon(at: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func makeIcon(at path: String) {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(srgbRed: 0.06, green: 0.08, blue: 0.1, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 1000, height: 1000), xRadius: 220, yRadius: 220).fill()
        NSColor.white.setStroke()
        let bubble = NSBezierPath(roundedRect: NSRect(x: 225, y: 300, width: 574, height: 464), xRadius: 105, yRadius: 105)
        bubble.lineWidth = 34
        bubble.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 260, y: 340)); tail.line(to: NSPoint(x: 260, y: 205))
        tail.line(to: NSPoint(x: 406, y: 300))
        tail.lineWidth = 34; tail.lineJoinStyle = .round; tail.lineCapStyle = .round
        NSColor(srgbRed: 0.06, green: 0.08, blue: 0.1, alpha: 1).setFill(); tail.fill(); tail.stroke()
        for (y, length) in [(610.0, 294.0), (500.0, 224.0), (390.0, 144.0)] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 365, y: y)); line.line(to: NSPoint(x: 365 + length, y: y))
            line.lineWidth = 32; line.lineCapStyle = .round
            (y == 390 ? Theme.blueNS : NSColor.white).setStroke(); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        do { try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }
        catch { fputs("Icon generation failed: \(error)\n", stderr); exit(1) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var settingsWindow: NSWindow?
    private var model: ComposerModel!
    private var snapshotPath: String?
    private var contentHeight = ComposerWindowSizing.minimumHeight
    private var resizeWork: DispatchWorkItem?
    private var composerWidthBeforeDrawer: CGFloat?
    private var frameAutosaveNameBeforeDrawer: NSWindow.FrameAutosaveName?
    private var isResizingDraftsDrawer = false
    private var inputMonitor: Any?
    private var menuActionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            snapshotPath = CommandLine.arguments[index + 1]
        }
        let isTesting = snapshotPath != nil || CommandLine.arguments.contains("--ui-test")
        let isolatedDirectory = isTesting ? FileManager.default.temporaryDirectory.appendingPathComponent("XWriter-preview-\(UUID())") : nil
        let previewSynonyms = isTesting ? SelfCheck.SynonymStub() : nil
        let previewHighlights = isTesting ? SelfCheck.HighlightStub() : nil
        if isTesting && CommandLine.arguments.contains("--loading") {
            previewSynonyms?.delay = .seconds(10)
            previewHighlights?.delay = .seconds(10)
        }
        let preferences = isolatedDirectory.map { SelfCheck.preferences(for: $0) } ?? .standard
        model = ComposerModel(directory: isolatedDirectory, synonymService: previewSynonyms,
                              highlightService: previewHighlights, preferences: preferences)
        model.onShowSettings = { [weak self] in self?.showSettings() }
        if CommandLine.arguments.contains("--demo") {
            model.draft.posts[0].text = "A little less scrolling. A little more writing.\n\nMade for the moments when you have something to say. ✨"
        }
        if isTesting && CommandLine.arguments.contains("--long-demo") {
            model.draft.posts[0].text = String(repeating: "A native composer that leaves room for your thoughts.\n\n", count: 18)
        }
        if isTesting, let index = CommandLine.arguments.firstIndex(of: "--demo-count"),
           CommandLine.arguments.count > index + 1, let count = Int(CommandLine.arguments[index + 1]),
           (0...25_100).contains(count) {
            model.draft.posts[0].text = String(repeating: "a", count: count)
        }
        if isTesting && CommandLine.arguments.contains("--synonyms") {
            model.draft.posts[0].text = "A little help goes a long way."
        }
        if isTesting && CommandLine.arguments.contains("--highlights") {
            model.draft.posts[0].text = "😀 A precise line, a clear point, and precise words."
            if CommandLine.arguments.contains("--wiggly") { model.toolbarSettings.buttons[0].style.underline = .wiggly }
            if CommandLine.arguments.contains("--dotted") { model.toolbarSettings.buttons[0].style.underline = .dotted }
        }
        if isTesting && CommandLine.arguments.contains("--message") {
            model.notify("Claude returned invalid highlighting intervals. Please try again.")
        }
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        else { model.applyAppearance() }
        configureMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: model.composerWidth, height: ComposerWindowSizing.minimumHeight),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "XWriter"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.backgroundNS
        window.minSize = NSSize(width: ComposerWindowSizing.minimumWidth, height: 300 + ComposerWindowSizing.echoAreaHeight)
        window.delegate = self
        model.onContentHeightChange = { [weak self] height in self?.scheduleResize(to: height) }
        model.onDraftsVisibilityChange = { [weak self] visible in self?.resizeDraftsDrawer(visible) }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        let hostingView = NSHostingView(rootView: ComposeView(model: model))
        // Window sizing is managed here, independently of the drawer's intermediate SwiftUI layout.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        if !isTesting { window.setFrameAutosaveName("XWriterComposer") }
        window.makeKeyAndOrderFront(nil)
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .beginGesture]) { [weak self] event in
            guard let self else { return event }
            let hadMessage = self.model.echo.message != nil
            self.model.echo.clear()
            guard event.type == .keyDown, event.window === self.window else { return event }
            // AppKit otherwise matches the retired thread shortcut to Command-Return's publishing action.
            if event.keyCode == 36 && event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .shift] {
                return nil
            }
            guard event.keyCode == 53, hadMessage || self.model.synonyms.state != .idle else { return event }
            if self.model.synonyms.state != .idle { self.model.synonyms.dismiss() }
            return nil
        }
        menuActionObserver = NotificationCenter.default.addObserver(forName: NSMenu.willSendActionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.echo.clear() }
        }
        NSApp.activate(ignoringOtherApps: true)
        if isTesting && CommandLine.arguments.contains("--drafts") { model.toggleDrafts() }
        if isTesting && CommandLine.arguments.contains("--synonyms") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let editor = self.model.activeEditor else { return }
                editor.setSelectedRange(NSRange(location: 11, length: 0))
                self.model.synonyms.lookup(in: editor, model: self.model.synonymModel, effort: self.model.synonymEffort)
            }
        }
        if isTesting && CommandLine.arguments.contains("--highlights") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                let index = CommandLine.arguments.contains("--cuts") ? 1 : 0
                guard self.model.toolbarSettings.buttons.indices.contains(index) else { return }
                let button = self.model.toolbarSettings.buttons[index]
                self.model.toggleHighlights(button)
            }
        }
        if isTesting && CommandLine.arguments.contains("--settings") { showSettings() }
        if snapshotPath != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.captureSnapshot() }
        }
        if CommandLine.arguments.contains("--ui-test"), let previewSynonyms, let previewHighlights {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SelfCheck.interface(model: self.model, window: self.window, synonymService: previewSynonyms, highlightService: previewHighlights)
            }
        }
    }

    private func scheduleResize(to height: CGFloat) {
        guard height > 0 else { return }
        contentHeight = height
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fitComposer() }
        resizeWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func fitComposer() {
        guard let window, !window.inLiveResize, !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main else { return }
        let chrome = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
        let frame = ComposerWindowSizing.frame(current: window.frame, contentHeight: contentHeight + chrome, screen: screen.visibleFrame)
        guard abs(frame.height - window.frame.height) > 1 || abs(frame.minY - window.frame.minY) > 1 else { return }
        window.setFrame(frame, display: true)
        model.activeEditor?.revealSelectionAfterLayout()
    }

    private func resizeDraftsDrawer(_ visible: Bool) {
        guard let window else { return }
        isResizingDraftsDrawer = true
        defer {
            isResizingDraftsDrawer = false
            updateComposerWidth()
        }
        if visible {
            composerWidthBeforeDrawer = window.frame.width
            // Don't restore the expanded drawer width as the composer width on the next launch.
            let name = window.frameAutosaveName
            if !name.isEmpty {
                window.saveFrame(usingName: name)
                window.setFrameAutosaveName("")
                frameAutosaveNameBeforeDrawer = name
            }
        }
        let composerWidth = composerWidthBeforeDrawer ?? window.frame.width
        window.minSize.width = ComposerWindowSizing.minimumWidth + (visible ? ComposerWindowSizing.drawerWidth : 0)
        if !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main {
            let frame = ComposerWindowSizing.frame(current: window.frame, composerWidth: composerWidth,
                                                   showingDrafts: visible, screen: screen.visibleFrame)
            window.setFrame(frame, display: true)
        }
        if !visible {
            composerWidthBeforeDrawer = nil
            if let name = frameAutosaveNameBeforeDrawer {
                // Reattaching autosave restores its saved frame, so save the current position first.
                window.saveFrame(usingName: name)
                window.setFrameAutosaveName(name)
                frameAutosaveNameBeforeDrawer = nil
            }
            if let editor = model.activeEditor { window.makeFirstResponder(editor) }
        }
    }

    private func updateComposerWidth() {
        let width = max(ComposerWindowSizing.minimumWidth, window.contentRect(forFrameRect: window.frame).width
                        - (model.showDrafts ? ComposerWindowSizing.drawerWidth : 0))
        if abs(model.composerWidth - width) > 0.5 { model.composerWidth = width }
    }

    func windowDidResize(_ notification: Notification) {
        if !isResizingDraftsDrawer { updateComposerWidth() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if model.showDrafts { composerWidthBeforeDrawer = window.frame.width - ComposerWindowSizing.drawerWidth }
        scheduleResize(to: contentHeight)
    }
    func windowDidChangeScreen(_ notification: Notification) { scheduleResize(to: contentHeight) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.synonyms.dismiss(); model.highlights.dismiss(); return model.save() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.synonyms.dismiss()
        model?.highlights.dismiss()
        guard model != nil, !model.save() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Your latest changes couldn't be saved."
        alert.informativeText = "Keep editing to copy your writing, or quit without saving these changes. Your existing draft file will stay untouched."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let menuActionObserver { NotificationCenter.default.removeObserver(menuActionObserver) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private func configureMenu() {
        let menu = NSMenu()
        let app = submenu("XWriter", in: menu)
        item("About XWriter", action: #selector(about), in: app)
        app.addItem(.separator())
        item("Settings…", action: #selector(showSettings), key: ",", in: app)
        app.addItem(.separator())
        item("Hide XWriter", action: #selector(NSApplication.hide(_:)), key: "h", in: app, target: NSApp)
        item("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], in: app, target: NSApp)
        item("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), in: app, target: NSApp)
        app.addItem(.separator())
        item("Quit XWriter", action: #selector(NSApplication.terminate(_:)), key: "q", in: app, target: NSApp)

        let file = submenu("File", in: menu)
        item("New Post", action: #selector(newPost), key: "n", in: file)
        item("Save Draft", action: #selector(saveDraft), key: "s", in: file)
        item("Toggle Drafts", action: #selector(drafts), key: "d", in: file)
        file.addItem(.separator())
        item("Continue on X…", action: #selector(post), key: "\r", in: file)
        file.addItem(.separator())
        item("Close", action: #selector(close), key: "w", in: file)

        let edit = submenu("Edit", in: menu)
        item("Undo", action: Selector(("undo:")), key: "z", in: edit, responder: true)
        item("Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], in: edit, responder: true)
        edit.addItem(.separator())
        item("Cut", action: #selector(NSText.cut(_:)), key: "x", in: edit, responder: true)
        item("Copy", action: #selector(NSText.copy(_:)), key: "c", in: edit, responder: true)
        item("Paste", action: #selector(NSText.paste(_:)), key: "v", in: edit, responder: true)
        item("Select All", action: #selector(NSText.selectAll(_:)), key: "a", in: edit, responder: true)
        edit.addItem(.separator())
        item("Find Synonyms", action: #selector(findSynonyms), key: " ", modifiers: .control, in: edit)

        let view = submenu("View", in: menu)
        item("Light", action: #selector(light), in: view)
        item("Dark", action: #selector(dark), in: view)
        item("Use System Appearance", action: #selector(system), in: view)
        item("Toggle Appearance", action: #selector(toggleAppearance), key: "d", modifiers: [.command, .shift], in: view)
        view.addItem(.separator())
        item("Choose Profile Photo…", action: #selector(profile), in: view)

        let windows = submenu("Window", in: menu)
        item("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", in: windows, responder: true)
        item("Zoom", action: #selector(NSWindow.performZoom(_:)), in: windows, responder: true)
        item("Show Composer", action: #selector(show), key: "1", in: windows)
        NSApp.windowsMenu = windows
        NSApp.mainMenu = menu
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        entry.submenu = menu
        parent.addItem(entry)
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                      in menu: NSMenu, target: AnyObject? = nil, responder: Bool = false) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = responder ? nil : (target ?? self)
        menu.addItem(item)
    }

    @objc private func newPost() { model.newDraft(); show() }
    @objc private func saveDraft() { if model.save() { model.notify("Draft saved") } }
    @objc private func drafts() { model.toggleDrafts(); show() }
    @objc private func findSynonyms() {
        guard let editor = window.firstResponder as? ComposerTextView else {
            model.notify("Place the cursor in a post to find synonyms.")
            return
        }
        model.synonyms.lookup(in: editor, model: model.synonymModel, effort: model.synonymEffort)
    }
    @objc private func post() { model.prepareHandoff() }
    @objc private func close() { NSApp.keyWindow?.performClose(nil) }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            settings.title = "Settings"
            settings.isReleasedWhenClosed = false
            settings.contentMinSize = NSSize(width: 660, height: 450)
            let hosting = NSHostingView(rootView: ToolbarSettingsView(settings: model.toolbarSettings))
            hosting.sizingOptions = []
            settings.contentView = hosting
            settings.center()
            settingsWindow = settings
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func light() { model.appearance = "light" }
    @objc private func dark() { model.appearance = "dark" }
    @objc private func system() { model.appearance = "system" }
    @objc private func toggleAppearance() { model.appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "light" : "dark" }
    @objc private func profile() { model.chooseAvatar() }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "XWriter", .applicationVersion: "1.0",
            .credits: NSAttributedString(string: "A quiet place to write.\nNative macOS composer inspired by X.\nDrafts are stored on this Mac; publishing happens on X.")
        ])
    }

    private func captureSnapshot() {
        let target = CommandLine.arguments.contains("--settings") ? settingsWindow : window
        guard let path = snapshotPath, let view = target?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("Snapshot failed: the preview window is not ready.\n", stderr)
            exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            print("Snapshot saved: \(path) (\(bitmap.pixelsWide) × \(bitmap.pixelsHigh))")
            UserDefaults.standard.removePersistentDomain(forName: model.storage.directory.lastPathComponent)
            try? FileManager.default.removeItem(at: model.storage.directory)
            exit(0)
        } catch { fputs("Snapshot failed: \(error)\n", stderr); exit(1) }
    }
}
