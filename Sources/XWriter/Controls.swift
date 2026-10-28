import AppKit
import SwiftUI

struct ModelPicker: View {
    @Binding var selection: ClaudeModel
    @Binding var effort: ClaudeEffort
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ClaudeModel.allCases) { model in
                option(model.title, selected: model == selection) {
                    selection = model
                    done()
                }
                .accessibilityIdentifier("synonym-model-\(model.rawValue)")
            }
            Divider().padding(.vertical, 6)
            Text("Reasoning").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            ForEach(ClaudeEffort.allCases) { level in
                option(level.title, selected: level == effort) {
                    effort = level
                    done()
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

struct AttachmentGrid: View {
    @Binding var attachments: [Attachment]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: attachments.count == 1 ? 1 : 2), spacing: 3) {
            ForEach($attachments) { $attachment in
                AttachmentView(attachment: $attachment, height: attachments.count == 1 ? 235 : 150) {
                    attachments.removeAll { $0.id == attachment.id }
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}

struct AttachmentView: View {
    @Binding var attachment: Attachment
    let height: CGFloat
    let remove: () -> Void
    @ViewState<Bool> private var showAlt = false
    @ViewState<NSImage?> private var preview = nil
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let preview {
                    Image(nsImage: preview).resizable().scaledToFill()
                } else { Theme.hover }
            }
            .frame(width: geometry.size.width, height: height).clipped()
            .overlay(alignment: .topTrailing) {
                Button(action: remove) { ComposerIcon(kind: .close, size: 18).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).foregroundStyle(.white).background(.black.opacity(0.65), in: Circle())
                    .padding(8).help("Remove image").accessibilityLabel("Remove \(attachment.name)")
            }
            .overlay(alignment: .bottomLeading) {
                Button { showAlt = true } label: {
                    Text(attachment.alt.isEmpty ? "+ ALT" : "ALT")
                        .font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 5)
                }.buttonStyle(.plain).foregroundStyle(.white).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    .padding(10).help("Add an image description")
            }
            .accessibilityLabel(attachment.alt.isEmpty ? attachment.name : attachment.alt)
        }
        .frame(height: height)
        .onAppear { preview = NSImage(data: attachment.data) }
        .sheet(isPresented: $showAlt) { AltEditor(attachment: $attachment) { showAlt = false } }
    }
}

struct AltEditor: View {
    @Binding var attachment: Attachment
    var done: () -> Void
    @ViewState<String> private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Image description").font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Save") { attachment.alt = text; done() }.buttonStyle(PillButtonStyle()).disabled(text.count > 1000)
            }
            Text("Describe the image for people who use screen readers.").foregroundStyle(Theme.secondary)
            TextEditor(text: $text).font(.system(size: 16)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 160).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .accessibilityLabel("Image description")
            HStack {
                Button("Cancel", action: done).buttonStyle(.plain).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(text.count) / 1,000").foregroundStyle(text.count > 1000 ? Theme.danger : Theme.secondary)
            }.font(.system(size: 13))
        }.padding(24).frame(width: 480).background(Theme.background).foregroundStyle(Theme.foreground)
            .onAppear { text = attachment.alt }
    }
}

