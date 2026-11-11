import SwiftUI

// Disposable candidate only. It changes rendering work, never the stored reply.
private struct AnalystPreparedText: Sendable {
    let original: String
    let attributed: AttributedString
    let accessible: String
    let rightToLeft: Bool
}

struct AnalystRenderedAnswer: View {
    let answer: String
    let isLatest: Bool
    let english: Bool
    @State private var prepared: AnalystPreparedText?

    var body: some View {
        Group {
            if let prepared, prepared.original == answer {
                Text(prepared.attributed)
                    .accessibilityLabel(Text(verbatim: prepared.accessible))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, prepared.rightToLeft ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(isLatest ? "analyst-answer" : "analyst-previous-answer")
                    .contextMenu {
                        Button(english ? "Copy" : "نسخ", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = answer
                        }
                    }
            } else {
                // Keep the answer's full text footprint while formatting is pending.
                // A one-line spinner collapses restored rows before their async work finishes.
                // The acceptance identifier remains exclusive to the prepared representation.
                Text(verbatim: answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("analyst-rendering")
            }
        }
        .task(id: answer) {
            if prepared?.original == answer { return }
            prepared = nil
            let text = answer
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let attributed = AnalystStageProbe.measure("markdown") {
                    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
                }
                try Task.checkCancellation()
                let accessible = AnalystStageProbe.measure("accessibility-text") {
                    String(attributed.characters)
                }
                let rtl = text.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) != nil
                try Task.checkCancellation()
                return AnalystPreparedText(original: text, attributed: attributed, accessible: accessible, rightToLeft: rtl)
            }
            do {
                let value = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                AnalystStageProbe.measure("render-install") { prepared = value }
            } catch {
                // Cancellation on disappearance or a changed answer cannot install
                // a stale representation into the current row.
            }
        }
    }
}
