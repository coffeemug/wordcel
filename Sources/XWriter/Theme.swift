import AppKit
import SwiftUI

// The latest SDK's @State macro needs an Xcode-only plugin. Composing the
// public property wrapper keeps this project buildable with Command Line Tools.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>
    init(wrappedValue: Value) { state = State(wrappedValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}

enum Theme {
    static let blue = Color(red: 29/255, green: 155/255, blue: 240/255)
    static let blueNS = NSColor(srgbRed: 29/255, green: 155/255, blue: 240/255, alpha: 1)
    static let backgroundNS = adaptive(0xffffff, 0x000000)
    static let foregroundNS = adaptive(0x0f1419, 0xe7e9ea)
    static let secondaryNS = adaptive(0x536471, 0x71767b)
    static let borderNS = adaptive(0xeff3f4, 0x2f3336)
    static let background = Color(nsColor: backgroundNS)
    static let foreground = Color(nsColor: foregroundNS)
    static let secondary = Color(nsColor: secondaryNS)
    static let border = Color(nsColor: borderNS)
    static let hover = Color(nsColor: adaptive(0xeff3f4, 0x181818))
    static let toolbarIconNS = adaptive(0x8799a9, 0x9ba9b5)
    static let toolbarIcon = Color(nsColor: toolbarIconNS)
    static let toolbarIconHover = Color(nsColor: adaptive(0x65737f, 0xb7c4ce))
    static let toolbarHover = Color(nsColor: adaptive(0xe6e6e6, 0x262b30))
    static let toolbarActive = Color(red: 74/255, green: 153/255, blue: 233/255)
    static let danger = Color(red: 244/255, green: 33/255, blue: 46/255)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

struct RoundButtonStyle: ButtonStyle {
    var blue = false
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, blue: blue)
    }
    private struct HoverBody: View {
        let configuration: Configuration
        let blue: Bool
        @ViewState<Bool> private var hovering = false
        var body: some View {
            configuration.label
                .frame(width: 34, height: 34)
                .background((blue ? Theme.blue.opacity(0.1) : Theme.hover)
                    .opacity(hovering || configuration.isPressed ? 1 : 0), in: Circle())
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 19).frame(height: 36)
            .background(Theme.foreground.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45), in: Capsule())
            .contentShape(Capsule())
    }
}
