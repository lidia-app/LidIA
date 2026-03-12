import Foundation

/// Fuzzy-matches a short quote against a transcript word array.
/// Uses token overlap with a sliding window approach.
enum TranscriptMatcher {

    struct Match {
        /// Index range in the TranscriptWord array.
        let wordRange: Range<Int>
        /// Confidence score (0...1).
        let confidence: Double
        /// Start timestamp of the matched segment.
        var startTime: TimeInterval { 0 }
        /// End timestamp of the matched segment.
        var endTime: TimeInterval { 0 }
    }

    /// Find the best match for `quote` in `words`.
    /// Returns nil if no match exceeds the confidence threshold.
    static func findMatch(
        quote: String,
        in words: [TranscriptWord],
        threshold: Double = 0.6
    ) -> Match? {
        let quoteTokens = tokenize(quote)
        guard quoteTokens.count >= 2 else { return nil }
        guard !words.isEmpty else { return nil }

        let windowSize = min(quoteTokens.count * 3, words.count)
        let quoteSet = Set(quoteTokens)

        var bestScore: Double = 0
        var bestRange: Range<Int>?

        for start in 0...(words.count - min(windowSize, words.count)) {
            let end = min(start + windowSize, words.count)
            let windowTokens = words[start..<end].flatMap { tokenize($0.word) }
            let windowSet = Set(windowTokens)

            let overlap = quoteSet.intersection(windowSet).count
            let score = Double(overlap) / Double(quoteSet.count)

            if score > bestScore {
                bestScore = score
                bestRange = start..<end
            }
        }

        guard bestScore >= threshold, let range = bestRange else { return nil }
        return Match(wordRange: range, confidence: bestScore)
    }

    /// Find match and return with actual timestamps from the word array.
    static func findMatchWithTimestamps(
        quote: String,
        in words: [TranscriptWord],
        contextSeconds: TimeInterval = 30,
        threshold: Double = 0.6
    ) -> (match: Match, contextRange: Range<Int>)? {
        guard let match = findMatch(quote: quote, in: words, threshold: threshold) else { return nil }

        // Expand range to include context
        let matchStart = words[match.wordRange.lowerBound].start
        let matchEnd = words[match.wordRange.upperBound - 1].end

        let contextStartTime = max(0, matchStart - contextSeconds)
        let contextEndTime = matchEnd + contextSeconds

        let contextStart = words.firstIndex { $0.start >= contextStartTime } ?? match.wordRange.lowerBound
        let contextEnd = (words.lastIndex { $0.end <= contextEndTime } ?? (match.wordRange.upperBound - 1)) + 1

        return (match, contextStart..<min(contextEnd, words.count))
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 }
    }
}
