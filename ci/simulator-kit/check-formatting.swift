import Foundation

@main
enum CheckFormatting {
    @MainActor static func main() {
        let cache = AnalystAnswerFormatting()
        let answers = (0..<13).map { index in
            String(repeating: "**Reply \(index)** · سؤال مصطنع \n", count: 36)
        }
        var misses = 0
        for index in 0..<516 {
            let answer = answers[index % answers.count]
            let result = cache.value(for: answer) {
                misses += 1
                let text = try! AttributedString(markdown: answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                return .init(text: text, accessibilityText: String(text.characters), rightToLeft: true)
            }
            precondition(result.accessibilityText.contains("Reply \(index % answers.count)") && result.rightToLeft)
            precondition(result.accessibilityText == String(result.text.characters))
        }
        precondition(misses == 13)
        print("516 lookups for 13 distinct long bilingual answers; \(misses) prepares.")
    }
}
