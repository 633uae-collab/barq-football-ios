import Foundation

struct AnalystContext: Codable {
    var fixtureId: Int?
    var teamIds: [Int]?
    var playerIds: [Int]?
}
struct AnalystReply: Codable {
    var answer: String
    var model: String
    var fetchedAt: Double
    var generatedAt: Double
    var context: AnalystContext?
    var sources: [AnalystSource]?
    var responseKind: AnalystResponseKind? { AnalystResponseKind(rawValue: model) }
    var sourceNames: String? {
        let names = (sources ?? []).compactMap(\.displayName)
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: " · ")
    }
}

enum AnalystResponseKind: String, CaseIterable {
    case groq = "openai/gpt-oss-120b"
    case providerData = "verified-provider-data"
    case linkDiscovery = "unverified-link-discovery"

    func label(english: Bool) -> String {
        switch self {
        case .groq: return english ? "AI analysis · Groq" : "تحليل بالذكاء الاصطناعي · Groq"
        case .providerData: return english ? "Direct provider data · API-Football" : "بيانات مباشرة من المزوّد · API-Football"
        case .linkDiscovery: return english ? "Unverified discovery links · GDELT" : "روابط اكتشاف غير مؤكدة · GDELT"
        }
    }
}
struct AnalystSource: Codable {
    var name: String?
    var path: String?
    var url: String?
    var revision: Int?
    var modifiedAt: String?
    var fetchedAt: Double?
    var displayName: String? {
        if let name, !name.isEmpty { return name }
        return path?.hasPrefix("/") == true ? "API-Football" : nil
    }
    var link: URL? {
        guard let url, let value = URL(string: url), value.scheme == "https", value.host != nil else { return nil }
        return value
    }
}
struct AnalystChatError: LocalizedError {
    let code: String
    let retryAfter: Int?
    var errorDescription: String? {
        let en = L.lang == "en"
        switch code {
        case "AI_FREE_QUOTA_REACHED", "PLAN_LIMIT", "LOCAL_REQUEST_BUDGET":
            if let retryAfter, retryAfter > 0 {
                return en ? "The free usage limit has been reached. Try again in \(retryAfter) seconds. No paid usage is enabled." : "وصلنا لحد الاستخدام المجاني. حاول بعد \(retryAfter) ثانية. لن يتم تفعيل استخدام مدفوع."
            }
            return en ? "The free usage limit has been reached. The provider did not specify a reset time. Please try later; no paid usage is enabled." : "وصلنا لحد الاستخدام المجاني. مزوّد الخدمة لم يحدد وقت تجدد الحصة. حاول لاحقاً؛ لن يتم تفعيل استخدام مدفوع."
        case "AI_BUSY": return en ? "The analyst is busy. Please try again shortly." : "المحلل مشغول حالياً، حاول بعد قليل."
        case "AI_CHAT_DISABLED": return en ? "AI chat is not enabled on the server yet." : "محادثة الذكاء الاصطناعي غير مفعّلة على الخادم حالياً."
        case "AI_FACT_CHECK_FAILED", "AI_INCOMPLETE_RESPONSE": return en ? "The answer could not be verified or was incomplete. It was not displayed. You can send a new request." : "تعذّر التحقق من الإجابة أو كانت غير مكتملة، لذلك لم نعرضها. تقدر ترسل طلباً جديداً."
        default: return en ? "Unable to complete the analysis. Check your connection and try again." : "تعذّر إكمال التحليل. تأكد من الاتصال وحاول مرة أخرى."
        }
    }
}

struct AnalystHistoryMessage: Codable { let role: String; let content: String }

struct AnalystWelcome: Decodable {
    let text: String
    let dynamic: Bool
    let expiresAt: Double
    static func fallback(english: Bool) -> String {
        english ? "Every football question on your mind, answered here." : "كل سؤال في بالك عن الكورة، جوابه هني."
    }
    func displayText(at date: Date, english: Bool) -> String {
        expiresAt > date.timeIntervalSince1970 * 1000 ? text : Self.fallback(english: english)
    }
}

enum AnalystNetworkFailure {
    // Resolve known transport errors without Foundation's localized-description
    // resource lookup on the UI actor. Never automatically resend a chat POST.
    static func message(for error: Error, english: Bool) -> String? {
        let value = error as NSError
        guard value.domain == NSURLErrorDomain else { return nil }
        let suffix = english
            ? " Your question remains in this conversation. It was not resent automatically."
            : " سؤالك باقٍ في هذه المحادثة، ولم نُعد إرساله تلقائياً."
        switch value.code {
        case NSURLErrorNetworkConnectionLost:
            return (english ? "The connection was interrupted before a complete answer arrived." : "انقطع الاتصال قبل وصول الإجابة كاملة.") + suffix
        case NSURLErrorTimedOut:
            return (english ? "The answer did not arrive within the connection time limit." : "لم تصل الإجابة خلال مهلة الاتصال.") + suffix
        case NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return (english ? "The analysis service could not be reached." : "تعذّر الوصول إلى خدمة التحليل.") + suffix
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid:
            return (english ? "A secure connection could not be established." : "تعذّر إنشاء اتصال آمن.") + suffix
        default: return nil
        }
    }
}

