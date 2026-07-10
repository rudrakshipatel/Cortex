import Foundation

extension String {
    /// Whitespace- and newline-trimmed copy. Used across content import/parsing.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Split a block of prose into display bullet points: on explicit line
    /// breaks when the author used them, otherwise on sentence boundaries.
    /// Authors get exact control by putting each point on its own line.
    var bulletPoints: [String] {
        let t = trimmed
        guard !t.isEmpty else { return [] }
        let lines = t.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        let ns = t as NSString
        guard let re = try? NSRegularExpression(pattern: "(?<=[.!?])\\s+") else { return [t] }
        let matches = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [t] }
        var parts: [String] = []
        var start = 0
        for m in matches {
            parts.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: start))
        return parts.map(\.trimmed).filter { !$0.isEmpty }
    }

    /// Splits a `"Label: rest"` bullet into its label and remainder so the UI
    /// can emphasise the label (e.g. "Character: Pain is strictly unilateral…").
    /// Returns nil when there's no short, sentence-free leading label.
    var labelledParts: (label: String, rest: String)? {
        guard let r = range(of: ": ") else { return nil }
        let label = String(self[startIndex..<r.lowerBound])
        guard !label.isEmpty, label.count <= 40, !label.contains(". ") else { return nil }
        return (label, String(self[r.upperBound...]))
    }
}
