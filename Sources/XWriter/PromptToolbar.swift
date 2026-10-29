import SwiftUI

enum PromptIcon: String, Codable, CaseIterable, Identifiable {
    case leaf, laurel, scissors, book, pencil, highlighter, eye, eyeglasses, brain, heart, ear
    case tree, flower = "camera.macro", sun = "sun.max", moon, cloud, bolt, flame, drop
    case ant, ladybug, bird, fish, hare, tortoise
    case flag, tag, target, scope, link, repetition = "repeat", paragraph
    case search = "text.magnifyingglass", list = "list.bullet", filter = "line.3.horizontal.decrease"
    case speech = "bubble.left", quote = "quote.bubble", question = "questionmark.circle"
    case warning = "exclamationmark.triangle", check = "checkmark.circle", clock

    var id: String { rawValue }
    var symbolNames: [String] {
        self == .laurel ? ["laurel.leading", "laurel.trailing"] : [rawValue]
    }
    var image: some View {
        HStack(spacing: 0) {
            ForEach(symbolNames, id: \.self) { Image(systemName: $0) }
        }
    }
    var title: String {
        switch self {
        case .flower: return "Flower"
        case .sun: return "Sun"
        case .repetition: return "Repetition"
        case .search: return "Search"
        case .list: return "List"
        case .filter: return "Filter"
        case .speech: return "Speech"
        case .quote: return "Quote"
        case .question: return "Question"
        case .warning: return "Warning"
        case .check: return "Check"
        default: return rawValue.capitalized
        }
    }
}

struct PromptButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "New button"
    var icon = PromptIcon.eye
    var prompt = ""
    var style = HighlightStyle()
    var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var examples: [PromptButton] {
        [
            PromptButton(name: "Latin words", icon: .laurel,
                         prompt: "Highlight individual English words with Latin-derived roots, including borrowings through French. Include every qualifying occurrence. Exclude words with uncertain or mixed origins.", style: .latin),
            PromptButton(name: "Removable wording", icon: .scissors,
                         prompt: "Highlight words or phrases that can be deleted to make the writing tighter without losing its main meaning or breaking its grammar. Prefer clear redundancies, filler, and unnecessary qualifications. Highlight only the wording to remove, not the surrounding sentence.", style: .cuts)
        ]
    }
}

extension PromptButton {
    private enum CodingKeys: String, CodingKey { case id, name, icon, prompt, style }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decode(PromptIcon.self, forKey: .icon)
        prompt = try values.decode(String.self, forKey: .prompt)
        if values.contains(.style) {
            style = try values.decode(HighlightStyle.self, forKey: .style)
        } else {
            style = Self.examples.first { $0.name == name || $0.prompt == prompt }?.style ?? HighlightStyle()
        }
    }
}

@MainActor
final class PromptToolbarSettings: ObservableObject {
    @Published var buttons: [PromptButton] {
        didSet {
            save()
            onChange?(buttons)
        }
    }
    @Published var error: String? {
        didSet { if let error { echo.message = error } }
    }
    let echo: EchoBuffer
    private(set) var isReadOnly = false
    var onChange: (([PromptButton]) -> Void)?
    private let preferences: UserDefaults
    static let preferenceKey = "promptToolbarButtons"
    static let latinIconMigrationKey = "latinHighlightLaurelMigrated"

    init(preferences: UserDefaults, echo: EchoBuffer? = nil) {
        self.preferences = preferences
        self.echo = echo ?? EchoBuffer()
        if preferences.object(forKey: Self.preferenceKey) == nil {
            buttons = PromptButton.examples
        } else {
            do {
                guard let data = preferences.data(forKey: Self.preferenceKey) else { throw CocoaError(.coderReadCorrupt) }
                let saved = try JSONDecoder().decode([PromptButton].self, from: data)
                guard Set(saved.map(\.id)).count == saved.count, saved.allSatisfy({ $0.style.isValid }) else { throw CocoaError(.coderReadCorrupt) }
                buttons = saved
            } catch {
                buttons = []
                isReadOnly = true
                self.error = "Your toolbar settings could not be read and have been left untouched. Open Settings to reset them: \(error.localizedDescription)"
            }
        }
        if !isReadOnly {
            if !preferences.bool(forKey: Self.latinIconMigrationKey) {
                let latin = PromptButton.examples[0]
                for index in buttons.indices where buttons[index].icon == .leaf &&
                    (buttons[index].name == latin.name || buttons[index].prompt == latin.prompt) {
                    buttons[index].icon = .laurel
                }
            }
            save()
            if error == nil { preferences.set(true, forKey: Self.latinIconMigrationKey) }
        }
        if let error { self.echo.message = error }
    }

    private func save() {
        guard !isReadOnly else { return }
        do { preferences.set(try JSONEncoder().encode(buttons), forKey: Self.preferenceKey) }
        catch { self.error = "Couldn't save toolbar settings: \(error.localizedDescription)" }
    }

    func reset() {
        isReadOnly = false
        error = nil
        buttons = PromptButton.examples
        if error == nil {
            preferences.set(true, forKey: Self.latinIconMigrationKey)
            echo.message = "Toolbar reset to examples."
        }
    }
}

struct PromptToolbar: View {
    @ObservedObject var settings: PromptToolbarSettings
    @ObservedObject var controller: HighlightController
    let toggle: (PromptButton) -> Void
    let openSettings: () -> Void

    var body: some View {
        if settings.buttons.isEmpty {
            Button("Add buttons…", action: openSettings)
                .font(.system(size: 13)).foregroundStyle(Theme.blue).buttonStyle(.plain).focusable(false)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(settings.buttons) { button in
                        PromptToolbarButton(button: button, selected: controller.activeButtonID == button.id,
                                            state: controller.state) {
                            toggle(button)
                        }
                    }
                }.padding(.vertical, 8)
            }.scrollIndicators(.hidden).frame(height: 50)
        }
    }
}

