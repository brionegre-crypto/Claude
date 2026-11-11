import SwiftUI
import WebKit

/// Renders formatted (HTML) email like Spark/Superhuman, with privacy built in:
/// remote images (tracking pixels) are blocked until you tap "Load images", page scripts never run,
/// and links open in Safari. The view sizes itself to the email's height.
struct HTMLMailView: UIViewRepresentable {
    let html: String
    let allowRemote: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let key = "\(allowRemote)|\(html.hashValue)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        web.loadHTMLString(Self.wrap(html, allowRemote: allowRemote), baseURL: nil)
    }

    static func wrap(_ html: String, allowRemote: Bool) -> String {
        let remote = allowRemote ? "https: http:" : ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid: \(remote); style-src 'unsafe-inline' \(remote); font-src data: \(remote)">
        <style>
          html, body { margin: 0; padding: 0; background: #ffffff; color: #1c1c1e;
                       font: -apple-system-body; -webkit-text-size-adjust: 100%; word-wrap: break-word; }
          img { max-width: 100% !important; height: auto !important; }
          table { max-width: 100% !important; }
          pre { white-space: pre-wrap; }
        </style></head><body>\(html)</body></html>
        """
    }

    /// True if the email tries to load anything from the internet (images, fonts, tracking pixels).
    static func hasRemoteContent(_ html: String) -> Bool {
        html.range(of: #"(src|background)\s*=\s*["']?https?://"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loadedKey = ""
        init(height: Binding<CGFloat>) { self.height = height }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                if let h = try? await webView.evaluateJavaScript("document.documentElement.scrollHeight") as? CGFloat {
                    height.wrappedValue = max(40, h)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
