import Foundation

/// Ephemeral display data. Authoritative answers and sources stay in the archive.
@MainActor
final class AnalystAnswerFormatting {
    final class Prepared {
        let text: AttributedString
        let accessibilityText: String
        let rightToLeft: Bool

        init(text: AttributedString, accessibilityText: String, rightToLeft: Bool) {
            self.text = text
            self.accessibilityText = accessibilityText
            self.rightToLeft = rightToLeft
        }
    }

    private let entries = NSCache<NSString, Prepared>()

    init() {
        entries.countLimit = 32
        entries.totalCostLimit = 512 * 1024
    }

    func value(for answer: String, prepare: () -> Prepared) -> Prepared {
        let key = answer as NSString
        if let existing = entries.object(forKey: key) { return existing }
        let prepared = prepare()
        let cost = answer.utf8.count + prepared.accessibilityText.utf8.count
        if cost <= entries.totalCostLimit {
            entries.setObject(prepared, forKey: key, cost: cost)
        }
        return prepared
    }
}
