import UIKit
import SwiftUI

/// Share a note as Markdown or as a PDF.
@MainActor
enum NoteExport {
    static func markdown(_ n: Note) -> String {
        var out = "# \(n.title)\n\n"
        for b in n.blocks {
            switch b.kind {
            case .heading: out += "## \(b.text)\n\n"
            case .heading2: out += "### \(b.text)\n\n"
            case .heading3: out += "#### \(b.text)\n\n"
            case .numbered: out += "1. \(b.text)\n"
            case .toggle: out += "<details><summary>\(b.text)</summary>\n\n\(b.body ?? "")\n\n</details>\n\n"
            case .callout: out += "> \(b.icon ?? "💡") \(b.text)\n\n"
            case .code: out += "```\(b.lang ?? "")\n\(b.text)\n```\n\n"
            case .bookmark: if let u = b.refId { out += "[\(b.text.isEmpty ? u : b.text)](\(u))\n\n" }
            case .table:
                if let rows = b.rows, let head = rows.first {
                    out += "| " + head.joined(separator: " | ") + " |\n|" + head.map { _ in " --- |" }.joined() + "\n"
                    for r in rows.dropFirst() { out += "| " + r.joined(separator: " | ") + " |\n" }
                    out += "\n"
                }
            case .todo: out += "- [\(b.checked ? "x" : " ")] \(b.text)\n"
            case .bullet: out += "- \(b.text)\n"
            case .quote: out += "> \(b.text)\n\n"
            case .divider: out += "\n---\n\n"
            case .image: if !b.text.isEmpty { out += "_[Image: \(b.text)]_\n\n" }
            default: if !b.text.isEmpty { out += "\(b.text)\n\n" }
            }
        }
        return out
    }

    private static func fileURL(_ n: Note, ext: String) -> URL {
        let safe = n.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined()
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Note" : safe).\(ext)")
    }

    static func markdownFile(_ n: Note) -> URL? {
        let url = fileURL(n, ext: "md")
        return (try? markdown(n).write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    static func pdfFile(_ n: Note) -> URL? {
        let text = NSMutableAttributedString()
        func add(_ s: String, _ font: UIFont, color: UIColor = .label, after: CGFloat = 6) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacing = after
            text.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
        }
        add(n.title, .systemFont(ofSize: 24, weight: .bold), after: 12)
        add(n.updatedAt.formatted(date: .long, time: .shortened), .systemFont(ofSize: 10), color: .secondaryLabel, after: 14)
        for b in n.blocks {
            switch b.kind {
            case .heading: add(b.text, .systemFont(ofSize: 17, weight: .semibold), after: 8)
            case .heading2: add(b.text, .systemFont(ofSize: 15, weight: .semibold), after: 6)
            case .heading3: add(b.text, .systemFont(ofSize: 13, weight: .semibold), after: 4)
            case .numbered: add("–  \(b.text)", .systemFont(ofSize: 12))
            case .toggle: add("▸ \(b.text)", .systemFont(ofSize: 12, weight: .medium)); if let body = b.body, !body.isEmpty { add(body, .systemFont(ofSize: 12), color: .secondaryLabel) }
            case .callout: add("\(b.icon ?? "💡") \(b.text)", .systemFont(ofSize: 12))
            case .code: add(b.text, .monospacedSystemFont(ofSize: 11, weight: .regular))
            case .bookmark: if let u = b.refId { add(u, .systemFont(ofSize: 12), color: .link) }
            case .table: for r in b.rows ?? [] { add(r.joined(separator: "   |   "), .systemFont(ofSize: 11)) }
            case .todo: add("\(b.checked ? "☑︎" : "☐") \(b.text)", .systemFont(ofSize: 12))
            case .bullet: add("•  \(b.text)", .systemFont(ofSize: 12))
            case .quote: add(b.text, .italicSystemFont(ofSize: 12), color: .secondaryLabel)
            case .divider: add("—————", .systemFont(ofSize: 12), color: .tertiaryLabel)
            default: if !b.text.isEmpty { add(b.text, .systemFont(ofSize: 12)) }
            }
        }
        let formatter = UISimpleTextPrintFormatter(attributedText: text)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)              // US Letter
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 54, dy: 54), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let url = fileURL(n, ext: "pdf")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

struct ExportFile: Identifiable { let url: URL; var id: URL { url } }

/// The system share sheet for a file (AirDrop, Files, Mail, Messages…).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
