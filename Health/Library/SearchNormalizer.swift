import Foundation

/// Shared normalization for search haystacks and queries (and duplicate checks).
enum SearchNormalizer {
    private static let removed: Set<Character> = ["-", "·", "_", "‐", "‑", "–", "—", "・", "ㆍ"]

    static func normalize(_ s: String) -> String {
        let folded = s.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.filter { !$0.isWhitespace && !removed.contains($0) })
    }
}
