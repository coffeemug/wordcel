import AppKit
import SwiftUI

enum HighlightColor: Codable, Equatable {
    case iconGray
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)

    static let underlineBlue = HighlightColor.rgba(red: 46/255, green: 103/255, blue: 211/255, alpha: 1)
    static let yellow = HighlightColor.rgba(red: 1, green: 0.8, blue: 0, alpha: 0.3)

    var nsColor: NSColor {
        switch self {
        case .iconGray: return Theme.toolbarIconNS
        case .rgba(let red, let green, let blue, let alpha):
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    var isValid: Bool {
        switch self {
        case .iconGray: return true
        case .rgba(let red, let green, let blue, let alpha):
            return [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }
    }

    init(_ color: Color) throws {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
            throw ColorError.unsupported
        }
        self = .rgba(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        guard isValid else { throw ColorError.unsupported }
    }

    private enum ColorError: LocalizedError {
        case unsupported
        var errorDescription: String? { "This color couldn't be converted to RGB. Please choose another color." }
    }
}

enum HighlightUnderline: String, Codable, CaseIterable, Identifiable {
    case none, solid, dotted, wiggly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct HighlightStyle: Codable, Equatable {
    var fontColor: HighlightColor?
    var strikethrough = false
    var underline = HighlightUnderline.none
    var underlineColor = HighlightColor.underlineBlue
    var backgroundColor: HighlightColor? = .yellow

    static let latin = HighlightStyle(underline: .solid, backgroundColor: nil)
    static let cuts = HighlightStyle(fontColor: .iconGray, strikethrough: true, backgroundColor: nil)
    static let marker = NSAttributedString.Key("XWriterHighlight")
    static let dottedUnderline = NSAttributedString.Key("XWriterDottedUnderline")
    static let wigglyUnderline = NSAttributedString.Key("XWriterWigglyUnderline")
    static let attributeKeys: [NSAttributedString.Key] = [
        .foregroundColor, .backgroundColor, .strikethroughStyle, .strikethroughColor,
        .underlineStyle, .underlineColor, marker, dottedUnderline, wigglyUnderline
    ]

    var isValid: Bool { (fontColor?.isValid ?? true) && underlineColor.isValid && (backgroundColor?.isValid ?? true) }

    var attributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [Self.marker: true]
        if let fontColor { result[.foregroundColor] = fontColor.nsColor }
        if let backgroundColor { result[.backgroundColor] = backgroundColor.nsColor }
        if strikethrough {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            if let fontColor { result[.strikethroughColor] = fontColor.nsColor }
        }
        if underline != .none {
            result[.underlineStyle] = underline == .dotted ? NSUnderlineStyle.single.union(.patternDot).rawValue : NSUnderlineStyle.single.rawValue
            result[.underlineColor] = underlineColor.nsColor
            if underline == .dotted { result[Self.dottedUnderline] = true }
            if underline == .wiggly { result[Self.wigglyUnderline] = true }
        }
        return result
    }
}

final class HighlightLayoutManager: NSLayoutManager {
    override func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType: NSUnderlineStyle, baselineOffset: CGFloat,
                                lineFragmentRect: NSRect, lineFragmentGlyphRange: NSRange, containerOrigin: NSPoint) {
        let character = characterIndexForGlyph(at: glyphRange.location)
        let dotted = temporaryAttribute(HighlightStyle.dottedUnderline, atCharacterIndex: character, effectiveRange: nil) as? Bool == true
        guard dotted || temporaryAttribute(HighlightStyle.wigglyUnderline, atCharacterIndex: character, effectiveRange: nil) as? Bool == true,
              let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil) else {
            super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineType, baselineOffset: baselineOffset,
                                lineFragmentRect: lineFragmentRect, lineFragmentGlyphRange: lineFragmentGlyphRange, containerOrigin: containerOrigin)
            return
        }
        let font = textStorage?.attribute(.font, at: character, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 20)
        let color = temporaryAttribute(.underlineColor, atCharacterIndex: character, effectiveRange: nil) as? NSColor ?? Theme.foregroundNS
        let y = containerOrigin.y + lineFragmentRect.maxY - baselineOffset - font.underlinePosition
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        color.setStroke()
        color.setFill()
        enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            var x = containerOrigin.x + rect.minX
            let end = containerOrigin.x + rect.maxX
            if dotted {
                let diameter = max(1.5, font.underlineThickness * 1.5)
                while x + diameter <= end {
                    NSBezierPath(ovalIn: NSRect(x: x, y: y - diameter / 2, width: diameter, height: diameter)).fill()
                    x += diameter * 2
                }
                return
            }
            let path = NSBezierPath()
            path.lineWidth = max(1, font.underlineThickness)
            path.lineCapStyle = .round
            var direction: CGFloat = 1
            path.move(to: NSPoint(x: x, y: y))
            while x < end {
                let width = min(3, end - x)
                path.curve(to: NSPoint(x: x + width, y: y),
                           controlPoint1: NSPoint(x: x + width / 3, y: y + direction * 1.5),
                           controlPoint2: NSPoint(x: x + 2 * width / 3, y: y + direction * 1.5))
                x += width
                direction = -direction
            }
            path.stroke()
        }
    }
}

struct HighlightStyleEditor: View {
    @Binding var style: HighlightStyle
    let onError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlight style").font(.system(size: 14, weight: .semibold))
            optionalColor("Font color", value: $style.fontColor, defaultColor: .iconGray)
            Toggle("Strikethrough", isOn: $style.strikethrough)
            HStack {
                Picker("Underline", selection: $style.underline) {
                    ForEach(HighlightUnderline.allCases) { Text($0.title).tag($0) }
                }.frame(maxWidth: 260)
                Spacer()
                colorPicker("Underline color", value: $style.underlineColor).disabled(style.underline == .none)
            }
            optionalColor("Background color", value: $style.backgroundColor, defaultColor: .yellow)
            HighlightStylePreview(style: style)
                .frame(height: 40).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .accessibilityLabel("Highlight style preview")
        }.font(.system(size: 13))
    }

    private func optionalColor(_ label: String, value: Binding<HighlightColor?>, defaultColor: HighlightColor) -> some View {
        HStack {
            Toggle(label, isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? defaultColor : nil }))
            Spacer()
            colorPicker(label, value: Binding(get: { value.wrappedValue ?? defaultColor }, set: { value.wrappedValue = $0 }))
                .disabled(value.wrappedValue == nil)
        }
    }

    private func colorPicker(_ label: String, value: Binding<HighlightColor>) -> some View {
        ColorPicker(label, selection: Binding(get: { Color(nsColor: value.wrappedValue.nsColor) }, set: { color in
            do { value.wrappedValue = try HighlightColor(color) }
            catch { onError(error.localizedDescription) }
        }), supportsOpacity: true).labelsHidden().accessibilityLabel(label)
    }
}

private struct HighlightStylePreview: NSViewRepresentable {
    let style: HighlightStyle

    func makeNSView(context: Context) -> ComposerTextView {
        let view = ComposerTextView(frame: .zero)
        view.textContainer?.replaceLayoutManager(HighlightLayoutManager())
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = .systemFont(ofSize: 14)
        view.string = "Preview of highlighted text."
        view.highlightRanges = [(view.string as NSString).range(of: "highlighted text")]
        return view
    }

    func updateNSView(_ view: ComposerTextView, context: Context) {
        view.textColor = Theme.foregroundNS
        view.highlightStyle = style
        view.refreshHighlights()
    }
}
