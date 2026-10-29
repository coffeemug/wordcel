import SwiftUI

struct SynonymEchoArea: View {
    @ObservedObject var controller: SynonymController
    let buffer: EchoBuffer
    var status: String?
    static let minimumResultsHeight: CGFloat = 48

    var body: some View {
        if controller.state == .idle || status != nil {
            EchoArea(buffer: buffer, leadingInset: ComposerWindowSizing.textLeading, status: status)
        } else {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(height: 1)
                content.padding(.leading, ComposerWindowSizing.textLeading).padding(.trailing, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.background)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Echo area")
            .accessibilityIdentifier("echo-area")
        }
    }

    @ViewBuilder private var content: some View {
        switch controller.state {
        case .idle:
            EmptyView()
        case .loading, .signingIn:
            TimelineView(.animation(minimumInterval: 0.4)) { timeline in
                let dots = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3 + 1
                Text((controller.state == .signingIn ? "Sign in in your browser" : "pulling synonyms") + String(repeating: ".", count: dots))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(controller.state == .signingIn ? "Waiting for Claude sign-in" : "Pulling synonyms")
            }
            .frame(height: ComposerWindowSizing.echoAreaHeight - 1)
        case .ready(let lists):
            VStack(alignment: .leading, spacing: 5) {
                row(lists.latin, label: "Latin-rooted synonyms") {
                    PromptIcon.laurel.image
                        .font(.system(size: 13))
                }
                row(lists.germanic, label: "Germanic-rooted synonyms") {
                    ComposerIcon(kind: .oak, size: 17)
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: Self.minimumResultsHeight - 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("synonym-results")
        }
    }

    private func row<Icon: View>(_ words: [String], label: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .top, spacing: 8) {
            icon().frame(width: 17, height: 17)
                .foregroundStyle(Theme.secondary).help(label).accessibilityHidden(true)
            SynonymWordLayout {
                if words.isEmpty {
                    Text("None found").foregroundStyle(Theme.secondary).frame(minHeight: 17)
                }
                ForEach(words, id: \.self) { word in
                    Button(word) {
                        _ = controller.choose(word)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.blue).focusable(false)
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 17)
                    .accessibilityLabel("Replace with \(word)")
                    .help("Replace with \(word)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

private struct SynonymWordLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > (width ?? .infinity) {
                x = 0
                y += rowHeight + 5
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + 12
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}
