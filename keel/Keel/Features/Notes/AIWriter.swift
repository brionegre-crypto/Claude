import SwiftUI
import FoundationModels

// MARK: - Which model writes

/// One model you can write with: Apple Intelligence, or a provider you added your own key for.
struct WriterModel: Hashable, Identifiable {
    let provider: AIProvider
    let model: String
    var id: String { provider.rawValue + "|" + model }

    var label: String {
        switch provider {
        case .apple: "Apple Intelligence"
        case .claude:
            switch model {
            case "claude-opus-5-5": "Claude Opus"
            case "claude-sonnet-5-5": "Claude Sonnet"
            case "claude-haiku-5-5": "Claude Haiku"
            default: "Claude"
            }
        case .openai: "ChatGPT"
        case .gemini: "Gemini"
        }
    }
    var detail: String {
        switch provider {
        case .apple: "On this device. Free and private."
        case .claude:
            switch model {
            case "claude-opus-5-5": "Most capable. Best for long or careful writing."
            case "claude-sonnet-5-5": "Fast and very good. A great everyday pick."
            case "claude-haiku-5-5": "Quickest and cheapest. Good for small edits."
            default: model
            }
        case .openai, .gemini: model
        }
    }
    var icon: String {
        switch provider { case .apple: "apple.intelligence"; case .claude: "sparkle"; case .openai: "circle.hexagongrid"; case .gemini: "diamond" }
    }

    init(provider: AIProvider, model: String) { self.provider = provider; self.model = model }
    init?(id: String) {
        let p = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard let first = p.first, let prov = AIProvider(rawValue: first) else { return nil }
        self.init(provider: prov, model: p.count > 1 ? p[1] : "")
    }
}

/// Writes with whichever model you pick. Each person uses their own key (Settings → AI & Privacy);
/// Apple Intelligence needs none.
@MainActor
enum AIWriter {
    static let defaultKey = "ai.writer.default"
    static let spaceKey = "ai.writer.space"          // space on an empty line opens Ask AI

    /// Every model you can use right now.
    static var available: [WriterModel] {
        var out: [WriterModel] = []
        if AIRouter.shared.onDeviceAvailable { out.append(WriterModel(provider: .apple, model: "")) }
        guard !AIRouter.shared.privateMode else { return out }
        if DirectAI.key(for: .claude) != nil {
            let mine = DirectAI.model(for: .claude)
            var ids = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
            if !ids.contains(mine) { ids.insert(mine, at: 0) }
            out += ids.map { WriterModel(provider: .claude, model: $0) }
        }
        for p in [AIProvider.openai, .gemini] where DirectAI.key(for: p) != nil {
            out.append(WriterModel(provider: p, model: DirectAI.model(for: p)))
        }
        return out
    }

    /// Your default (Settings), or the best one you have.
    static var defaultModel: WriterModel? {
        let all = available
        if let saved = UserDefaults.standard.string(forKey: defaultKey), let m = WriterModel(id: saved), all.contains(m) { return m }
        return all.first { $0.provider == .apple } ?? all.first
    }

    static var system: String {
        """
        You are the writing assistant inside Keel, a notes app. Write clear, warm, plain English. \
        Reply with only the text to put in the page: no preamble, no "Here is…", no closing remarks. \
        Use Markdown where it helps: # headings, - bullets, 1. numbered steps, - [ ] to-dos, **bold**, and | tables |. \
        Keep paragraphs short. Follow the request's length and format exactly.
        """ + (KeelMemory.shared.context.isEmpty ? "" : "\n\nAbout the person you write for:\n" + KeelMemory.shared.context)
    }

