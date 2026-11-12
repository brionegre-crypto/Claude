import SwiftUI
import SwiftData
import Speech
import AVFoundation
import EventKit
import FoundationModels

/// Record a meeting, transcribe it on-device as people talk, then write up a summary,
/// decisions and action items with Apple Intelligence. Saved as a note linked to the calendar event.

/// The audio thread feeds buffers here (kept off the main actor on purpose).
private final class AudioFeed: @unchecked Sendable {
    var request: SFSpeechAudioBufferRecognitionRequest?
}

@MainActor @Observable
final class MeetingRecorder {
    var transcript = ""
    var isRecording = false
    var startedAt: Date?
    var error: String?

    private var finalized = ""
    private let engine = AVAudioEngine()
    private let feed = AudioFeed()
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func start(resume: Bool = false) async {
        error = nil
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = "Keel needs Microphone and Speech Recognition access. Turn them on in Settings → Keel."
            return
        }
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                feed.request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Couldn't start recording: \(error.localizedDescription)"
            return
        }
        if resume {
            finalized = transcript.isEmpty ? "" : transcript + " "
        } else {
            transcript = ""; finalized = ""
            startedAt = Date()
        }
        isRecording = true
        if startedAt == nil { startedAt = Date() }
        beginRecognition()
    }

    private func beginRecognition() {
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // private, no time limit
        feed.request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = err != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = self.finalized + text }
                if isFinal || failed {
                    // Recognition segments end on long pauses; keep going until the user stops.
                    self.finalized = self.transcript.isEmpty ? "" : self.transcript + " "
                    if self.isRecording {
                        try? await Task.sleep(for: .milliseconds(300))
                        if self.isRecording { self.beginRecognition() }
                    }
                }
            }
        }
    }

    func stop() {
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        feed.request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Write-up

struct MeetingWriteUp {
    struct Topic { var title: String; var points: [String] }
    struct Action { var task: String; var owner: String; var due: Date? }
    var summary: String
    var topics: [Topic] = []
    var decisions: [String] = []
    var actions: [Action] = []
    var questions: [String] = []
    var enhancedNotes: [String] = []
}

@Generable
struct MeetingTopicOut {
    @Guide(description: "Short name for a topic that was discussed")
    var title: String
    @Guide(description: "2 to 4 specific details about it: names, numbers, dates, reasons, concerns raised, options compared", .maximumCount(5))
    var points: [String]
}

@Generable
struct MeetingActionOut {
    @Guide(description: "The follow-up action, starting with a verb")
    var task: String
    @Guide(description: "Name of the person who will do it, or empty if nobody was named")
    var owner: String
    @Guide(description: "Due date as YYYY-MM-DD if one was said, otherwise empty")
    var due: String
}

@Generable
struct MeetingPartOut {
    @Guide(description: "Two or three sentences on what this part of the meeting covered")
    var summary: String
    @Guide(description: "Topics discussed, in order", .maximumCount(5))
    var topics: [MeetingTopicOut]
    @Guide(description: "Decisions that were actually agreed", .maximumCount(6))
    var decisions: [String]
    @Guide(description: "Concrete follow-ups someone committed to", .maximumCount(8))
    var actions: [MeetingActionOut]
    @Guide(description: "Questions raised but not answered", .maximumCount(4))
    var questions: [String]
}

@Generable
struct EnhancedNotesOut {
    @Guide(description: "Each of the user's own notes, in the same order, rewritten as one fuller sentence with specific details from the transcript. Keep their meaning; never invent.", .maximumCount(20))
    var notes: [String]
}

/// Everything Keel knows that helps it understand this meeting.
@MainActor
enum MeetingContext {
    static func build(event: EKEvent?, title: String, ctx: ModelContext) -> (text: String, sources: [String]) {
        var lines: [String] = [], sources: [String] = []
        if let e = event {
            let people = (e.attendees ?? []).compactMap(\.name)
            lines.append("Meeting: \(e.title ?? title) on \(e.startDate.formatted(date: .abbreviated, time: .shortened)). Attendees: \(people.isEmpty ? "unknown" : people.joined(separator: ", ")).")
            if let agenda = e.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !agenda.isEmpty {
                lines.append("Agenda / invite notes: \(agenda.prefix(400))")
                sources.append("the invite's agenda")
            }
            let pack = MeetingPrep.build(e, ctx: ctx)
            if !pack.emails.isEmpty {
                lines.append("Recent emails with attendees: " + pack.emails.prefix(3).map { "\($0.fromName): \($0.subject)" }.joined(separator: "; "))
                sources.append("\(min(3, pack.emails.count)) recent emails")
            }
            if !pack.promises.isEmpty {
                lines.append("The user promised attendees: " + pack.promises.prefix(3).map(\.promise).joined(separator: "; "))
                sources.append("your promises")
            }
        }
        // The previous meeting with the same name: what was decided and still open.
        let key = (event?.title ?? title).lowercased()
        let notes = (try? ctx.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        if !key.isEmpty, let prev = notes.first(where: { $0.title.lowercased() == key && !$0.isLocked && $0.updatedAt < Date().addingTimeInterval(-3_600) }) {
            let open = prev.blocks.filter { $0.kind == .todo && !$0.checked && !$0.text.isEmpty }.prefix(5).map(\.text)
            lines.append("Previous meeting (\(prev.updatedAt.formatted(date: .abbreviated, time: .omitted))): \((prev.aiSummary ?? prev.plainText).prefix(350))" +
                         (open.isEmpty ? "" : " Still-open action items: " + open.joined(separator: "; ")))
            sources.append("last meeting's notes")
        }
        let memory = KeelMemory.shared.facts.suffix(6)
        if !memory.isEmpty { lines.append("About the user: " + memory.joined(separator: "; ")) }
        return (String(lines.joined(separator: "\n").prefix(1_600)), sources)
    }
}

enum MeetingAI {
    /// Context-aware write-up. Long transcripts are read in parts, then merged, so nothing at the end is lost.
    @MainActor
    static func writeUp(_ transcript: String, context: String, myNotes: String) async -> MeetingWriteUp {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let mine = myNotes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")) }.filter { !$0.isEmpty }
        guard AIRouter.shared.onDeviceAvailable, text.count > 40 else {
            return MeetingWriteUp(summary: String(text.prefix(400)), enhancedNotes: mine)
        }
        let instructions = """
        You write meeting notes like an excellent chief of staff. Use the context to understand names, projects and acronyms, \
        and to notice follow-ups from last time, but only report what was said in this transcript. Be specific: keep numbers, \
        names, dates and reasons. Never invent.
        CONTEXT:
        \(context)
        """
        // 1. Read the transcript in parts.
        var parts: [MeetingPartOut] = []
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: 5_000, limitedBy: text.endIndex) ?? text.endIndex
            let session = LanguageModelSession(instructions: instructions)
            if let p = try? await session.respond(to: "Transcript part:\n\(text[i..<j])", generating: MeetingPartOut.self).content {
                parts.append(p)
            }
            i = j
        }
        guard !parts.isEmpty else {
            return MeetingWriteUp(summary: await AIRouter.shared.summarize(String(text.prefix(6_000))) ?? String(text.prefix(400)), enhancedNotes: mine)
        }
        // 2. Merge.
        func unique(_ xs: [String]) -> [String] { var seen = Set<String>(); return xs.filter { seen.insert($0.lowercased()).inserted } }
        var w = MeetingWriteUp(summary: parts.map(\.summary).joined(separator: " "))
        w.topics = parts.flatMap(\.topics).map { .init(title: $0.title, points: $0.points) }
        w.decisions = unique(parts.flatMap(\.decisions))
        w.questions = unique(parts.flatMap(\.questions))
        var seenActions = Set<String>()
        w.actions = parts.flatMap(\.actions).filter { seenActions.insert($0.task.lowercased()).inserted }.map {
            .init(task: $0.task, owner: $0.owner, due: try? Date($0.due, strategy: .iso8601.year().month().day()))
        }
        if parts.count > 1, let tight = await AIRouter.shared.write("Combine these into one 3 to 4 sentence meeting summary. Reply with only the summary.\n\(w.summary)") {
            w.summary = tight
        }
        // 3. Enhance the user's own notes with detail from the transcript.
        if !mine.isEmpty {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "MY NOTES:\n" + mine.map { "- \($0)" }.joined(separator: "\n") + "\n\nTRANSCRIPT:\n\(text.suffix(4_000))"
            w.enhancedNotes = (try? await session.respond(to: prompt, generating: EnhancedNotesOut.self).content.notes) ?? mine
        }
        return w
    }
}

