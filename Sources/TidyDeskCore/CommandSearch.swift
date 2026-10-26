import Foundation

public struct CommandItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let keywords: [String]
    public let shortcutText: String?

    public init(id: String, title: String, keywords: [String] = [], shortcutText: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.shortcutText = shortcutText
    }
}

/// Forgiving command search: prefix and word-start matches beat substrings, which beat letters that
/// merely appear in order ("tgl" finds "Toggle"). Every word of the query must match.
public enum CommandSearch {
    public static func rank(_ query: String, in items: [CommandItem]) -> [CommandItem] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item -> (score: Int, offset: Int, item: CommandItem)? in
                var total = 0
                for token in tokens {
                    let score = self.score(token, for: item)
                    guard score > 0 else { return nil }
                    total += score
                }
                return (total, offset, item)
            }
            .sorted { ($0.score, -$0.offset) > ($1.score, -$1.offset) }
            .map(\.item)
    }

    private static func score(_ token: String, for item: CommandItem) -> Int {
        let title = item.title.lowercased()
        var best = 0
        if title.hasPrefix(token) { best = 100 }
        else if words(title).contains(where: { $0.hasPrefix(token) }) { best = 80 }
        else if title.contains(token) { best = 60 }
        for keyword in item.keywords.map({ $0.lowercased() }) {
            if words(keyword).contains(where: { $0.hasPrefix(token) }) { best = max(best, 50) }
            else if keyword.contains(token) { best = max(best, 40) }
        }
        if best == 0, isSubsequence(token, of: title) { best = 20 }
        return best
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return false
    }
}
