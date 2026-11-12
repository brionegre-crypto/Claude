import Foundation
import EventKit

/// Background from the web for meetings: the companies people work at (from their email domains), links in
/// the invite and agenda, and Wikipedia for topics and acronyms that come up. With your own AI key, that
/// provider also runs a live web search. Off in Private mode. People's names are never sent anywhere.
@MainActor
enum WebContext {
    static let onKey = "web.context.on"
    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: onKey) as? Bool ?? true) && !AIRouter.shared.privateMode
    }

    private static let personalDomains: Set<String> = ["gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "outlook.com",
                                                      "hotmail.com", "live.com", "msn.com", "yahoo.com", "ymail.com", "aol.com",
                                                      "proton.me", "protonmail.com", "gmx.com", "zoho.com", "fastmail.com", "hey.com"]
    nonisolated private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral          // no cookies, no cache left behind
        c.timeoutIntervalForRequest = 8
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone) Keel"]
        return URLSession(configuration: c)
    }()

    struct Result { var text: String; var sources: [String] }

    /// Company domains of the other attendees.
    static func domains(_ event: EKEvent?) -> [String] {
        let emails = (event?.attendees ?? []).filter { !$0.isCurrentUser }
            .map { $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased() }
        var seen = Set<String>()
        let ds = emails.compactMap { $0.split(separator: "@").last.map(String.init) }
            .filter { !personalDomains.contains($0) && seen.insert($0).inserted }
        return Array(ds.prefix(3))
    }

    /// Links in the invite (URL field and agenda text).
    static func links(_ event: EKEvent?) -> [URL] {
        var urls: [URL] = []
        if let u = event?.url { urls.append(u) }
        let text = (event?.notes ?? "") + " " + (event?.location ?? "")
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            urls += det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
        }
        // Video-call links say nothing useful about the meeting.
        let skip = ["zoom.us", "meet.google", "teams.microsoft", "webex", "facetime", "whereby", "gotomeeting"]
        return Array(urls.filter { u in u.scheme?.hasPrefix("http") == true && !skip.contains { (u.host() ?? "").contains($0) } }.prefix(3))
    }

    /// Topics worth looking up: acronyms and capitalized phrases that recur in the transcript or appear in the title.
    static func topics(title: String, transcript: String) -> [String] {
        let text = title + " " + transcript
        var counts: [String: Int] = [:]
        if let re = try? NSRegularExpression(pattern: #"\b([A-Z]{2,6}|[A-Z][a-z]+(?:\s[A-Z][a-z]+){1,2})\b"#) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text) { counts[String(text[r]), default: 0] += 1 }
            }
        }
        let common: Set<String> = ["OK", "AM", "PM", "US", "I", "TV", "FYI", "ASAP", "EOD", "Thank You", "Good Morning", "Next Week", "Last Week"]
        return counts.filter { $0.value >= 2 || title.contains($0.key) }.keys
            .filter { !common.contains($0) }
            .sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
            .prefix(3).map { $0 }
    }

    static func gather(event: EKEvent?, title: String, transcript: String, deep: Bool) async -> Result {
        guard enabled else { return Result(text: "", sources: []) }
        let ds = domains(event), ls = links(event), ts = topics(title: title, transcript: transcript)
        var lines: [String] = [], sources: [String] = []

        await withTaskGroup(of: (String, String)?.self) { group in
            for d in ds { group.addTask { await page(URL(string: "https://\(d)")!).map { ("Company \(d): \($0)", d) } } }
            for u in ls { group.addTask { await page(u).map { ("Linked page \(u.host() ?? ""): \($0)", u.host() ?? "link") } } }
            for t in ts { group.addTask { await wikipedia(t).map { ("\(t) (Wikipedia): \($0)", "Wikipedia: \(t)") } } }
            for await item in group {
                if let item { lines.append(item.0); sources.append(item.1) }
            }
        }

        // Deeper: a live web search through the person's own AI provider, about companies and topics only.
        if deep && DirectAI.isConfigured && (!ds.isEmpty || !ts.isEmpty) {
            let q = "Meeting: \(title). Companies: \(ds.joined(separator: ", ")). Topics: \(ts.joined(separator: ", ")). " +
                    "Give 4 to 6 short bullet points of factual, recent background that would help someone follow this meeting."
            if let r = try? await DirectAI.research(system: "You research background for meetings. Be brief, factual and current. No preamble.", question: q) {
                lines.append("Web research: \(r.prefix(900))")
                sources.append("web search via \(DirectAI.provider.name)")
            }
        }
        return Result(text: String(lines.joined(separator: "\n").prefix(1_400)), sources: sources)
    }

    /// Title, description and the first readable text of a page.
    nonisolated static func page(_ url: URL) async -> String? {
        guard let response = try? await session.data(from: url),
              ((response.1 as? HTTPURLResponse)?.statusCode ?? 0) < 400 else { return nil }
        let data = response.0
        guard let html = String(data: data.prefix(400_000), encoding: .utf8) ?? String(data: data.prefix(400_000), encoding: .isoLatin1) else { return nil }
        func capture(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m.range(at: 1), in: html) else { return nil }
            return decode(String(html[r]))
        }
        let title = capture(#"<title[^>]*>(.*?)</title>"#) ?? ""
        let desc = capture(#"<meta[^>]+(?:name|property)=["'](?:og:)?description["'][^>]+content=["']([^"']+)"#)
            ?? capture(#"<meta[^>]+content=["']([^"']+)["'][^>]+(?:name|property)=["'](?:og:)?description"#) ?? ""
        let body = decode(html
            .replacingOccurrences(of: #"<script.*?</script>|<style.*?</style>|<nav.*?</nav>|<header.*?</header>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let summary = [title, desc, String(body.prefix(desc.isEmpty ? 300 : 120))].filter { !$0.isEmpty }.joined(separator: " — ")
        return summary.isEmpty ? nil : String(summary.prefix(380))
    }

    nonisolated static func wikipedia(_ term: String) async -> String? {
        let t = term.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(t)"),
              let response = try? await session.data(from: url), (response.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              obj["type"] as? String == "standard", let extract = obj["extract"] as? String, !extract.isEmpty else { return nil }
        return String(extract.prefix(300))
    }

    nonisolated private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
