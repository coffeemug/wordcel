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
                    Text("Latin").frame(height: 17)
                    Text("Germanic").frame(height: 17)
                }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 5) {
                        row(lists.latin)
                        row(lists.germanic)
                    }
                }.scrollIndicators(.hidden).frame(height: 39)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("synonym-results")
        }
    }

    private func row(_ words: [String]) -> some View {
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
    }
}
