import Foundation
import os

/// Talks to the FOTIQ Node backend. The API-SPORTS key never lives in the app.
/// Base URL resolves like the web app: published config.json -> {"api": "..."}; overridable in Settings.
actor API {
    static let shared = API()
    private var base: String?
    private var fixed: String?
    private let session: URLSession
    private let analystSession: URLSession
    private let retryDelay: Double
    /// `protocolClasses` lets unit tests inject a URLProtocol stub (offline / server error / missing data).
    init(protocolClasses: [AnyClass]? = nil, fixedBase: String? = nil, retryDelay: Double = 1) {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 15
        if let p = protocolClasses { c.protocolClasses = p; c.urlCache = nil }
        session = URLSession(configuration: c)
        let ai = URLSessionConfiguration.ephemeral
        ai.timeoutIntervalForRequest = 150
        ai.timeoutIntervalForResource = 180
        ai.urlCache = nil
        if let p = protocolClasses { ai.protocolClasses = p }
        analystSession = URLSession(configuration: ai)
        base = fixedBase; fixed = fixedBase
        self.retryDelay = retryDelay
    }
    private var mem: [String: (Date, Data)] = [:]

    static var configURL: String {
        UserDefaults.standard.string(forKey: "configURL")
            ?? (Bundle.main.object(forInfoDictionaryKey: "BARQConfigURL") as? String)
            ?? "https://koora-ae.surge.sh/config.json"
    }

    func resetBase() { base = fixed; mem.removeAll() }

    private func checkedBase(_ value: String) throws -> String {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw APIError.bad }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func resolveBase() async throws -> String {
        if let b = base { return b }
        if let o = UserDefaults.standard.string(forKey: "apiOverride"), !o.isEmpty { return try checkedBase(o) }
        // Public deployment URL from build settings; API credentials remain server-side.
        if let o = Bundle.main.object(forInfoDictionaryKey: "FOTIQAPIBase") as? String, o.hasPrefix("http") { return try checkedBase(o) }
        guard let url = URL(string: Self.configURL + "?t=\(Int(Date().timeIntervalSince1970))") else { throw APIError.offline }
        let (d, response) = try await session.data(from: url)
        try Self.validate(d, response)
        struct C: Decodable { var api: String }
        let c = try JSONDecoder().decode(C.self, from: d)
        let b = try checkedBase(c.api)
        base = b
        return b
    }

    /// Retries transient failures. The free Pinggy tunnel rotates its URL (the new one is published to config.json),
    /// so a dead/old tunnel (network error, 5xx, or a non-JSON interstitial page) drops the cached base and re-resolves.
    func get<T: Decodable>(_ path: String, maxAge: TimeInterval = 0, attempts: Int = 3, as: T.Type = T.self) async throws -> T {
        if maxAge > 0, let hit = mem[path], Date().timeIntervalSince(hit.0) < maxAge {
            return try JSONDecoder().decode(T.self, from: hit.1)
        }
        var last: Error = APIError.offline
        for attempt in 0..<max(1, attempts) {
            if attempt > 0 { try await Task.sleep(for: .seconds(Double(attempt) * retryDelay)) }
            try Task.checkCancellation()
            do { return try await fetchOnce(path) }
            catch let e as APIError {
                last = e
                switch e {
                case .offline, .temporary: base = fixed
                default: throw e
                }
            } catch let e as DecodingError { last = e; base = fixed }
        }
        throw last
    }

    private func fetchOnce<T: Decodable>(_ path: String) async throws -> T {
        let b: String
        do { b = try await resolveBase() } catch {
            try Task.checkCancellation()
            if let e = error as? APIError { throw e }
            throw APIError.offline
        }
        guard let url = URL(string: b + path) else { throw APIError.bad }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("1", forHTTPHeaderField: "X-Pinggy-No-Screen")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch {
            try Task.checkCancellation()
            base = fixed; throw APIError.offline
        }
        try Self.validate(data, resp)
        let v = try JSONDecoder().decode(T.self, from: data)
        if mem.count >= 128, let oldest = mem.min(by: { $0.value.0 < $1.value.0 })?.key { mem.removeValue(forKey: oldest) }
        mem[path] = (Date(), data)
        return v
    }

    func analystWelcome(language: String) async throws -> AnalystWelcome {
        let b = try await resolveBase()
        guard let url = URL(string: b + "/api/analyst/welcome?lang=" + (language == "en" ? "en" : "ar")) else { throw APIError.bad }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await analystSession.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.offline }
        return try JSONDecoder().decode(AnalystWelcome.self, from: data)
    }

    /// One POST per deliberate send. Never retry or cache a generated answer.
    func askAnalyst(_ question: String, context: AnalystContext = AnalystContext(), history: [AnalystHistoryMessage] = []) async throws -> AnalystReply {
        let b = try await resolveBase()
        guard let url = URL(string: b + "/api/analyst/chat") else { throw APIError.bad }
        struct Request: Encodable { let question: String; let context: AnalystContext; let history: [AnalystHistoryMessage] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Request(question: question, context: context, history: history))
        let data: Data, response: URLResponse
        do { (data, response) = try await analystSession.data(for: request, delegate: AnalystTransportMetrics()) }
        catch {
            // Diagnostic codes only: never log URL, question, headers, userInfo,
            // certificate contents, answer or credentials. TLS validation stays on.
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            Logger(subsystem: "ae.barq.transport", category: "analyst").error("POST transport failure code=\(error.code, privacy: .public) underlyingCode=\(underlying?.code ?? 0, privacy: .public)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        let log = Logger(subsystem: "ae.barq.transport", category: "analyst")
        log.info("POST response status=\(http.statusCode, privacy: .public)")
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "AI_UPSTREAM_UNAVAILABLE"
            let failure = AnalystChatError(code: code, retryAfter: Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""))
            // Only fixed, known categories enter diagnostics; arbitrary server text stays private.
            log.error("POST rejected category=\(failure.diagnosticCode, privacy: .public)")
            throw failure
        }
        let reply: AnalystReply
        do { reply = try JSONDecoder().decode(AnalystReply.self, from: data) }
        catch {
            log.error("POST rejected category=MALFORMED_REPLY")
            throw AnalystChatError(code: "AI_INVALID_RESPONSE", retryAfter: nil)
        }
        guard !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.error("POST rejected category=EMPTY_ANSWER")
            throw AnalystChatError(code: "AI_INVALID_RESPONSE", retryAfter: nil)
        }
        guard reply.responseKind != nil else {
            log.error("POST rejected category=UNKNOWN_MODEL")
            throw AnalystChatError(code: "AI_INVALID_RESPONSE", retryAfter: nil)
        }
        return reply
    }

    func send(_ method: String, _ path: String, body: Encodable) async throws {
        let b: String
        do { b = try await resolveBase() }
        catch {
            try Task.checkCancellation()
            if let error = error as? APIError { throw error }
            throw APIError.offline
        }
        guard let url = URL(string: b + path) else { throw APIError.bad }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Pinggy-No-Screen")
        req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { try Task.checkCancellation(); base = fixed; throw APIError.offline }
        do { try Self.validate(data, response, acknowledgement: true) }
        catch { base = fixed; throw error }
    }

    /// A tunnel can return HTTP 200 with HTML. Never acknowledge that as a saved preference/token.
    /// 204 is the only accepted empty write response; JSON writes must explicitly return {"ok":true}.
    static func validate(_ data: Data, _ response: URLResponse, acknowledgement: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        let status = http.statusCode
        let html = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("html")
            || String(data: data.prefix(256), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") == true
        let message = html ? nil : (try? JSONDecoder().decode(ServerError.self, from: data))?.error
        // Preserve actionable provider/account errors (covered by the existing PLAN_LIMIT regression).
        if message == "PLAN_LIMIT" { throw APIError.server("PLAN_LIMIT") }
        if status == 429 || status >= 500 || html { throw APIError.temporary(message ?? L.s("الخادم غير متاح مؤقتاً، جرّب بعد شوي")) }
        guard (200..<300).contains(status) else { throw APIError.server(message ?? "HTTP \(status)") }
        if let message, !message.isEmpty { throw APIError.server(message) }
        if acknowledgement {
            if status == 204 { return }
            struct Ack: Decodable { var ok: Bool }
            guard let ack = try? JSONDecoder().decode(Ack.self, from: data), ack.ok else { throw APIError.badResponse }
        }
    }
}


