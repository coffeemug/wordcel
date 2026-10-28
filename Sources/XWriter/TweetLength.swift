import Foundation

enum TweetLength {
    static let standardLimit = 280
    static let limit = 25_000
    private static let links = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // X uses weighted Unicode length and reserves 23 characters for each URL.
    // NSDataDetector is deliberately used instead of shipping a web runtime.
    static func count(_ text: String) -> Int {
        let normalized = text.precomposedStringWithCanonicalMapping
        let ns = normalized as NSString
        let matches = links.matches(in: normalized, range: NSRange(location: 0, length: ns.length))
            .filter { ["http", "https"].contains($0.url?.scheme?.lowercased() ?? "") }
        var result = 0
        var offset = 0
        for match in matches {
            result += weight(ns.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            result += 23
            offset = NSMaxRange(match.range)
        }
        return result + weight(ns.substring(from: offset))
    }

    private static func weight(_ text: String) -> Int {
        text.reduce(0) { total, character in
            let scalars = character.unicodeScalars
            if scalars.contains(where: { $0.properties.isEmojiPresentation }) ||
                (scalars.contains(where: { $0.value == 0xfe0f || $0.value == 0x20e3 }) &&
                 scalars.contains(where: { $0.properties.isEmoji })) {
                return total + 2
            }
            return total + scalars.reduce(0) { sum, scalar in
                let v = scalar.value
                return sum + ((v <= 0x10ff || (0x2000...0x200d).contains(v) ||
                              (0x2010...0x201f).contains(v) || (0x2032...0x2037).contains(v)) ? 1 : 2)
            }
        }
    }
}

struct CharacterCounterState {
    let count: Int
    var remaining: Int { TweetLength.limit - count }
    var countdown: Int? {
        if (TweetLength.standardLimit - 20..<TweetLength.standardLimit).contains(count) {
            return TweetLength.standardLimit - count
        }
        return remaining <= 20 ? remaining : nil
    }
    var isExpanded: Bool { count >= TweetLength.standardLimit - 20 }
    var perimeterProgress: CGFloat { min(1, max(0, CGFloat(count) / CGFloat(TweetLength.standardLimit))) }
    var fillProgress: CGFloat? {
        guard count >= TweetLength.standardLimit else { return nil }
        return min(1, CGFloat(count - TweetLength.standardLimit) / CGFloat(TweetLength.limit - TweetLength.standardLimit))
    }
}
