import SwiftUI

struct SynonymToolbar<Content: View>: View {
    @ObservedObject var controller: SynonymController
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch controller.state {
        case .idle:
            content()
        case .loading, .signingIn:
            TimelineView(.animation(minimumInterval: 0.4)) { timeline in
                let dots = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3 + 1
                Text((controller.state == .signingIn ? "Sign in in your browser" : "pulling synonyms") + String(repeating: ".", count: dots))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(controller.state == .signingIn ? "Waiting for Claude sign-in" : "Pulling synonyms")
            }
        case .ready(let lists):
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        Image(systemName: "laurel.leading")
                        Image(systemName: "laurel.trailing")
                    }
                    .font(.system(size: 13)).frame(width: 17, height: 17)
                    .help("Latin-rooted synonyms")
                    ComposerIcon(kind: .oak, size: 17).help("Germanic-rooted synonyms")
                }.foregroundStyle(Theme.secondary).accessibilityHidden(true)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 5) {
                        row(lists.latin, label: "Latin-rooted synonyms")
                        row(lists.germanic, label: "Germanic-rooted synonyms")
                    }
                }.scrollIndicators(.hidden).frame(height: 39)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("synonym-results")
        }
    }

    private func row(_ words: [String], label: String) -> some View {
        HStack(spacing: 12) {
            if words.isEmpty {
                Text("None found").foregroundStyle(Theme.secondary)
            }
            ForEach(words, id: \.self) { word in
                Button(word) {
                    _ = controller.choose(word)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.blue).focusable(false)
                .accessibilityLabel("Replace with \(word)")
                .help("Replace with \(word)")
            }
        }
        .font(.system(size: 13)).frame(height: 17).fixedSize()
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}