private struct PromptToolbarButton: View {
    let button: PromptButton
    let selected: Bool
    let state: HighlightController.State
    let action: () -> Void
    @ViewState<Bool> private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loading: Bool { selected && (state == .loading || state == .signingIn) }
    private var help: String {
        guard button.isConfigured else { return "Set a name and prompt in Settings" }
        guard selected else { return button.name }
        if state == .signingIn { return "Sign in to Claude in your browser; click to cancel" }
        if loading { return "\(button.name) — analyzing; click to cancel" }
        return "\(button.name) — click to turn off"
    }

    var body: some View {
        Button(action: action) {
            Group {
                if loading && !reduceMotion {
                    BouncingPromptIcon(icon: button.icon)
                } else {
                    button.icon.image
                }
            }
                .font(.system(size: 19))
                .transaction { $0.animation = nil }
                .foregroundStyle(selected ? Theme.toolbarActive : (hovering ? Theme.toolbarIconHover : Theme.toolbarIcon))
                .opacity(button.isConfigured ? 1 : 0.4)
                .frame(width: 34, height: 34)
                .background(Theme.toolbarHover.opacity(hovering && button.isConfigured ? 1 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).focusable(false)
        .onHover { hovering = $0 }
        .disabled(!button.isConfigured)
        .accessibilityLabel(button.name).accessibilityValue(selected ? (loading ? "Loading" : "On") : "Off")
        .accessibilityIdentifier("prompt-button-\(button.id)")
        .help(help)
    }
}

private struct BouncingPromptIcon: View {
    let icon: PromptIcon
    @ViewState<Date> private var started = .now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let phase = max(0, timeline.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: 1)
            let progress = min(phase / 0.65, 1)
            let height = 8 * 4 * progress * (1 - progress)
            icon.image.offset(y: -height)
        }
    }
}

struct ToolbarSettingsView: View {
    @ObservedObject var settings: PromptToolbarSettings
    @ViewState<UUID?> private var selection = nil
    @ViewState<Bool> private var confirmReset = false

    var body: some View {
        Group {
            if settings.isReadOnly {
                VStack(spacing: 20) {
                    Text(settings.error ?? "Toolbar settings are unavailable.")
                    Button("Reset toolbar to examples") { confirmReset = true }
                }.padding(30)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        List(selection: $selection) {
                            ForEach(settings.buttons) { button in
                                Label {
                                    Text(button.name.isEmpty ? "Untitled button" : button.name)
                                } icon: {
                                    button.icon.image
                                }.tag(button.id)
                            }
                            .onMove { settings.buttons.move(fromOffsets: $0, toOffset: $1) }
                        }
                        HStack {
                            Button {
                                let button = PromptButton()
                                settings.buttons.append(button)
                                selection = button.id
                            } label: { Image(systemName: "plus") }
                                .help("Add button").accessibilityLabel("Add button")
                            Button {
                                guard let id = selection else { return }
                                selection = nil
                                settings.buttons.removeAll { $0.id == id }
                                selection = settings.buttons.first?.id
                            } label: { Image(systemName: "minus") }
                                .disabled(selection == nil).help("Remove button").accessibilityLabel("Remove button")
                            Spacer()
                        }.padding(12)
                    }.frame(width: 190)
                    Divider()
                    if settings.buttons.isEmpty {
                        Text("Add a button to choose its icon and write a highlighting prompt.")
                            .foregroundStyle(Theme.secondary).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach($settings.buttons) { $button in
                            if button.id == selection { PromptButtonEditor(button: $button, onError: { settings.error = $0 }) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 660, minHeight: 450)
        .background(Theme.background).foregroundStyle(Theme.foreground)
        .onAppear { selection = settings.buttons.first?.id }
        .confirmationDialog("Replace the unreadable toolbar settings with the two examples?", isPresented: $confirmReset) {
            Button("Reset toolbar", role: .destructive) { settings.reset(); selection = settings.buttons.first?.id }
        }
    }
}

private struct PromptButtonEditor: View {
    @Binding var button: PromptButton
    let onError: (String) -> Void
    @ViewState<Bool> private var choosingIcon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Toolbar button").font(.system(size: 20, weight: .bold))
                HStack(spacing: 12) {
                    Button { choosingIcon = true } label: {
                        button.icon.image.font(.system(size: 22))
                            .foregroundStyle(Theme.blue).frame(width: 40, height: 36)
                    }
                    .help("Choose icon").accessibilityLabel("Choose icon")
                    .popover(isPresented: $choosingIcon) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 8), spacing: 8) {
                            ForEach(PromptIcon.allCases) { icon in
                                Button { button.icon = icon; choosingIcon = false } label: {
                                    icon.image.font(.system(size: 20))
                                        .frame(width: 38, height: 36)
                                        .background(Theme.blue.opacity(button.icon == icon ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(Theme.blue)
                                    .help(icon.title).accessibilityLabel(icon.title)
                            }
                        }.padding(14).onExitCommand { choosingIcon = false }
                    }
                    TextField("Button name", text: $button.name).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Button name")
                }
                Text("Prompt").font(.system(size: 14, weight: .semibold))
                TextEditor(text: $button.prompt).font(.system(size: 14))
                    .scrollContentBackground(.hidden).padding(8).frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .accessibilityLabel("Highlighting prompt")
                Text("Describe what to highlight. The app supplies the entire active post and handles the output format; you don't need to write JSON.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Divider().padding(.vertical, 4)
                HighlightStyleEditor(style: $button.style, onError: onError)
                Text("Style changes apply immediately without another model call. Uses the composer's model and reasoning setting. Settings save automatically.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
