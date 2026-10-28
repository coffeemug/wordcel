import AppKit
import SwiftUI

struct ComposeView: View {
    @ObservedObject var model: ComposerModel
    @ViewState<Bool> private var modelPopover = false
    @ViewState<Bool> private var planPopover = false
    @ViewState<Bool> private var dropTarget = false

    var body: some View {
        HStack(spacing: 0) {
            composer.frame(width: model.composerWidth)
            if model.showDrafts {
                DraftsView(model: model)
                    .frame(width: ComposerWindowSizing.drawerWidth)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .sheet(isPresented: $model.showHandoff) { HandoffView(model: model) }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .frame(minWidth: ComposerWindowSizing.minimumWidth + (model.showDrafts ? ComposerWindowSizing.drawerWidth : 0),
               maxWidth: .infinity, minHeight: 300, alignment: .leading)
        .ignoresSafeArea()
    }

    private var composer: some View {
        VStack(spacing: 0) {
            header.measuringComposerHeight()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let date = model.draft.plannedDate {
                            HStack(spacing: 7) {
                                Image(systemName: "calendar")
                                Text("Planned for \(date.formatted(date: .abbreviated, time: .shortened))")
                                Spacer()
                                Button { model.draft.plannedDate = nil } label: { ComposerIcon(kind: .close, size: 14) }
                                    .buttonStyle(.plain).accessibilityLabel("Remove planned date")
                            }
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            .padding(.leading, 68).padding(.trailing, 20).padding(.bottom, 12)
                        }
                        ForEach($model.draft.posts) { $post in
                            PostEditor(post: $post, model: model, isLast: post.id == model.draft.posts.last?.id)
                                .id(post.id)
                        }
                    }.padding(.top, 8).measuringComposerHeight()
                }
                .onChange(of: model.activePostID) { _, id in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            modelControl.measuringComposerHeight()
            toolbar.measuringComposerHeight()
        }
        .onPreferenceChange(ComposerHeightKey.self) { model.onContentHeightChange?($0) }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.blue, lineWidth: 2)
                    .padding(4).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Theme.blue, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .padding(.bottom, 69).allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.toast)
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            let postID = model.activePostID
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { model.addImages([url], to: postID) }
                }
            }
            return !providers.isEmpty
        }
    }

    private var header: some View {
        HStack {
            Button { NSApp.keyWindow?.performClose(nil) } label: { ComposerIcon(kind: .close, size: 22) }
                .buttonStyle(RoundButtonStyle()).help("Close • your draft is saved automatically")
                .accessibilityLabel("Close composer")
            Spacer()
            Button { model.toggleDrafts() } label: { ComposerIcon(kind: .drawer, size: 22) }
                .foregroundStyle(Theme.blue).buttonStyle(RoundButtonStyle(blue: true))
                .background(Theme.blue.opacity(model.showDrafts ? 0.1 : 0), in: Circle())
                .help(model.showDrafts ? "Hide drafts (⌘D)" : "Show drafts (⌘D)")
                .accessibilityLabel("Toggle drafts")
                .accessibilityValue(model.showDrafts ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("toggle-drafts")
        }
        .padding(.horizontal, 8).frame(height: 52)
        .background(WindowDragArea())
    }

    private var modelControl: some View {
        HStack {
            Button { modelPopover.toggle() } label: {
                HStack(spacing: 5) {
                    ComposerIcon(kind: .robot, size: 16)
                    Text(model.synonymModel.title).font(.system(size: 14, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.blue).padding(.vertical, 8).padding(.horizontal, 10)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).focusable(false)
            .help("Choose the synonym model and reasoning level (\(model.synonymEffort.title.lowercased()) effort)")
            .accessibilityLabel("Synonym model and reasoning")
            .accessibilityValue("\(model.synonymModel.title), \(model.synonymEffort.title) reasoning")
            .accessibilityIdentifier("synonym-model")
            .popover(isPresented: $modelPopover, arrowEdge: .bottom) {
                ModelPicker(selection: $model.synonymModel, effort: $model.synonymEffort)
                    .onExitCommand { modelPopover = false }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 58).padding(.trailing, 16).padding(.bottom, 7)
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                SynonymToolbar(controller: model.synonyms) {
                    HStack(spacing: 0) {
                        tool(.photo, "Add photos") { model.pickImages() }
                            .disabled(model.draft.posts[model.activeIndex].poll != nil || model.draft.posts[model.activeIndex].attachments.count >= 4)
                        tool(.gif, "Add a GIF from your Mac") { model.pickImages(gifOnly: true) }
                            .disabled(model.draft.posts[model.activeIndex].poll != nil || model.draft.posts[model.activeIndex].attachments.count >= 4)
                        tool(.poll, "Add a poll") { model.draft.posts[model.activeIndex].poll = Poll() }
                            .disabled(!model.draft.posts[model.activeIndex].attachments.isEmpty || model.draft.posts[model.activeIndex].poll != nil)
                        tool(.emoji, "Emoji & Symbols (⌃⌘Space)") {
                            if let editor = model.activeEditor { editor.window?.makeFirstResponder(editor) }
                            NSApp.orderFrontCharacterPalette(nil)
                        }
                        tool(.calendar, "Plan a post") { planPopover.toggle() }
                            .popover(isPresented: $planPopover, arrowEdge: .bottom) { PlanPicker(model: model) { planPopover = false } }
                        tool(.location, "Add a location on X when you publish") { }
                            .disabled(true)
                    }
                }.padding(.leading, 44)
                Spacer(minLength: 8)
                if model.draft.posts[model.activeIndex].hasContent {
                    CharacterRing(count: TweetLength.count(model.draft.posts[model.activeIndex].text))
                    Rectangle().fill(Theme.border).frame(width: 1, height: 30).padding(.horizontal, 12)
                    Button { model.addPost() } label: {
                        ComposerIcon(kind: .plus, size: 17)
                            .frame(width: 23, height: 23)
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                    .foregroundStyle(Theme.blue).buttonStyle(.plain)
                    .disabled(model.draft.posts.last?.valid != true)
                    .help("Add another post (⌘⇧Return)").accessibilityLabel("Add another post")
                    .padding(.trailing, 12)
                }
                Button(model.draft.posts.count > 1 ? "Post all" : "Post") { model.prepareHandoff() }
                    .buttonStyle(PillButtonStyle()).disabled(!model.canPost)
                    .help("Continue on X (⌘Return)")
            }
            .frame(height: 58)
        }.padding(.horizontal, 16)
    }

    private func tool(_ icon: ComposerIcon.Kind, _ label: String, action: @escaping () -> Void) -> some View {
        ToolButton(icon: icon, label: label, action: action)
    }
}

struct ToolButton: View {
    let icon: ComposerIcon.Kind
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) { ComposerIcon(kind: icon).opacity(enabled ? 1 : 0.4) }
            .foregroundStyle(Theme.blue).buttonStyle(RoundButtonStyle(blue: true))
            .help(label).accessibilityLabel(label)
    }
}

