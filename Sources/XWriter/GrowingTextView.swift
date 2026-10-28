import AppKit
import SwiftUI

struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let postID: UUID
    @ObservedObject var model: ComposerModel

    func makeNSView(context: Context) -> ComposerTextView {
        let view = ComposerTextView(frame: .zero)
        view.textContainer?.replaceLayoutManager(HighlightLayoutManager())
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 0, height: 5)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.font = .systemFont(ofSize: 20)
        view.textColor = Theme.foregroundNS
        view.insertionPointColor = Theme.blueNS
        view.setAccessibilityLabel("Post text")
        view.setAccessibilityIdentifier("post-editor-\(postID)")
        view.string = text
        context.coordinator.editor = view
        view.textStorage?.delegate = context.coordinator
        configure(view, coordinator: context.coordinator)
        view.onResize = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.measure(view)
        }
        return view
    }

    func updateNSView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        configure(view, coordinator: context.coordinator)
        if view.string != text && !view.hasMarkedText() {
            view.string = text
            view.undoManager?.removeAllActions()
        }
        context.coordinator.style(view)
        view.refreshHighlights()
        context.coordinator.measure(view)
        if model.activePostID == postID && (!view.didRequestFocus || model.activeEditor !== view) {
            view.didRequestFocus = true
            DispatchQueue.main.async { [weak view] in view?.onFocusRequest?() }
        } else if model.activePostID != postID { view.didRequestFocus = false }
    }

    private func configure(_ view: ComposerTextView, coordinator: Coordinator) {
        view.onFocusRequest = { [weak model, weak view] in
            guard let model, let view, model.activePostID == postID else { return }
            view.window?.makeFirstResponder(view)
        }
        view.onFocus = { [weak model, weak view] in
            model?.activePostID = postID
            model?.activeEditor = view
        }
        view.onSubmit = { [weak model] in model?.prepareHandoff() }
        view.onSynonymLookup = { [weak model, weak view] in
            guard let model, let view else { return }
            model.synonyms.lookup(in: view, model: model.synonymModel, effort: model.synonymEffort)
        }
        view.onSelectionChange = { [weak model, weak view] in
            guard let view else { return }
            model?.synonyms.invalidateIfChanged(in: view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: GrowingTextView
        weak var editor: ComposerTextView?
        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? ComposerTextView else { return }
            parent.text = view.string
            style(view)
            view.refreshHighlights()
            measure(view)
        }

        func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            MainActor.assumeIsolated {
                guard editedMask.contains(.editedCharacters), let editor else { return }
                let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
                parent.model.highlights.didEdit(HighlightEdit(range: oldRange, replacementLength: editedRange.length), in: editor)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? ComposerTextView)?.onSelectionChange?()
        }

        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer, view.bounds.width > 0 else { return }
            layout.ensureLayout(for: container)
            let height = max(124, ceil(layout.usedRect(for: container).height) + 12)
            if abs(parent.height - height) > 1 {
                DispatchQueue.main.async { [weak self, weak view] in
                    self?.parent.height = height
                    (view as? ComposerTextView)?.revealSelectionAfterLayout()
                }
            }
        }

        func style(_ view: NSTextView) {
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20), .foregroundColor: Theme.foregroundNS, .paragraphStyle: paragraph
            ]
            storage.beginEditing()
            storage.setAttributes(attributes, range: range)
            if let expression = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])[@#][\\p{L}\\p{N}_]+|https?://[^\\s]+") {
                for match in expression.matches(in: view.string, range: range) {
                    storage.addAttribute(.foregroundColor, value: Theme.blueNS, range: match.range)
                }
            }
            storage.endEditing()
            view.typingAttributes = attributes
        }
    }
}

final class ComposerTextView: NSTextView {
    var onFocusRequest: (() -> Void)?
    var onFocus: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onSynonymLookup: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onResize: (() -> Void)?
    var didRequestFocus = false
    var highlightRanges: [NSRange] = []
    var highlightStyle = HighlightStyle()

    func refreshHighlights() {
        guard let layoutManager else { return }
        let length = (string as NSString).length
        var position = 0
        while position < length {
            var range = NSRange()
            let attributes = layoutManager.temporaryAttributes(atCharacterIndex: position, effectiveRange: &range)
            if attributes[HighlightStyle.marker] != nil {
                for key in HighlightStyle.attributeKeys { layoutManager.removeTemporaryAttribute(key, forCharacterRange: range) }
            }
            position = NSMaxRange(range)
        }
        for range in highlightRanges {
            layoutManager.addTemporaryAttributes(highlightStyle.attributes, forCharacterRange: range)
        }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI can request focus before a restored editor is attached to the window.
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onFocusRequest?() } }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { DispatchQueue.main.async { [weak self] in self?.onFocus?() } }
        return result
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override func keyDown(with event: NSEvent) {
        if handleSynonymShortcut(event) { return }
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command && event.keyCode == 36 {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
        revealSelectionAfterLayout()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleSynonymShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleSynonymShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.control, .command, .option, .shift]) == .control,
              event.keyCode == 49 else { return false }
        onSynonymLookup?()
        return true
    }

    func revealSelectionAfterLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, window?.firstResponder === self else { return }
            window?.contentView?.layoutSubtreeIfNeeded()
            scrollRangeToVisible(selectedRange())
        }
    }

    override func paste(_ sender: Any?) {
        super.pasteAsPlainText(sender)
    }
}
