import Foundation

extension String {
    /// Whitespace- and newline-trimmed copy. Used across content import/parsing.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Split a block of prose into its display points: on explicit line breaks
    /// when the author used them, otherwise on sentence boundaries. Authors get
    /// exact control by putting each point on its own line.
    var bulletPoints: [String] {
        let t = trimmed
        guard !t.isEmpty else { return [] }
        let lines = t.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        let broken = Self.sentenceBreak.stringByReplacingMatches(
            in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "\n")
        let parts = broken.components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty }
        return parts.isEmpty ? [t] : parts
    }

    private static let sentenceBreak = try! NSRegularExpression(pattern: "(?<=[.!?])\\s+")

    /// Splits a `"Label: rest"` line into its label and remainder so the UI can
    /// emphasise the label (e.g. "The Game Trap: …"). Returns nil when there's no
    /// short, sentence-free leading label.
    var labelledParts: (label: String, rest: String)? {
        guard let sep = range(of: ": "), sep.lowerBound > startIndex else { return nil }
        let label = String(self[startIndex..<sep.lowerBound])
        guard label.count <= 40, !label.contains(". ") else { return nil }
        return (label, String(self[sep.upperBound...]))
    }
}
