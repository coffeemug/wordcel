import SwiftUI

struct ModelPicker: View {
    @Binding var selection: ClaudeModel
    @Binding var effort: ClaudeEffort
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ClaudeModel.allCases) { model in
                option(model.title, selected: model == selection) {
                    selection = model
                }
                .accessibilityIdentifier("synonym-model-\(model.rawValue)")
            }
            Divider().padding(.vertical, 6)
            Text("Reasoning").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            ForEach(ClaudeEffort.allCases) { level in
                option(level.title, selected: level == effort) {
                    effort = level
                }
                .accessibilityIdentifier("synonym-effort-\(level.rawValue)")
            }
        }
        .foregroundStyle(Theme.foreground).padding(12).frame(width: 220).background(Theme.background)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.blue).fontWeight(.bold) }
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct DraftsView: View {
    @ObservedObject var model: ComposerModel
    @ViewState<Draft?> private var deleting = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("New post") { model.newDraft() }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.blue)
                    .buttonStyle(.plain).padding(.vertical, 9).help("New post (⌘N)")
            }.padding(.horizontal, 16).frame(height: 52)
            Rectangle().fill(Theme.border).frame(height: 1)
            if model.drafts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save it for later").font(.system(size: 24, weight: .heavy))
                    Text("Your writing is saved automatically.\nCome back whenever you're ready.")
                        .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.drafts) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Button { model.load(item) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(item.id == model.draft.id ? "Current draft" : "Draft").fontWeight(.bold)
                                            Text(item.modified, style: .date).foregroundStyle(Theme.secondary)
                                        }.font(.system(size: 12))
                                        Text(item.title).font(.system(size: 15)).lineLimit(3).multilineTextAlignment(.leading)
                                        if item.posts.count > 1 {
                                            Label("\(item.posts.count) posts", systemImage: "text.bubble")
                                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { deleting = item } label: { Image(systemName: "trash").font(.system(size: 14)) }
                                    .buttonStyle(RoundButtonStyle()).foregroundStyle(Theme.secondary).help("Delete draft")
                                    .accessibilityLabel("Delete draft")
                            }.padding(16)
                                .background(item.id == model.draft.id ? Theme.blue.opacity(0.06) : .clear)
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity).background(Theme.background).foregroundStyle(Theme.foreground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drafts")
        .accessibilityIdentifier("drafts-drawer")
        .alert("Delete this draft?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let item = deleting { model.deleteDraft(item.id) }; deleting = nil }
        } message: { Text("This will remove the draft from this Mac.") }
    }
}

struct HandoffView: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
        VStack(spacing: 0) {
            content
            EchoArea(buffer: model.echo)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ready for X").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { model.showHandoff = false } label: { ComposerIcon(kind: .close) }
                    .buttonStyle(RoundButtonStyle()).accessibilityLabel("Back to composer")
            }
            Text("Open your text on X to review and publish. Your draft stays saved here.")
                .font(.system(size: 15)).foregroundStyle(Theme.secondary)
            if model.draft.posts.count > 1 {
                Label("For a thread, publish the first post, then copy the remaining posts into replies on X.", systemImage: "text.bubble")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            if model.draft.audience != .everyone {
                Text("Apply your saved reply settings on X before publishing.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.hover, in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(model.draft.posts.enumerated()), id: \.element.id) { index, post in
                        VStack(alignment: .leading, spacing: 12) {
                            if model.draft.posts.count > 1 { Text("Post \(index + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.secondary) }
                            if !post.text.isEmpty { Text(post.text).font(.system(size: 17)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            HStack(spacing: 16) {
                                Button("Copy text") { model.copy(post.text) }.buttonStyle(.plain).foregroundStyle(Theme.blue).disabled(post.text.isEmpty)
                                Spacer()
                                if index == 0 {
                                    Button(ComposerModel.requiresClipboardHandoff(post.text) ? "Copy & open X ↗" : "Open on X ↗") {
                                        model.openOnX(post)
                                    }.buttonStyle(PillButtonStyle())
                                }
                            }.font(.system(size: 13, weight: .semibold))
                            if index == 0 && ComposerModel.requiresClipboardHandoff(post.text) {
                                Text("Your long post will be copied. Paste it into X with ⌘V, then publish.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                        }.padding(16).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }
                }
            }
            HStack {
                Text(model.draft.audience.label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Back to editing") { model.showHandoff = false }.buttonStyle(.plain).foregroundStyle(Theme.blue)
            }
        }.padding(24).frame(width: 550, height: 500).foregroundStyle(Theme.foreground).background(Theme.background)
    }
}