    /// Streams the answer. Each value is the whole text so far, so a view can show it as it grows.
    static func stream(_ prompt: String, with m: WriterModel) -> AsyncThrowingStream<String, Error> {
        let sys = system
        let user = String(prompt.prefix(m.provider == .apple ? 9_000 : 60_000))
        let key = DirectAI.key(for: m.provider)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch m.provider {
                    case .apple:
                        let session = LanguageModelSession(instructions: sys)
                        let r = try await session.respond(to: user).content
                        continuation.yield(r)
                    case .claude, .openai, .gemini:
                        guard let key else { throw DirectAI.Failure.empty }
                        var text = ""
                        for try await piece in WriterStreams.pieces(m.provider, model: m.model, key: key, system: sys, user: user) {
                            text += piece
                            continuation.yield(text)
                        }
                        if text.isEmpty { throw DirectAI.Failure.empty }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole answer at once (live AI blocks, page actions).
    static func write(_ prompt: String, with m: WriterModel) async throws -> String {
        var last = ""
        for try await t in stream(prompt, with: m) { last = t }
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Streaming from each provider (server-sent events)

enum WriterStreams {
    /// Yields each new piece of text as it arrives.
    static func pieces(_ p: AIProvider, model: String, key: String, system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request(p, model: model, key: key, system: system, user: user)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 400 { break } }
                        throw DirectAI.Failure.http(code, body)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let piece = try text(in: obj, provider: p), !piece.isEmpty { continuation.yield(piece) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func request(_ p: AIProvider, model: String, key: String, system: String, user: String) throws -> URLRequest {
        var req: URLRequest
        let body: [String: Any]
        switch p {
        case .claude:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            body = ["model": model, "max_tokens": 8_192, "stream": true, "system": system,
                    "messages": [["role": "user", "content": user]]]
        case .openai:
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = ["model": model, "stream": true,
                    "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        case .gemini:
            let path = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(path):streamGenerateContent?alt=sse")!)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": user]]]]]
        case .apple:
            throw DirectAI.Failure.empty
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// The text inside one streamed event, if any.
    static func text(in obj: [String: Any], provider p: AIProvider) throws -> String? {
        switch p {
        case .claude:
            if obj["type"] as? String == "error" {
                throw DirectAI.Failure.http(0, ((obj["error"] as? [String: Any])?["message"] as? String) ?? "error")
            }
            if obj["type"] as? String == "message_delta", (obj["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                throw DirectAI.Failure.refused
            }
            guard obj["type"] as? String == "content_block_delta", let d = obj["delta"] as? [String: Any],
                  d["type"] as? String == "text_delta" else { return nil }
            return d["text"] as? String
        case .openai:
            return ((obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String
        case .gemini:
            let parts = (((obj["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            return parts.compactMap { $0["text"] as? String }.joined()
        case .apple:
            return nil
        }
    }
}

// MARK: - What you can ask for

struct AIAction: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let instruction: String

    /// For selected text (or the line you're on).
    static let edits: [AIAction] = [
        .init(id: "improve", title: "Improve writing", icon: "wand.and.stars", instruction: "Improve the writing: clearer, smoother, same meaning and voice."),
        .init(id: "grammar", title: "Fix spelling & grammar", icon: "checkmark.seal", instruction: "Fix spelling, grammar and punctuation only. Change nothing else."),
        .init(id: "shorter", title: "Make shorter", icon: "arrow.down.right.and.arrow.up.left", instruction: "Make it about half as long, keeping what matters."),
        .init(id: "longer", title: "Make longer", icon: "arrow.up.left.and.arrow.down.right", instruction: "Expand it with useful detail, about twice as long."),
        .init(id: "simpler", title: "Simplify", icon: "text.badge.minus", instruction: "Rewrite in simple, plain words anyone can follow."),
        .init(id: "friendly", title: "Friendlier tone", icon: "face.smiling", instruction: "Rewrite in a warmer, friendlier tone."),
        .init(id: "professional", title: "More professional", icon: "briefcase", instruction: "Rewrite in a confident, professional tone."),
        .init(id: "list", title: "Turn into a list", icon: "list.bullet", instruction: "Turn this into a tidy bulleted list."),
        .init(id: "table", title: "Turn into a table", icon: "tablecells", instruction: "Turn this into a Markdown table with sensible columns."),
        .init(id: "steps", title: "Break into steps", icon: "list.number", instruction: "Turn this into small, numbered, doable steps."),
        .init(id: "explain", title: "Explain this", icon: "questionmark.circle", instruction: "Explain this simply, in a short paragraph, for someone new to it."),
    ]

    /// For the whole page.
    static let page: [AIAction] = [
        .init(id: "summary", title: "Summarize page", icon: "text.line.first.and.arrowtriangle.forward", instruction: "Summarize this page in 3 to 5 short bullets."),
        .init(id: "tldr", title: "TL;DR at the top", icon: "text.insert", instruction: "Write a one or two sentence TL;DR of this page. Plain text, no heading."),
        .init(id: "actions", title: "Find action items", icon: "checklist", instruction: "List every action item on this page as Markdown to-dos (- [ ] …), with who and when if the page says. If there are none, reply with only: none"),
        .init(id: "title", title: "Suggest a title", icon: "textformat", instruction: "Suggest one short, specific title for this page. Reply with only the title, no quotes."),
        .init(id: "outline", title: "Add structure", icon: "list.bullet.indent", instruction: "Rewrite this page with clear headings and lists, keeping every fact. Don't add new information."),
        .init(id: "questions", title: "Open questions", icon: "questionmark.bubble", instruction: "List the open questions and gaps this page leaves, as short bullets."),
        .init(id: "continue", title: "Continue writing", icon: "text.append", instruction: "Continue this page naturally with one or two short paragraphs in the same voice. Reply with only the new text."),
    ]

    /// Ideas shown in the Ask AI box.
    static let starters: [String] = [
        "Brainstorm ideas for…", "Draft an email about…", "Write a plan for…", "Make a checklist for…",
        "Pros and cons of…", "Write an agenda for…", "Explain like I'm new:", "Make a table comparing…",
    ]
}

// MARK: - Model picker (one chip, switch per request)

struct WriterModelChip: View {
    @Binding var choice: WriterModel?
    var body: some View {
        let all = AIWriter.available
        Menu {
            ForEach(all) { m in
                Button { choice = m } label: {
                    Label { Text(m.label); Text(m.detail) } icon: { Image(systemName: choice == m ? "checkmark" : m.icon) }
                }
            }
            if all.count < 2 {
                Divider()
                Text("Add your own Claude, ChatGPT or Gemini key in Settings → AI & Privacy to choose more models.")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: choice?.icon ?? "sparkles")
                Text(choice?.label ?? "No AI available").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(DS.Palette.elevated, in: Capsule())
        }
        .accessibilityLabel("Model: \(choice?.label ?? "none")")
    }
}

// MARK: - Ask AI sheet (ask anywhere, edit a selection, whole-page actions)

struct AIWriteRequest: Identifiable {
    enum Mode { case ask, edit, page }
    let id = UUID()
    var mode: Mode
    var blockId: UUID?             // where the answer goes
    var source: String = ""        // the selected text (edit) or nothing
    var preset: AIAction?          // a one-tap action to run right away
    var range: Range<String.Index>?
}

struct AIWriteSheet: View {
    let request: AIWriteRequest
    let pageTitle: String
    let pageText: String
    /// Called with the final text and whether it should replace the selection.
    var onDone: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var output = ""
    @State private var working = false
    @State private var error: String?
    @State private var choice: WriterModel?
    @State private var job: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if request.mode == .edit, !request.source.isEmpty {
                        Text(request.source).font(.callout).foregroundStyle(DS.Palette.inkSoft).lineLimit(4)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if output.isEmpty && !working {
                        inputArea
                    } else {
                        resultArea
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { job?.cancel(); dismiss() } }
                ToolbarItem(placement: .principal) { WriterModelChip(choice: $choice) }
            }
            .onAppear {
                if choice == nil { choice = AIWriter.defaultModel }
                if let p = request.preset { prompt = p.instruction; run() } else { focused = true }
            }
            .onDisappear { job?.cancel() }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch request.mode { case .ask: "Ask AI"; case .edit: "Edit with AI"; case .page: request.preset?.title ?? "Page AI" }
    }

    @ViewBuilder private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(request.mode == .edit ? "Tell AI what to change…" : "Ask AI to write anything…", text: $prompt, axis: .vertical)
                .focused($focused)
                .lineLimit(1...6)
                .padding(10)
                .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: 12))
                .onSubmit(run)
            Button(action: run) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || choice == nil)
                .accessibilityLabel("Write")
        }
        if choice == nil {
            Text("No AI is available yet. Turn on Apple Intelligence in iPhone Settings, or add your own Claude, ChatGPT or Gemini key in Settings → AI & Privacy.")
                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        let ideas: [(String, String)] = request.mode == .edit
            ? AIAction.edits.map { ($0.title, $0.instruction) }
            : AIAction.starters.map { ($0, $0) } + AIAction.page.prefix(3).map { ($0.title, $0.instruction) }
        AIChipRow(items: ideas.map(\.0)) { i in
            let pick = ideas[i]
            if pick.1.hasSuffix("…") || pick.1.hasSuffix(":") { prompt = String(pick.1.dropLast()) + " "; focused = true }
            else { prompt = pick.1; run() }
        }
    }

    @ViewBuilder private var resultArea: some View {
        if !prompt.isEmpty { Text(prompt).font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2) }
        Group {
            if output.isEmpty { HStack { ProgressView(); Text("Writing…").foregroundStyle(DS.Palette.inkSoft) } }
            else { Text(rendered).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(12)
        .background(DS.Palette.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.12), value: output.count / 40)
        if !working && !output.isEmpty {
            HStack {
                if request.mode == .edit {
                    Button { finish(replace: true) } label: { Label("Replace", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
                    Button { finish(replace: false) } label: { Label("Insert below", systemImage: "text.insert") }.buttonStyle(.bordered)
                } else {
                    Button { finish(replace: false) } label: { Label("Insert", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
                }
                Button { run() } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) { output = "" } label: { Image(systemName: "trash") }.accessibilityLabel("Discard")
            }
            .font(.callout)
        } else if working {
            Button("Stop") { job?.cancel(); working = false }.font(.callout)
        }
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: output, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(output)
    }

    private func run() {
        guard let m = choice, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        job?.cancel()
        output = ""; error = nil; working = true; focused = false
        let full = AIWriter.prompt(for: request.mode, instruction: prompt, source: request.source, title: pageTitle, page: pageText)
        job = Task {
            do {
                for try await t in AIWriter.stream(full, with: m) { output = t }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            working = false
            Haptics.tap()
        }
    }

    private func finish(replace: Bool) {
        onDone(output.trimmingCharacters(in: .whitespacesAndNewlines), replace)
        Haptics.success()
        dismiss()
    }
}

extension AIWriter {
    /// Builds the request: your instruction plus the page around it.
    static func prompt(for mode: AIWriteRequest.Mode, instruction: String, source: String, title: String, page: String) -> String {
        let pageCtx = "PAGE TITLE: \(title.isEmpty ? "Untitled" : title)\nPAGE:\n\(page.prefix(20_000))"
        switch mode {
        case .edit:
            return "\(instruction)\n\nReply with only the rewritten text.\n\nTEXT:\n\(source)\n\nFor context only (don't rewrite it):\n\(pageCtx.prefix(6_000))"
        case .page:
            return "\(instruction)\n\n\(pageCtx)"
        case .ask:
            return "\(instruction)\n\nThis will be added to the page below; match its style and don't repeat what's already there.\n\n\(pageCtx.prefix(8_000))"
        }
    }
}

/// Sideways-scrolling row of tappable suggestion chips.
struct AIChipRow: View {
    let items: [String]
    var tap: (Int) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    Button { tap(i) } label: {
                        Text(items[i]).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(DS.Palette.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - AI block: stays live, refresh any time

/// A block that keeps an instruction ("Summarize this page", "List open questions") and its latest answer.
/// text = instruction, body = last answer, refId = model id, rows[0][0] = when it last ran.
struct AIBlockView: View {
    @Binding var block: NoteBlock
    let pageTitle: String
    let pageText: String

    @State private var choice: WriterModel?
    @State private var working = false
    @State private var error: String?
    @State private var editingPrompt = false
    @State private var draft = ""

    private var lastRun: Date? { block.rows?.first?.first.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(DS.Palette.accent)
                if editingPrompt || block.text.isEmpty {
                    TextField("What should this block always show? e.g. Summarize this page", text: $draft)
                        .font(.caption.weight(.medium))
                        .onSubmit { block.text = draft; editingPrompt = false; refresh() }
                } else {
                    Text(block.text).font(.caption.weight(.medium)).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        .onTapGesture { draft = block.text; editingPrompt = true }
                }
                Spacer(minLength: 4)
                WriterModelChip(choice: Binding(get: { choice }, set: { choice = $0; block.refId = $0?.id }))
                Button { refresh() } label: {
                    if working { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.plain).disabled(working || block.text.isEmpty)
                .accessibilityLabel("Refresh")
            }
            if let body = block.body, !body.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            let heading = line.hasPrefix("#")
                            let shown = heading ? String(line.drop { $0 == "#" || $0 == " " }) : line
                            Text((try? AttributedString(markdown: shown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(shown))
                                .font(heading ? .headline : .callout)
                        }
                    }
                }
                .textSelection(.enabled)
            } else if !working && !block.text.isEmpty {
                Text("Tap ↻ to write this.").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
            if let lastRun {
                Text("Updated \(lastRun.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(12)
        .background(DS.Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.Palette.accent.opacity(0.18)))
        .task {
            choice = block.refId.flatMap(WriterModel.init(id:)).flatMap { m in AIWriter.available.contains(m) ? m : nil } ?? AIWriter.defaultModel
            if block.text.isEmpty { editingPrompt = true; return }
            // Stays fresh: rewrites itself when you open the page if it's more than 6 hours old.
            if (block.body ?? "").isEmpty || (lastRun.map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true) { refresh() }
        }
    }

    private func refresh() {
        guard let m = choice, !block.text.isEmpty, !working else { return }
        working = true; error = nil
        let page = pageText
        let full = AIWriter.prompt(for: .page, instruction: block.text, source: "", title: pageTitle, page: page)
        Task {
            do {
                let r = try await AIWriter.write(full, with: m)
                block.body = r
                block.rows = [[String(Date().timeIntervalSince1970)]]
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

// MARK: - Settings

struct AIWriterSettings: View {
    @AppStorage(AIWriter.defaultKey) private var defaultId = ""
    @AppStorage(AIWriter.spaceKey) private var spaceOpens = true

    var body: some View {
        let all = AIWriter.available
        Section {
            Picker("Default writing model", selection: Binding(get: { AIWriter.defaultModel?.id ?? "" }, set: { defaultId = $0 })) {
                ForEach(all) { Text($0.label).tag($0.id) }
                if all.isEmpty { Text("None available").tag("") }
            }
            Toggle("Space on an empty line asks AI", isOn: $spaceOpens)
        } header: { Text("AI Writing in Notes") } footer: {
            Text("Ask AI in any page with / then “Ask AI”, or space on an empty line. Select text to edit it with AI, add a live AI block, or use ✨ for page actions. You can switch models on each request. Claude, ChatGPT and Gemini use your own key and bill you per use.")
        }
    }
}
