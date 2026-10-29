import AppKit
import SwiftUI

struct ComposeView: View {
    @ObservedObject var model: ComposerModel
    @ViewState<Bool> private var modelPopover = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                composer.frame(width: model.composerWidth)
                if model.showDrafts {
                    DraftsView(model: model)
                        .frame(width: ComposerWindowSizing.drawerWidth)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
                }
            }
            EchoArea(buffer: model.echo).measuringComposerHeight()
        }
        .onPreferenceChange(ComposerHeightKey.self) { model.onContentHeightChange?($0) }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .sheet(isPresented: $model.showHandoff) { HandoffView(model: model) }
        .frame(minWidth: ComposerWindowSizing.minimumWidth + (model.showDrafts ? ComposerWindowSizing.drawerWidth : 0),
               maxWidth: .infinity, minHeight: 300 + ComposerWindowSizing.echoAreaHeight, alignment: .leading)
        .ignoresSafeArea()
    }

    private var composer: some View {
        VStack(spacing: 0) {
            header.measuringComposerHeight()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
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
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
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
                    PromptToolbar(settings: model.toolbarSettings, controller: model.highlights,
                                  toggle: model.toggleHighlights, openSettings: { model.onShowSettings?() })
                }.padding(.leading, 44)
                Spacer(minLength: 8)
                if model.draft.posts[model.activeIndex].hasContent {
                    CharacterRing(count: TweetLength.count(model.draft.posts[model.activeIndex].text))
                        .padding(.trailing, 12)
                }
                Button(model.draft.posts.count > 1 ? "Post all" : "Post") { model.prepareHandoff() }
                    .buttonStyle(PillButtonStyle()).disabled(!model.canPost)
                    .help("Continue on X (⌘Return)")
            }
            .frame(height: 58)
        }.padding(.horizontal, 16)
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
