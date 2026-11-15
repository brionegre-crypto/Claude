import SwiftUI
import MessageUI

// MARK: - Apple Mail handoff: open a ready-made draft in Apple's own Mail sheet (or the Mail app)
//
// For accounts you haven't connected to Keel Mail. Keel fills in the recipients, subject and text; you send it from
// Apple Mail. Apps can't read the Mail app's inbox, so this goes one way only.

struct MailHandoffDraft: Identifiable, Hashable {
    let id = UUID()
    var to: [String] = []
    var cc: [String] = []
    var subject = ""
    var body = ""
}

enum MailHandoff {
    /// mailto: link with everything filled in (used on a Mac, or when Mail isn't set up on this iPhone).
    static func url(for d: MailHandoffDraft) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = d.to.joined(separator: ",")
        var q: [URLQueryItem] = []
        if !d.cc.isEmpty { q.append(URLQueryItem(name: "cc", value: d.cc.joined(separator: ","))) }
        if !d.subject.isEmpty { q.append(URLQueryItem(name: "subject", value: d.subject)) }
        if !d.body.isEmpty { q.append(URLQueryItem(name: "body", value: d.body)) }
        c.queryItems = q.isEmpty ? nil : q
        return c.url
    }
}

struct MailHandoffSheet: View {
    let draft: MailHandoffDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if MFMailComposeViewController.canSendMail() {
                MailComposeSheet(draft: draft) { dismiss() }.ignoresSafeArea()
            } else {
                ContentUnavailableView {
                    Label("Opening Mail", systemImage: "envelope.arrow.triangle.branch")
                } description: {
                    Text("Apple Mail isn't set up inside apps on this device, so Keel opens the Mail app with your draft instead.")
                } actions: {
                    Button("Open Mail") { open() }.buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                }
                .onAppear(perform: open)
            }
        }
    }

    private func open() {
        if let u = MailHandoff.url(for: draft) { UIApplication.shared.open(u) }
    }
}

struct MailComposeSheet: UIViewControllerRepresentable {
    let draft: MailHandoffDraft
    var done: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(draft.to)
        vc.setCcRecipients(draft.cc)
        vc.setSubject(draft.subject)
        vc.setMessageBody(draft.body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if result == .sent { Task { @MainActor in Haptics.success() } }
            done()
        }
    }
}