// MARK: - Recorder screen

struct MeetingRecorderView: View {
    var target: Note? = nil
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var recorder = MeetingRecorder()
    @State private var event: EKEvent?
    @State private var writing = false
    @State private var makeTasks = true
    @State private var savedNote: Note?
    @State private var result: MeetingWriteUp?
    @State private var pane = 0
    @State private var myNotes = ""
    @State private var sources: [String] = []
    @State private var compose: ComposeDraft?
    @State private var openNote: Note?

    private var title: String { event?.title ?? (target?.title.isEmpty == false ? target!.title : "Meeting") }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            VStack(spacing: 4) {
                Text(title).font(DS.Font.title).multilineTextAlignment(.center)
                if let e = event {
                    Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \((e.attendees ?? []).compactMap(\.name).prefix(4).joined(separator: ", "))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
                if !sources.isEmpty {
                    Label("Using context: " + sources.joined(separator: ", "), systemImage: "sparkles")
                        .font(.caption2).foregroundStyle(DS.Palette.accent).lineLimit(2).multilineTextAlignment(.center)
                }
            }

            if result == nil { controls }

            if let r = result {
                resultView(r)
            } else {
                Picker("", selection: $pane) { Text("Transcript").tag(0); Text("My notes").tag(1) }.pickerStyle(.segmented)
                if pane == 0 {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(recorder.transcript.isEmpty ? "The transcript appears here as people talk. Everything stays on this iPhone." : recorder.transcript)
                                .font(DS.Font.body)
                                .foregroundStyle(recorder.transcript.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).padding().id("end")
                        }
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                        .onChange(of: recorder.transcript) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                } else {
                    TextEditor(text: $myNotes)
                        .scrollContentBackground(.hidden).padding(8)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                        .overlay(alignment: .topLeading) {
                            if myNotes.isEmpty {
                                Text("Jot quick notes, one per line. Keel fills in the details from the conversation.")
                                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).padding(14).allowsHitTesting(false)
                            }
                        }
                }
                if !recorder.isRecording && !recorder.transcript.isEmpty {
                    Toggle("Turn my action items into tasks", isOn: $makeTasks).font(DS.Font.body)
                    Button { Task { await writeUp() } } label: {
                        Label(writing ? "Writing up with context…" : "Write up meeting notes", systemImage: "sparkles")
                            .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                            .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                    }
                    .disabled(writing)
                }
            }
        }
        .padding()
        .navigationTitle("AI Meeting Notes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $compose) { ComposeView(draft: $0) }
        .navigationDestination(item: $openNote) { NoteEditor(note: $0) }
        .task {
            await CalendarService.shared.requestAccess()
            let now = Date()
            if let id = target?.linkedEventId, let e = CalendarService.shared.store.event(withIdentifier: id) {
                event = e
            } else {
                event = CalendarService.shared.events(from: now.addingTimeInterval(-3_600), to: now.addingTimeInterval(3_600))
                    .first { !$0.isAllDay && $0.startDate <= now.addingTimeInterval(900) && $0.endDate >= now }
            }
            sources = MeetingContext.build(event: event, title: title, ctx: ctx).sources
        }
        .onDisappear { if recorder.isRecording { recorder.stop() } }
    }

    private var controls: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.l) {
                Button {
                    Task {
                        if recorder.isRecording { recorder.stop() } else { await recorder.start(resume: !recorder.transcript.isEmpty) }
                    }
                } label: {
                    ZStack {
                        Circle().fill(recorder.isRecording ? Color.red : DS.Palette.accent).frame(width: 84, height: 84)
                            .shadow(color: (recorder.isRecording ? Color.red : DS.Palette.accent).opacity(0.4), radius: 14)
                        Image(systemName: recorder.isRecording ? "pause.fill" : (recorder.transcript.isEmpty ? "mic.fill" : "play.fill"))
                            .font(.system(size: 32)).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .symbolEffect(.pulse, isActive: recorder.isRecording)
                .accessibilityLabel(recorder.isRecording ? "Pause recording" : (recorder.transcript.isEmpty ? "Start recording" : "Resume recording"))
            }
            if let start = recorder.startedAt, recorder.isRecording {
                Text(start, style: .timer).font(DS.Font.headline.monospacedDigit()).foregroundStyle(.red)
            } else if !recorder.transcript.isEmpty {
                Text("Paused. Tap play to keep going, or write up the notes.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if let err = recorder.error { Text(err).font(DS.Font.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
    }

    private func resultView(_ r: MeetingWriteUp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                GlassCard(tint: DS.Palette.accent) { Text(r.summary).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                if !r.actions.isEmpty {
                    Text("Action items").font(DS.Font.headline)
                    ForEach(Array(r.actions.enumerated()), id: \.offset) { _, a in
                        Label(Self.actionLine(a), systemImage: "checkmark.circle").font(.callout)
                    }
                }
                if !r.decisions.isEmpty {
                    Text("Decisions").font(DS.Font.headline)
                    ForEach(r.decisions, id: \.self) { Label($0, systemImage: "checkmark.seal").font(.callout) }
                }
                HStack {
                    if let n = savedNote { Button { openNote = n } label: { Label("Open notes", systemImage: "doc.text") }.buttonStyle(.borderedProminent).tint(DS.Palette.accent) }
                    Button { compose = followUpDraft(r) } label: { Label("Email recap", systemImage: "envelope") }.buttonStyle(.bordered)
                }
                .padding(.top, DS.Space.s)
            }
        }
    }

    static func actionLine(_ a: MeetingWriteUp.Action) -> String {
        var s = a.owner.isEmpty ? a.task : "\(a.owner): \(a.task)"
        if let d = a.due { s += " (due \(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))" }
        return s
    }

    /// Is this action mine? Unassigned, "me", or my own name from Keel Memory.
    private func isMine(_ a: MeetingWriteUp.Action) -> Bool {
        let owner = a.owner.lowercased().trimmingCharacters(in: .whitespaces)
        if owner.isEmpty || ["me", "i", "myself", "you"].contains(owner) { return true }
        let myName = KeelMemory.shared.facts.first { $0.lowercased().hasPrefix("call me ") }?.dropFirst(8).lowercased() ?? ""
        return !myName.isEmpty && owner.contains(myName.trimmingCharacters(in: .whitespaces))
    }

    private func writeUp() async {
        writing = true; defer { writing = false }
        let context = MeetingContext.build(event: event, title: title, ctx: ctx)
        sources = context.sources
        let w = await MeetingAI.writeUp(recorder.transcript, context: context.text, myNotes: myNotes)

        var blocks: [NoteBlock] = []
        if let e = event {
            blocks.append(.init(kind: .text, text: "\(e.startDate.formatted(date: .abbreviated, time: .shortened)) · \((e.attendees ?? []).compactMap(\.name).joined(separator: ", "))"))
        }
        var summary = NoteBlock(kind: .callout, text: w.summary); summary.icon = "✨"
        blocks.append(summary)
        if !w.enhancedNotes.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Your notes"))
            blocks += w.enhancedNotes.map { NoteBlock(kind: .bullet, text: $0) }
        }
        if !w.topics.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Discussion"))
            for t in w.topics {
                blocks.append(.init(kind: .heading3, text: t.title))
                blocks += t.points.map { NoteBlock(kind: .bullet, text: $0) }
            }
        }
        if !w.decisions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Decisions"))
            blocks += w.decisions.map { NoteBlock(kind: .bullet, text: $0) }
        }
        if !w.actions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Action items"))
            blocks += w.actions.map { a in NoteBlock(kind: .todo, text: a.owner.isEmpty ? Self.actionLine(a) : "**\(a.owner)**: " + Self.actionLine(.init(task: a.task, owner: "", due: a.due))) }
        }
        if !w.questions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Open questions"))
            blocks += w.questions.map { NoteBlock(kind: .bullet, text: $0) }
        }
        var transcriptBlock = NoteBlock(kind: .toggle, text: "Transcript")
        transcriptBlock.body = recorder.transcript
        transcriptBlock.collapsed = true
        blocks += [.init(kind: .divider, text: ""), transcriptBlock]

        let note: Note
        if let target {
            note = target
            note.blocks += blocks
        } else {
            note = Note(title: event?.title ?? "Meeting · \(Date().formatted(date: .abbreviated, time: .shortened))", blocks: blocks)
            note.icon = "🎙️"
            ctx.insert(note)
        }
        note.linkedEventId = note.linkedEventId ?? event?.eventIdentifier
        note.aiSummary = w.summary
        note.updatedAt = Date()

        if makeTasks {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
            for a in w.actions {
                let mine = isMine(a)
                let t = TaskItem(title: mine ? a.task : "Follow up with \(a.owner): \(a.task)", dueDate: a.due ?? tomorrow)
                t.sourceNoteId = note.id
                t.tags = ["meeting"]
                t.isWaitingOn = !mine
                ctx.insert(t)
                try? CalendarService.shared.push(t)
            }
        }
        savedNote = note
        result = w
        Haptics.milestone()
    }

    /// A ready-to-send recap for everyone who was there.
    private func followUpDraft(_ r: MeetingWriteUp) -> ComposeDraft {
        var d = ComposeDraft()
        let mine = Set(accounts.map { $0.address.lowercased() })
        d.to = (event?.attendees ?? []).compactMap { p -> String? in
            let email = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return mine.contains(email.lowercased()) || p.isCurrentUser ? nil : email
        }.joined(separator: ", ")
        d.subject = "Recap: \(title)"
        var body = "Hi all,\n\nThanks for today. Here's a quick recap.\n\n\(r.summary)\n"
        if !r.decisions.isEmpty { body += "\nDecisions\n" + r.decisions.map { "• \($0)" }.joined(separator: "\n") + "\n" }
        if !r.actions.isEmpty { body += "\nNext steps\n" + r.actions.map { "• \(Self.actionLine($0))" }.joined(separator: "\n") + "\n" }
        d.body = body
        return d
    }
}