struct PostEditor: View {
    @Binding var post: Post
    @ObservedObject var model: ComposerModel
    let isLast: Bool
    @ViewState<CGFloat> private var height = 124
    @ViewState<Bool> private var confirmRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Button { model.chooseAvatar() } label: { AvatarView(image: model.avatar) }
                    .buttonStyle(.plain).help("Choose your profile photo").accessibilityLabel("Choose profile photo")
                if !isLast { Rectangle().fill(Theme.border).frame(width: 2).frame(maxHeight: .infinity) }
            }.frame(width: 40)
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if post.text.isEmpty {
                        Text(model.draft.posts.first?.id == post.id ? "What is happening?!" : "Add another post")
                            .font(.system(size: 20)).foregroundStyle(Theme.secondary)
                            .padding(.top, 5).allowsHitTesting(false)
                    }
                    GrowingTextView(text: $post.text, height: $height, postID: post.id, model: model)
                        .frame(height: height)
                }
                if !post.attachments.isEmpty { AttachmentGrid(attachments: $post.attachments) }
                if post.poll != nil {
                    PollEditor(poll: Binding(get: { post.poll ?? Poll() }, set: { post.poll = $0 })) { post.poll = nil }
                }
                if model.draft.posts.count > 1 {
                    HStack {
                        Text("\((model.draft.posts.firstIndex(where: { $0.id == post.id }) ?? 0) + 1) of \(model.draft.posts.count)")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Remove") {
                            if post.hasContent { confirmRemoval = true } else { model.removePost(post.id) }
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, isLast ? 4 : 22)
        .alert("Remove this post?", isPresented: $confirmRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { model.removePost(post.id) }
        } message: { Text("The other posts in your thread will stay here.") }
    }
}

struct AvatarView: View {
    var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(red: 0.85, green: 0.92, blue: 0.96)
                    Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(Color(red: 0.36, green: 0.55, blue: 0.66)).offset(y: 5)
                }
            }
        }.frame(width: 40, height: 40).clipShape(Circle())
    }
}

struct CharacterRing: View {
    let count: Int
    private var state: CharacterCounterState { CharacterCounterState(count: count) }
    private var color: Color {
        state.remaining < 0 ? Theme.danger : state.remaining <= 20 ? Color(red: 1, green: 0.68, blue: 0) : Color(red: 73/255, green: 151/255, blue: 243/255)
    }
    var body: some View {
        ZStack {
            if state.remaining >= -9 {
                Circle().stroke(Theme.border, lineWidth: 2)
                Circle().trim(from: 0, to: state.perimeterProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                if let progress = state.fillProgress {
                    PremiumFill(progress: progress)
                        .fill(color.opacity(state.remaining <= 20 ? 0.18 : 1)).padding(2)
                }
            }
            if let countdown = state.countdown {
                Text("\(countdown)").font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(state.remaining < 0 ? Theme.danger : Theme.secondary)
            }
        }
        .frame(width: state.isExpanded ? 30 : 21, height: state.isExpanded ? 30 : 21)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(state.remaining) characters remaining")
        .help("\(count.formatted()) / \(TweetLength.limit.formatted()) characters · X Premium")
    }
}

private struct PremiumFill: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        // X's long-post indicator has a flat, rising waterline. At the
        // transition it starts with a thin visible sliver along the bottom.
        let height = max(2, rect.height * min(1, max(0, progress)))
        let fill = Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
        return Path(ellipseIn: rect).intersection(fill)
    }
}

private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    // Measure the scroll document and fixed controls separately. Measuring the
    // ScrollView itself would only report its current viewport, preventing growth.
    func measuringComposerHeight() -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: ComposerHeightKey.self, value: geometry.size.height)
        })
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) { }
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