struct PollEditor: View {
    @Binding var poll: Poll
    var remove: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            ForEach(poll.choices.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Choice \(index + 1)")
                            Spacer()
                            Text("\(poll.choices[index].count) / 25")
                                .foregroundStyle(poll.choices[index].count > 25 ? Theme.danger : Theme.secondary)
                        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        TextField("", text: $poll.choices[index]).textFieldStyle(.plain).font(.system(size: 16))
                            .accessibilityLabel("Poll choice \(index + 1)")
                    }.padding(10).overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border))
                    if index == poll.choices.count - 1 && poll.choices.count < 4 {
                        Button { poll.choices.append("") } label: { ComposerIcon(kind: .plus) }
                            .buttonStyle(RoundButtonStyle(blue: true)).foregroundStyle(Theme.blue).help("Add a choice")
                            .accessibilityLabel("Add poll choice")
                    } else if index >= 2 {
                        Button { poll.choices.remove(at: index) } label: { ComposerIcon(kind: .close, size: 16) }
                            .buttonStyle(RoundButtonStyle()).help("Remove choice").accessibilityLabel("Remove poll choice")
                    }
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Poll length").font(.system(size: 14))
                HStack {
                    Picker("Days", selection: $poll.days) { ForEach(0...7, id: \.self) { Text("\($0)") } }
                    Picker("Hours", selection: $poll.hours) { ForEach(0...23, id: \.self) { Text("\($0)") } }
                    Picker("Minutes", selection: $poll.minutes) { ForEach(0...59, id: \.self) { Text("\($0)") } }
                }.font(.system(size: 12))
                if !(5...10080).contains(poll.days * 1440 + poll.hours * 60 + poll.minutes) {
                    Text("Choose a duration between 5 minutes and 7 days.").font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            Button("Remove poll", action: remove).buttonStyle(.plain).foregroundStyle(Theme.danger)
                .font(.system(size: 14)).padding(.vertical, 2)
        }.padding(12).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

struct PlanPicker: View {
    @ObservedObject var model: ComposerModel
    var done: () -> Void
    @ViewState<Date> private var date = Date().addingTimeInterval(3600)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plan a post").font(.system(size: 20, weight: .bold))
            Text("Keep a date with your draft. You'll still need to open X and publish it yourself.")
                .font(.system(size: 14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            DatePicker("Date", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().datePickerStyle(.field)
            HStack {
                if model.draft.plannedDate != nil {
                    Button("Remove") { model.draft.plannedDate = nil; done() }.buttonStyle(.plain).foregroundStyle(Theme.danger)
                }
                Spacer()
                Button("Confirm") { model.draft.plannedDate = date; done() }
                    .buttonStyle(PillButtonStyle()).disabled(date <= Date())
            }
        }.padding(24).frame(width: 340).background(Theme.background).foregroundStyle(Theme.foreground)
            .onAppear { date = model.draft.plannedDate ?? Date().addingTimeInterval(3600) }
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
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 10) {
                                                if item.posts.count > 1 { Label("\(item.posts.count) posts", systemImage: "text.bubble") }
                                                let imageCount = item.posts.reduce(0) { $0 + $1.attachments.count }
                                                if imageCount > 0 { Label("\(imageCount)", systemImage: "photo") }
                                            }
                                            if let date = item.plannedDate { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar") }
                                        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
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
        } message: { Text("This will remove the draft and its attachments from this Mac.") }
    }
}

struct HandoffView: View {
    @ObservedObject var model: ComposerModel
    var body: some View {
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
            if model.draft.audience != .everyone || model.draft.posts.contains(where: { !$0.attachments.isEmpty || $0.poll != nil }) || model.draft.plannedDate != nil {
                Text("Images, image descriptions, polls, reply settings, and planned dates stay in this app. Add them on X before publishing.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.hover, in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(model.draft.posts.enumerated()), id: \.element.id) { index, post in
                        VStack(alignment: .leading, spacing: 12) {
                            if model.draft.posts.count > 1 { Text("Post \(index + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.secondary) }
                            if !post.text.isEmpty { Text(post.text).font(.system(size: 17)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            if let poll = post.poll {
                                ForEach(Array(poll.choices.enumerated()), id: \.offset) { i, choice in
                                    Text("\(i + 1). \(choice)").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                                }
                                Text("Poll length: \(poll.days)d \(poll.hours)h \(poll.minutes)m").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            ForEach(post.attachments) { image in
                                HStack {
                                    Image(systemName: "photo")
                                    Text(image.name).lineLimit(1)
                                    Spacer()
                                    if !image.alt.isEmpty { Button("Copy ALT") { model.copy(image.alt) }.buttonStyle(.plain).foregroundStyle(Theme.blue) }
                                }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            HStack(spacing: 16) {
                                Button("Copy text") { model.copy(post.text) }.buttonStyle(.plain).foregroundStyle(Theme.blue).disabled(post.text.isEmpty)
                                if !post.attachments.isEmpty {
                                    Button("Save images…") { model.exportImages(post) }.buttonStyle(.plain).foregroundStyle(Theme.blue)
                                }
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