/// Phase timings only. Never log endpoints, payloads, headers, addresses or certificates.
private final class AnalystTransportMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let log = Logger(subsystem: "ae.barq.transport", category: "analyst")
        log.info("POST metrics totalMs=\(Int(metrics.taskInterval.duration * 1000), privacy: .public) transactions=\(metrics.transactionMetrics.count, privacy: .public)")
        for phase in metrics.transactionMetrics {
            func milliseconds(_ start: Date?, _ end: Date?) -> Int {
                guard let start, let end else { return -1 }
                return Int(end.timeIntervalSince(start) * 1000)
            }
            log.info("POST phases dnsMs=\(milliseconds(phase.domainLookupStartDate, phase.domainLookupEndDate), privacy: .public) connectMs=\(milliseconds(phase.connectStartDate, phase.connectEndDate), privacy: .public) tlsMs=\(milliseconds(phase.secureConnectionStartDate, phase.secureConnectionEndDate), privacy: .public) firstByteMs=\(milliseconds(phase.requestEndDate, phase.responseStartDate), privacy: .public) requestStarted=\(phase.requestStartDate != nil, privacy: .public) responseStarted=\(phase.responseStartDate != nil, privacy: .public) reusedConnection=\(phase.isReusedConnection, privacy: .public)")
        }
    }
}

