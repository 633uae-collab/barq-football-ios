import Foundation

// Copied into a disposable diagnostic build only, never the shipping app target.
// Every URLSession request is intercepted. No real provider or network fallback.
final class AnalystSyntheticProtocol: URLProtocol {
    private let queue = DispatchQueue(label: "ae.barq.synthetic-transport")
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "fotiq-synthetic.invalid",
              request.url?.path == "/api/analyst/chat", request.httpMethod == "POST" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        var bytes = request.httpBody
        if bytes == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }; body.append(contentsOf: buffer.prefix(n))
            }
            bytes = body
        }
        guard let bytes,
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let question = json["question"] as? String else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse)); return
        }
        // Long mixed Markdown creates real parsing/layout work in the unchanged view.
        let paragraph = "**SYNTHETIC ONLY** — اختبار مصطنع، لا مباراة أو لاعب حقيقي.\n- Artificial football diagnostic content; no provider facts.\n- `fixture` **team** *season* — بيانات غير حقيقية.\n\n"
        if question == "Synthetic restoration follow-up: verify saved history" {
            let expectedQuestions = [
                "اختبار مصطنع: حلل المباراة المنتهية", "Synthetic test: explain the completed match",
                "اختبار مصطنع: اذكر مصادر الأرقام", "Synthetic test: explain the source limitations"
            ]
            guard let history = json["history"] as? [[String: String]], history.count == 8 else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse)); return
            }
            for (index, prior) in expectedQuestions.enumerated() {
                let raw = "SYNTHETIC SEND CONTROL\n" + prior + "\n\n" + String(repeating: paragraph, count: 24)
                // All fixture scalars are BMP with no combining sequences; this
                // independent UTF-16 prefix is the documented request bound.
                let bounded = String(decoding: Array(raw.utf16.prefix(1000)), as: UTF16.self)
                guard history[index * 2] == ["role": "user", "content": prior],
                      history[index * 2 + 1] == ["role": "assistant", "content": bounded] else {
                    client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse)); return
                }
            }
        }
        let answer = "SYNTHETIC SEND CONTROL\n" + question + "\n\n" + String(repeating: paragraph, count: 24)
        let body: [String: Any] = [
            "answer": answer, "model": "openai/gpt-oss-120b", // simulated schema, not Groq
            "fetchedAt": 0, "generatedAt": 0, "context": [:],
            "sources": [["name": "Synthetic diagnostic fixture — not live"]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        // URLProtocol callback queue, never MainActor. Exercise pending state for 2 s.
        queue.asyncAfter(deadline: .now() + 2) { [self] in
            guard !stopped else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { queue.async { [self] in stopped = true } }
}

