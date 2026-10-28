import AppKit
import SwiftUI

struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let postID: UUID
    @ObservedObject var model: ComposerModel

    func makeNSView(context: Context) -> ComposerTextView {
        let view = ComposerTextView(frame: .zero)
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
        view.onImages = { [weak model] urls in model?.addImages(urls, to: postID) }
        view.onImagePaste = { [weak model] image in model?.pasteImage(image, to: postID) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? ComposerTextView else { return }
            parent.text = view.string
            style(view)
            measure(view)
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
    var onImages: (([URL]) -> Void)?
    var onImagePaste: ((NSImage) -> Void)?
    var onResize: (() -> Void)?
    var didRequestFocus = false

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
        if event.modifierFlags.contains(.command) && event.keyCode == 36 { onSubmit?(); return }
        super.keyDown(with: event)
        revealSelectionAfterLayout()
    }

    func revealSelectionAfterLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, window?.firstResponder === self else { return }
            window?.contentView?.layoutSubtreeIfNeeded()
            scrollRangeToVisible(selectedRange())
        }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onImages?(urls)
        } else if pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard) {
            onImagePaste?(image)
        } else { super.pasteAsPlainText(sender) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onImages?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }
}
