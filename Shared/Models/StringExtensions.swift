import Foundation

extension String {
    /// Whitespace- and newline-trimmed copy. Used across content import/parsing.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