struct AnyEncodable: Encodable {
    let v: Encodable
    init(_ v: Encodable) { self.v = v }
    func encode(to e: Encoder) throws { try v.encode(to: e) }
}

enum APIError: LocalizedError {
    case offline, bad, badResponse, server(String), temporary(String)
    var errorDescription: String? {
        switch self {
        case .offline: return L.s("الخادم غير متاح مؤقتاً، جرّب بعد شوي")
        case .bad: return L.s("طلب غير صالح")
        case .badResponse: return L.s("لم يؤكد الخادم حفظ التغييرات، سنحاول مرة أخرى")
        case .server(let m), .temporary(let m): return m
        }
    }
}

enum Fmt {
    static var tz: TimeZone { TimeZone(identifier: UserDefaults.standard.string(forKey: "tz") ?? "Asia/Dubai") ?? .current }
    static var locale: Locale { Locale(identifier: (UserDefaults.standard.string(forKey: "lang") ?? "ar") == "en" ? "en_US" : "ar_AE") }
    static func day(_ offset: Int, from: Date = Date()) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: from.addingTimeInterval(Double(offset) * 86400))
    }
    static func dayString(_ d: Date) -> String { day(0, from: d) }
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = tz; f.locale = locale; f.dateFormat = "h:mm a"; return f.string(from: d)
    }
    static func dateLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = tz; f.locale = locale; f.dateFormat = "EEE d MMM"; return f.string(from: d)
    }
    static func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        if m < 1 { return L.s("الآن") }
        if m < 60 { return L.f("قبل %lld د", m) }
        return L.f("قبل %lld س", m / 60)
    }
}

/// In-app language lookup. `String(localized:)` follows the DEVICE language; FOTIQ lets the user pick ar/en inside the app,
/// so non-SwiftUI strings must be resolved from the chosen .lproj explicitly.
enum L {
    static var lang: String { UserDefaults.standard.string(forKey: "lang") ?? "ar" }
    static func s(_ key: String) -> String {
        if let p = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: p) {
            return b.localizedString(forKey: key, value: key, table: nil)
        }
        return key
    }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: s(key), locale: Locale(identifier: lang), arguments: args) }
    /// Arabic labels for analyst metric keys coming from the server (`nums`).
    static func metric(_ k: String) -> String {
        let ar: [String: String] = ["window": "الفترة", "sot": "على المرمى", "shots": "التسديدات", "corners": "الركنيات", "box": "داخل المنطقة",
                                    "poss": "الاستحواذ", "xg": "الأهداف المتوقعة", "score": "النتيجة", "minute": "الدقيقة", "pressure": "الضغط"]
        return s(ar[k] ?? k)
    }
}

struct ServerError: Decodable { var error: String? }

/// In-app language. SwiftUI `Text` follows the device language; the settings picker must override `Bundle.main`
/// so the string catalog (Arabic source, English translations) follows `lang` on this launch, not only after a reboot.
enum AppLanguage {
    static func code(_ raw: String?) -> String { raw == "en" ? "en" : "ar" }

    fileprivate static var strings: Bundle?
    private static var catalogs: [String: Bundle] = [:]
    private static var installed = false

    static func apply(_ raw: String?) {
        let lang = code(raw)
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        if !installed {
            // Snapshot lproj bundles before swapping the class. path(forResource:) after the swap can re-enter localizedString.
            for c in ["ar", "en"] {
                if let path = Bundle.main.path(forResource: c, ofType: "lproj"), let b = Bundle(path: path) { catalogs[c] = b }
            }
            object_setClass(Bundle.main, LocalizedMainBundle.self)
            installed = true
        }
        strings = catalogs[lang]
    }
}

@objc(FOTIQLocalizedMainBundle)
final class LocalizedMainBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let table = tableName ?? "Localizable"
        if table == "Localizable", let b = AppLanguage.strings {
            return b.localizedString(forKey: key, value: value ?? key, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

