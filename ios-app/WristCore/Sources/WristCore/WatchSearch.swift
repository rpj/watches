import Foundation

/// Pure, platform-independent search over the watch list used by the picker.
public enum WatchSearch {
    /// Case- and diacritic-insensitive. Every whitespace-separated token of
    /// `query` must occur somewhere in "brand model". Empty/blank query returns
    /// `watches` unchanged. Order is preserved.
    public static func filter(_ watches: [WearWatch], query: String) -> [WearWatch] {
        let tokens = normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return watches }
        return watches.filter { watch in
            let haystack = normalize("\(watch.brand) \(watch.model)")
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    /// Normalised form used for matching (exposed for tests).
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        return folded
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
