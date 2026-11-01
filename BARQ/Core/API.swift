import Foundation

/// Talks to the FOTIQ Node backend. The API-SPORTS key never lives in the app.
/// Base URL resolves like the web app: published config.json -> {"api": "..."}; overridable in Settings.
actor API {
    static let shared = API()
    private var base: String?
    private let session: URLSession
    /// `protocolClasses` lets unit tests inject a URLProtocol stub (offline / server error / missing data).
    init(protocolClasses: [AnyClass]? = nil, fixedBase: String? = nil) {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        c.timeoutIntervalForRequest = 20
        if let p = protocolClasses { c.protocolClasses = p; c.urlCache = nil }
        session = URLSession(configuration: c)
        base = fixedBase
    }
    private var mem: [String: (Date, Data)] = [:]

    static var configURL: String {
        UserDefaults.standard.string(forKey: "configURL")
            ?? (Bundle.main.object(forInfoDictionaryKey: "BARQConfigURL") as? String)
            ?? "https://koora-ae.surge.sh/config.json"
    }

    func resetBase() { base = nil }

    func resolveBase() async throws -> String {
        if let b = base { return b }
        if let o = UserDefaults.standard.string(forKey: "apiOverride"), !o.isEmpty { return o.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        if let b = base { return b }
        guard let url = URL(string: Self.configURL + "?t=\(Int(Date().timeIntervalSince1970))") else { throw APIError.offline }
        let (d, _) = try await session.data(from: url)
        struct C: Decodable { var api: String }
        let c = try JSONDecoder().decode(C.self, from: d)
        let b = c.api.hasSuffix("/") ? String(c.api.dropLast()) : c.api
        base = b
        return b
    }

    func get<T: Decodable>(_ path: String, maxAge: TimeInterval = 0, as: T.Type = T.self) async throws -> T {
        if maxAge > 0, let hit = mem[path], Date().timeIntervalSince(hit.0) < maxAge {
            return try JSONDecoder().decode(T.self, from: hit.1)
        }
        let b: String
        do { b = try await resolveBase() } catch { throw APIError.offline }
        guard let url = URL(string: b + path) else { throw APIError.bad }
        var req = URLRequest(url: url)
        req.setValue("1", forHTTPHeaderField: "X-Pinggy-No-Screen")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { base = nil; throw APIError.offline }
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            throw APIError.server((try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "HTTP \(h.statusCode)")
        }
        mem[path] = (Date(), data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send(_ method: String, _ path: String, body: Encodable) async throws {
        let b = try await resolveBase()
        guard let url = URL(string: b + path) else { throw APIError.bad }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Pinggy-No-Screen")
        req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        _ = try await session.data(for: req)
    }
}

struct AnyEncodable: Encodable {
    let v: Encodable
    init(_ v: Encodable) { self.v = v }
    func encode(to e: Encoder) throws { try v.encode(to: e) }
}

enum APIError: LocalizedError {
    case offline, bad, server(String)
    var errorDescription: String? {
        switch self {
        case .offline: return L.s("الخادم غير متاح مؤقتاً، جرّب بعد شوي")
        case .bad: return L.s("طلب غير صالح")
        case .server(let m): return m
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
