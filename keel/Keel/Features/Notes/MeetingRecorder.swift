import SwiftUI
import SwiftData
import Speech
import AVFoundation
import EventKit
import FoundationModels

/// Record a meeting, transcribe it on-device as people talk, then write up a summary,
/// decisions and action items with Apple Intelligence. Saved as a note linked to the calendar event.

/// The audio thread feeds buffers here (kept off the main actor on purpose): to live transcription, and to a file
/// on disk so nothing is lost even if live transcription hiccups.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    private var _file: AVAudioFile?
    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }
    var file: AVAudioFile? {
        get { lock.withLock { _file } }
        set { lock.withLock { _file = newValue } }
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        let (req, f) = lock.withLock { (_request, _file) }
        req?.append(buffer)
        try? f?.write(from: buffer)
    }
}

/// One recorder for the whole app, so a meeting keeps recording if you switch screens or lock your iPhone.
@MainActor @Observable
final class MeetingRecorder {
    static let shared = MeetingRecorder()

    var transcript = ""
    var isRecording = false
    var startedAt: Date?
    var error: String?
    var repairing = false                  // re-reading the saved audio after you stop
    var recordedSeconds: TimeInterval = 0
    var liveTitle: String?                 // what the Lock Screen calls this recording (the event's name, if known)

    private var finalized = ""             // everything from earlier segments
    private var segment = ""               // the current segment's latest text
    private var generation = 0             // ignores late results from a recognition task we already replaced
    private var segmentStarted = Date()
    private var segmentStamp = ""          // "[04:12]" where the current segment began
    private let engine = AVAudioEngine()
    private let feed = AudioFeed()
    private var task: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private(set) var audioParts: [URL] = []      // one file per stretch of recording (pause → resume starts a new one)

    static var recordingsFolder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MeetingAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Clears the last meeting so the next one starts fresh.
    func reset() {
        guard !isRecording else { return }
        transcript = ""; finalized = ""; segment = ""; segmentStamp = ""
        startedAt = nil; recordedSeconds = 0; error = nil
        audioParts = []
    }

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
        if !resume { reset() }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Keep a compressed copy of the audio, appended across pauses.
            let url = Self.recordingsFolder.appendingPathComponent("meeting-\(Int(Date().timeIntervalSince1970))-\(audioParts.count).m4a")
            do {
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                               AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 48_000]
                feed.file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                if feed.file != nil { audioParts.append(url) }
            }
            input.removeTap(onBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                feed.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Couldn't start recording: \(error.localizedDescription)"
            return
        }
        if resume {
            finalized = transcript.isEmpty ? "" : transcript + "\n"
            segment = ""; segmentStamp = ""
        }
        isRecording = true
        if startedAt == nil { startedAt = Date() }
        segmentStarted = Date()
        MeetingAutopilot.recordingChanged(true, since: startedAt, title: liveTitle)
        UIApplication.shared.isIdleTimerDisabled = true       // the screen stays on while you record
        observeInterruptions()
        beginRecognition()
    }

    private func beginRecognition() {
        guard let recognizer, isRecording else { return }
        generation += 1
        let gen = generation
        segment = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // private, no time limit
        feed.request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = err != nil
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let text { self.take(text) }
                if isFinal || failed {
                    // The recognizer ends a segment on a long pause or an error; bank it and keep listening.
                    self.commitSegment()
                    if self.isRecording {
                        try? await Task.sleep(for: .milliseconds(150))
                        if self.isRecording && gen == self.generation { self.beginRecognition() }
                    }
                }
            }
        }
    }

    /// New text for the current segment. On-device recognition sometimes starts over after a pause
    /// without saying so; when the new text no longer continues the old one, bank the old one first.
    private func take(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !segment.isEmpty && !Self.continues(segment, with: t) {
            finalized += segmentStamp + segment + "\n"
            segmentStamp = ""
        }
        if segmentStamp.isEmpty { segmentStamp = stamp() }
        segment = t
        transcript = finalized + segmentStamp + segment
    }

    private func commitSegment() {
        if !segment.isEmpty { finalized += segmentStamp + segment + "\n" }
        segment = ""
        segmentStamp = ""
        transcript = finalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { finalized = transcript + "\n" }
    }

    /// "[mm:ss] " from the start of the meeting, like a transcript in a meeting app.
    private func stamp() -> String {
        let secs = Int(Date().timeIntervalSince(startedAt ?? Date()))
        return String(format: "[%02d:%02d] ", secs / 60, secs % 60)
    }

    /// True when `new` is a revision of `old` (same beginning), false when the recognizer started over.
    nonisolated static func continues(_ old: String, with new: String) -> Bool {
        let a = old.lowercased().split(separator: " ").prefix(3)
        let b = new.lowercased().split(separator: " ").prefix(3)
        if a.isEmpty || b.isEmpty { return true }
        if new.count + 12 < old.count / 2 { return false }               // far shorter: it reset
        return a.first == b.first || Array(a) == Array(b)
    }

    func stop(repair: Bool = true) {
        guard isRecording else { return }
        isRecording = false
        MeetingAutopilot.recordingChanged(false, since: nil)
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        feed.request?.endAudio()
        feed.request = nil
        feed.file = nil                                    // closes the audio file
        task?.finish()
        commitSegment()
        if let s = startedAt { recordedSeconds = Date().timeIntervalSince(s) }
        UIApplication.shared.isIdleTimerDisabled = false
        if let o = interruptionObserver { NotificationCenter.default.removeObserver(o); interruptionObserver = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if repair { Task { await repairIfShort() } }
    }

    /// The meeting is saved as a note: delete the temporary audio and start clean next time.
    func finishMeeting() {
        guard !isRecording else { return }
        MeetingAutopilot.recordingFinished()
        liveTitle = nil
        for url in audioParts { try? FileManager.default.removeItem(at: url) }
        reset()
    }

    /// A phone call or Siri pauses recording; pick it back up when the interruption ends.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                let rec = MeetingRecorder.shared
                guard rec.isRecording, raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                if !rec.engine.isRunning { try? rec.engine.start() }
                rec.commitSegment()
                rec.beginRecognition()
            }
        }
    }

    /// If the live transcript is much shorter than the meeting (people talk ~2 words a second),
    /// transcribe the saved audio file again from the start and keep whichever is longer.
    func repairIfShort() async {
        let parts = audioParts.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !parts.isEmpty, let recognizer else { return }
        let words = transcript.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let seconds = recordedSeconds
        guard seconds > 30, Double(words) < seconds * 0.6 else { return }
        repairing = true
        defer { repairing = false }
        var pieces: [String] = []
        for url in parts { pieces.append(await Self.transcribeFile(url, recognizer: recognizer)) }
        let full = pieces.filter { !$0.isEmpty }.joined(separator: " ")
        if !isRecording, full.split(separator: " ").count > words {
            transcript = full
            finalized = full + "\n"
        }
    }

    /// Reads a whole recording on device, banking each segment as it finishes.
    static func transcribeFile(_ url: URL, recognizer: SFSpeechRecognizer) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let req = SFSpeechURLRecognitionRequest(url: url)
            req.shouldReportPartialResults = false
            req.addsPunctuation = true
            req.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            final class Box: @unchecked Sendable { var parts: [String] = []; var done = false }
            let box = Box()
            _ = recognizer.recognitionTask(with: req) { result, err in
                if let r = result {
                    let t = r.bestTranscription.formattedString
                    if !t.isEmpty {
                        // A revision of the same stretch replaces it; a new stretch is added after it.
                        if let last = box.parts.last, MeetingRecorder.continues(last, with: t) { box.parts[box.parts.count - 1] = t }
                        else { box.parts.append(t) }
                    }
                    if r.isFinal && !box.done { box.done = true; c.resume(returning: box.parts.joined(separator: " ")) }
                } else if err != nil, !box.done {
                    box.done = true
                    c.resume(returning: box.parts.joined(separator: " "))
                }
            }
        }
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

/// Which calendar event a recording belongs to. Like picking the event you "Join and transcribe" from:
/// a real meeting (people or a call link) happening when you pressed record beats an all-day block,
/// a long "Work" hold, an event you declined, or Keel's own focus blocks.
@MainActor
enum MeetingEventMatcher {
    /// Events near this moment, best first (for the picker as well).
    static func candidates(around t: Date, window: TimeInterval = 2 * 3600) -> [EKEvent] {
        CalendarService.shared.events(from: t.addingTimeInterval(-window), to: t.addingTimeInterval(window))
            .filter { usable($0) }
            .sorted { score($0, at: t) > score($1, at: t) }
    }

    /// The event this recording is most likely for, or nil when nothing fits well.
    static func best(at t: Date) -> EKEvent? {
        let near = CalendarService.shared.events(from: t.addingTimeInterval(-6 * 3600), to: t.addingTimeInterval(1_800))
            .filter { usable($0) && $0.startDate <= t.addingTimeInterval(15 * 60) && $0.endDate >= t.addingTimeInterval(-5 * 60) }
        guard let top = near.max(by: { score($0, at: t) < score($1, at: t) }) else { return nil }
        // A solo, hours-long block ("Work", "Office") isn't a meeting someone records.
        let hours = top.endDate.timeIntervalSince(top.startDate) / 3600
        if !MeetingAutopilot.isMeeting(top) && hours > 2.5 { return nil }
        return top
    }

    private static func usable(_ e: EKEvent) -> Bool {
        guard !e.isAllDay, e.status != .canceled, e.calendar?.title != "Keel" else { return false }
        if let me = e.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return false }
        return true
    }

    static func score(_ e: EKEvent, at t: Date) -> Double {
        var s = 0.0
        let others = (e.attendees ?? []).filter { !$0.isCurrentUser }.count
        if others > 0 { s += 3 + min(Double(others), 5) * 0.2 }
        if MeetingLink.find(e) != nil { s += 2 }
        if e.availability == .free { s -= 1 }
        if e.startDate <= t && e.endDate >= t { s += 2 }                       // happening right now
        s -= abs(e.startDate.timeIntervalSince(t)) / 1_800                       // closer start, better
        s -= min(e.endDate.timeIntervalSince(e.startDate) / 3600, 8) * 0.4       // long holds lose
        return s
    }

    /// When the event was guessed (not chosen), check the conversation is actually that meeting.
    static func confirm(_ e: EKEvent, transcript: String) async -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 400 else { return true }
        let people = (e.attendees ?? []).compactMap(\.name).prefix(6).joined(separator: ", ")
        let prompt = """
        A calendar event is titled "\(e.title ?? "")"\(people.isEmpty ? "" : " with \(people)")\(e.notes.map { ". Invite notes: \($0.prefix(200))" } ?? "").
        Below is the start of a recorded conversation. Reply with only YES if it could plausibly be this meeting, or NO if it is clearly about something unrelated.

        \(text.prefix(2_500))
        """
        guard let r = await AIRouter.shared.write(prompt) else { return true }
        return !r.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("NO")
    }
}

/// Names the meeting note: the calendar event's name when it's specific; otherwise a short title written from what
/// was actually discussed (a generic "Sync" or "Call" gets the subject added).
@MainActor
enum MeetingTitler {
    static let generic: Set<String> = ["meeting", "call", "sync", "catch up", "catch-up", "catchup", "chat", "1:1", "1-1", "1 on 1", "one on one",
                                       "busy", "hold", "blocked", "zoom", "zoom meeting", "teams meeting", "microsoft teams meeting", "google meet",
                                       "check-in", "check in", "standup", "stand-up", "huddle", "discussion", "event", "appointment", "new event",
                                       "phone call", "video call", "facetime", "quick call", "quick chat", "touch base", "connect", "tbd"]

    static func isGeneric(_ title: String?) -> Bool {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.count < 3 || generic.contains(t)
    }

    static func title(event: EKEvent?, summary: String, topics: [String], transcript: String) async -> String {
        if let e = event, !isGeneric(e.title) { return e.title ?? "Meeting" }
        let basis = summary.isEmpty ? String(transcript.prefix(3_000)) : summary + (topics.isEmpty ? "" : "\nTopics: " + topics.joined(separator: "; "))
        var subject: String?
        if basis.count > 40 {
            let prompt = """
            Write a short, specific title for these meeting notes: 3 to 7 words naming the main subject and, if clear, who it was with             (like "Q3 budget review with Dana" or "Kitchen remodel quote"). No quotes, no date, no ending period. Reply with only the title.

            \(basis.prefix(3_000))
            """
            if let r = await AIRouter.shared.write(prompt) {
                let clean = r.split(separator: "\n").first.map(String.init)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*#. ").union(.whitespaces)) ?? ""
                if clean.count >= 3 && clean.count <= 80 && !clean.lowercased().hasPrefix("title") { subject = clean }
            }
        }
        let date = (event?.startDate ?? Date()).formatted(date: .abbreviated, time: .omitted)
        switch (event?.title, subject) {
        case let (eventTitle?, subject?) where !eventTitle.isEmpty: return "\(eventTitle): \(subject)"
        case let (_, subject?): return subject
        case let (eventTitle?, nil) where !eventTitle.isEmpty: return "\(eventTitle) · \(date)"
        default: return "Meeting · \(date)"
        }
    }
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

/// What kind of meeting it was, so the notes focus on what matters for it.
enum MeetingTemplate: String, CaseIterable, Identifiable {
    case general, oneOnOne, standup, sales, interview, brainstorm, lecture
    var id: String { rawValue }
    static let key = "meeting.template"

    var title: String {
        switch self {
        case .general: "General"; case .oneOnOne: "1:1"; case .standup: "Standup"; case .sales: "Sales or client call"
        case .interview: "Interview"; case .brainstorm: "Brainstorm"; case .lecture: "Class or lecture"
        }
    }
    var icon: String {
        switch self {
        case .general: "person.2"; case .oneOnOne: "person.line.dotted.person"; case .standup: "figure.stand"; case .sales: "briefcase"
        case .interview: "person.crop.rectangle.badge.plus"; case .brainstorm: "lightbulb"; case .lecture: "graduationcap"
        }
    }
    /// Extra direction for the writer.
    var focus: String {
        switch self {
        case .general: "Cover what was discussed, what was decided, and who is doing what next."
        case .oneOnOne: "Focus on wins, blockers, feedback given in both directions, growth and career topics, and commitments each person made."
        case .standup: "For each person: what they did, what they'll do next, and anything blocking them. Topics are people."
        case .sales: "Capture the customer's needs and pain points, current tools, objections, budget, decision makers, timeline, competitors mentioned, and agreed next steps."
        case .interview: "Capture the candidate's background, strongest answers, concerns or gaps, questions they asked, and an overall signal. Stay factual."
        case .brainstorm: "Group the ideas into themes, note which ideas got the most support, and capture open questions and next experiments."
        case .lecture: "Capture the key concepts with definitions, examples given, anything the speaker said will be tested or is important, and assignments with due dates."
        }
    }
}

enum MeetingAI {
    /// Context-aware write-up. With Claude connected the whole meeting is read at once; otherwise Apple Intelligence
    /// reads long transcripts in parts, then merges them, so nothing at the end is lost.
    @MainActor
    static func writeUp(_ transcript: String, context: String, myNotes: String, template: MeetingTemplate = .general) async -> MeetingWriteUp {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let mine = myNotes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")) }.filter { !$0.isEmpty }
        let instructions = """
        You write meeting notes like an excellent chief of staff. Use the context to understand names, projects and acronyms, \
        and to notice follow-ups from last time, but only report what was said in this transcript. Be specific: keep numbers, \
        names, dates and reasons. Never invent. Meeting type: \(template.title). \(template.focus)
        CONTEXT:
        \(context)
        """
        // Apple Intelligence first; Claude only when it isn't available on this device or can't read the meeting.
        guard AIRouter.shared.onDeviceAvailable, text.count > 40 else {
            if text.count > 40, AIRouter.shared.cloudEnabled, let w = await cloudWriteUp(text, instructions: instructions, mine: mine) { return w }
            return MeetingWriteUp(summary: String(text.prefix(400)), enhancedNotes: mine)
        }
        // 1. Read the transcript in parts.
        var parts: [MeetingPartOut] = []
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: 4_500, limitedBy: text.endIndex) ?? text.endIndex
            let session = LanguageModelSession(instructions: instructions)
            if let p = try? await session.respond(to: "Transcript part:\n\(text[i..<j])", generating: MeetingPartOut.self).content {
                parts.append(p)
            }
            i = j
        }
        guard !parts.isEmpty else {
            if AIRouter.shared.cloudEnabled, let w = await cloudWriteUp(text, instructions: instructions, mine: mine) { return w }
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
            let session = LanguageModelSession(instructions: String(instructions.prefix(3_000)))
            let prompt = "MY NOTES:\n" + mine.map { "- \($0)" }.joined(separator: "\n") + "\n\nTRANSCRIPT:\n\(text.suffix(4_000))"
            w.enhancedNotes = (try? await session.respond(to: prompt, generating: EnhancedNotesOut.self).content.notes) ?? mine
        }
        return w
    }

    /// One pass over the whole meeting with Claude (through your Keel server or your own key).
    @MainActor
    private static func cloudWriteUp(_ text: String, instructions: String, mine: [String]) async -> MeetingWriteUp? {
        let user = (mine.isEmpty ? "" : "MY NOTES (rewrite each into a fuller sentence using the transcript, same order):\n" + mine.map { "- \($0)" }.joined(separator: "\n") + "\n\n")
            + "TRANSCRIPT ([mm:ss] marks when each part was said):\n" + String(text.prefix(150_000))
        guard let r = try? await AIRouter.shared.cloud.meetingNotes(system: instructions, user: user) else { return nil }
        var w = MeetingWriteUp(summary: r.summary)
        w.topics = r.topics.map { .init(title: $0.title, points: $0.points) }
        w.decisions = r.decisions
        w.questions = r.questions
        w.actions = r.actions.map { .init(task: $0.task, owner: $0.owner, due: try? Date($0.due, strategy: .iso8601.year().month().day())) }
        w.enhancedNotes = mine.isEmpty ? [] : (r.enhancedNotes.isEmpty ? mine : r.enhancedNotes)
        return w
    }

    /// "Ask about this meeting": answers only from the transcript.
    @MainActor
    static func ask(_ question: String, transcript: String) async -> String {
        let prompt = """
        Answer the question using only this meeting transcript. Quote names, numbers and dates exactly. \
        If the transcript doesn't say, answer "That wasn't discussed." Keep it to a few sentences.
        QUESTION: \(question)
        TRANSCRIPT:
        \(transcript.suffix(AIRouter.shared.onDeviceAvailable ? 8_000 : 120_000))
        """
        if AIRouter.shared.onDeviceAvailable, let a = await AIRouter.shared.write(prompt) { return a }
        if AIRouter.shared.cloudEnabled, let a = try? await AIRouter.shared.cloud.answer(prompt) { return a }
        return "Keel couldn't answer that right now."
    }
}

// MARK: - Recorder screen

struct MeetingRecorderView: View {
    var target: Note? = nil
    /// Opened from the meeting nudge or Today's Record button: start listening right away.
    var autoStart = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var recorder = MeetingRecorder.shared
    @State private var event: EKEvent?
    @State private var eventChosen = false          // linked to the page, or picked by you: never second-guessed
    @State private var candidates: [EKEvent] = []
    @State private var writing = false
    @State private var makeTasks = true
    @State private var savedNote: Note?
    @State private var result: MeetingWriteUp?
    @State private var pane = 0
    @State private var myNotes = ""
    @State private var sources: [String] = []
    @State private var compose: ComposeDraft?
    @State private var openNote: Note?
    @AppStorage(MeetingTemplate.key) private var templateRaw = MeetingTemplate.general.rawValue
    @State private var question = ""
    @State private var answers: [(q: String, a: String)] = []
    @State private var asking = false

    private var template: MeetingTemplate { MeetingTemplate(rawValue: templateRaw) ?? .general }
    private var title: String { event?.title ?? (target?.title.isEmpty == false ? target!.title : "Meeting") }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            VStack(spacing: 4) {
                Text(title).font(DS.Font.title).multilineTextAlignment(.center)
                if result == nil {
                    Menu {
                        Section("Which meeting is this?") {
                            ForEach(candidates, id: \.calendarItemIdentifier) { e in
                                Button {
                                    event = e; eventChosen = true; recorder.liveTitle = e.title
                                    if recorder.isRecording { MeetingAutopilot.startActivity(for: e) }
                                } label: {
                                    Label("\(e.title ?? "Event") · \(e.startDate.formatted(date: .omitted, time: .shortened))",
                                          systemImage: event?.calendarItemIdentifier == e.calendarItemIdentifier ? "checkmark" : "calendar")
                                }
                            }
                        }
                        Button("Not a calendar event", systemImage: "calendar.badge.minus") { event = nil; eventChosen = true; recorder.liveTitle = nil }
                    } label: {
                        HStack(spacing: 4) {
                            if let e = event {
                                Text("\(e.startDate.formatted(date: .omitted, time: .shortened))\((e.attendees ?? []).isEmpty ? "" : " · " + (e.attendees ?? []).compactMap(\.name).prefix(3).joined(separator: ", "))")
                                    .lineLimit(1)
                            } else {
                                Text("No calendar event · Keel names it from the conversation")
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .accessibilityLabel(event == nil ? "No calendar event. Choose the meeting" : "Linked to \(event?.title ?? ""). Change the meeting")
                } else if let e = event {
                    Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \((e.attendees ?? []).compactMap(\.name).prefix(4).joined(separator: ", "))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
                if result == nil {
                    Menu {
                        Picker("Meeting type", selection: $templateRaw) {
                            ForEach(MeetingTemplate.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                        }
                    } label: {
                        Label(template.title, systemImage: template.icon).font(DS.Font.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(DS.Palette.accent.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Meeting type: \(template.title). Changes how the notes are written")
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
                        Label(recorder.repairing ? "Recovering the full transcript…" : writing ? "Writing up with context…" : "Write up meeting notes",
                              systemImage: recorder.repairing ? "waveform" : "sparkles")
                            .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                            .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                    }
                    .disabled(writing || recorder.repairing)
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
            let at = recorder.startedAt ?? now
            if let id = target?.linkedEventId, let e = CalendarService.shared.store.event(withIdentifier: id) {
                event = e
                eventChosen = true
            } else if !eventChosen {
                event = MeetingEventMatcher.best(at: at)
            }
            candidates = MeetingEventMatcher.candidates(around: at)
            recorder.liveTitle = event?.title
            // A finished meeting from hours ago shouldn't leak into this one.
            if !recorder.isRecording, let s = recorder.startedAt, Date().timeIntervalSince(s) > 4 * 3600 { recorder.reset() }
            if autoStart && !recorder.isRecording && recorder.transcript.isEmpty {
                await recorder.start()
                if let event { MeetingAutopilot.startActivity(for: event) }
            }
            sources = MeetingContext.build(event: event, title: title, ctx: ctx).sources
            // A quick look at the web (company sites, invite links) so you can see what Keel will use.
            let web = await WebContext.gather(event: event, title: title, transcript: "", deep: false)
            sources += web.sources
        }
        .onDisappear { if !recorder.isRecording { MeetingAutopilot.setRecording(false) } }   // keeps recording if you switch screens
    }

    private var controls: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.l) {
                Button {
                    Task {
                        if recorder.isRecording { recorder.stop() } else {
                            let first = recorder.transcript.isEmpty
                            await recorder.start(resume: !first)
                            if first, let event { MeetingAutopilot.startActivity(for: event) }
                        }
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

                if !recorder.transcript.isEmpty || recorder.isRecording {
                    Button { Task { await endMeeting() } } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(DS.Palette.ink).frame(width: 60, height: 60)
                                Image(systemName: "stop.fill").font(.title2).foregroundStyle(DS.Palette.canvas)
                            }
                            Text("End").font(DS.Font.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(writing || recorder.repairing)
                    .accessibilityLabel("End meeting and write the notes")
                }
            }
            if let start = recorder.startedAt, recorder.isRecording {
                Text(start, style: .timer).font(DS.Font.headline.monospacedDigit()).foregroundStyle(.red)
            } else if !recorder.transcript.isEmpty {
                Text(recorder.repairing ? "Recovering the full transcript from the recording…" : writing ? "Writing your notes…" : "Paused. Tap play to keep going, or End to write the notes.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
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
                if !r.topics.isEmpty {
                    Text("Key discussion points").font(DS.Font.headline)
                    ForEach(Array(r.topics.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.title).font(.callout.weight(.semibold))
                            ForEach(Array(t.points.enumerated()), id: \.offset) { _, p in
                                Text("• " + p).font(.callout).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
                if !r.decisions.isEmpty {
                    Text("Decisions").font(DS.Font.headline)
                    ForEach(r.decisions, id: \.self) { Label($0, systemImage: "checkmark.seal").font(.callout) }
                }
                askSection
                HStack {
                    if let n = savedNote { Button { openNote = n } label: { Label("Open notes", systemImage: "doc.text") }.buttonStyle(.borderedProminent).tint(DS.Palette.accent) }
                    Button { compose = followUpDraft(r) } label: { Label("Email recap", systemImage: "envelope") }.buttonStyle(.bordered)
                }
                .padding(.top, DS.Space.s)
            }
        }
    }

    /// Ask about this meeting: answers come only from what was said.
    private var askSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Ask about this meeting").font(DS.Font.headline)
            ForEach(Array(answers.enumerated()), id: \.offset) { _, qa in
                VStack(alignment: .leading, spacing: 4) {
                    Text(qa.q).font(.callout.weight(.semibold))
                    Text(qa.a).font(.callout).foregroundStyle(DS.Palette.inkSoft).textSelection(.enabled)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: 14))
            }
            HStack {
                TextField("What did we decide about…?", text: $question, axis: .vertical).lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await askQuestion() } }
                Button { Task { await askQuestion() } } label: {
                    if asking { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || asking)
                .accessibilityLabel("Ask")
            }
        }
        .padding(.top, DS.Space.s)
    }

    private func askQuestion() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let text = savedNote?.blocks.first(where: { $0.kind == .toggle && $0.text == "Transcript" })?.body else { return }
        asking = true; defer { asking = false }
        question = ""
        let a = await MeetingAI.ask(q, transcript: text)
        withAnimation(DS.spring) { answers.append((q, a)) }
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

    /// Like ending a meeting in a meeting-notes app: stop, recover anything the live transcript missed, then write the notes.
    private func endMeeting() async {
        writing = true
        if recorder.isRecording { recorder.stop(repair: false) }
        await recorder.repairIfShort()
        writing = false
        guard !recorder.transcript.isEmpty else { return }
        await writeUp()
    }

    private func writeUp() async {
        writing = true; defer { writing = false }
        // Settle which meeting this was, using when recording actually started, then make sure the
        // conversation matches it (a call taken during a scheduled block shouldn't be named after the block).
        if !eventChosen {
            event = MeetingEventMatcher.best(at: recorder.startedAt ?? Date())
            if let e = event, !(await MeetingEventMatcher.confirm(e, transcript: recorder.transcript)) { event = nil }
        }
        let context = MeetingContext.build(event: event, title: title, ctx: ctx)
        // Web context: company sites, invite links, Wikipedia for recurring topics, and (with your own AI key) a live web search.
        let web = await WebContext.gather(event: event, title: title, transcript: recorder.transcript, deep: true)
        sources = context.sources + web.sources
        let fullContext = web.text.isEmpty ? context.text : context.text + "\nFROM THE WEB (background only; the meeting itself is the source of truth):\n" + web.text
        let w = await MeetingAI.writeUp(recorder.transcript, context: fullContext, myNotes: myNotes, template: template)

        var blocks: [NoteBlock] = []
        // Header: when, who, how long, what kind of meeting.
        var meta: [String] = [(event?.startDate ?? recorder.startedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)]
        let minutes = Int((recorder.recordedSeconds > 0 ? recorder.recordedSeconds : Date().timeIntervalSince(recorder.startedAt ?? Date())) / 60)
        if minutes > 0 { meta.append("\(minutes) min") }
        meta.append(template.title)
        if let names = event?.attendees?.compactMap(\.name), !names.isEmpty { meta.append(names.joined(separator: ", ")) }
        var header = NoteBlock(kind: .callout, text: meta.joined(separator: " · ")); header.icon = "🎙️"
        blocks.append(header)

        blocks.append(.init(kind: .heading2, text: "Summary"))
        blocks.append(.init(kind: .text, text: w.summary))
        if !w.actions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Action items"))
            blocks += w.actions.map { a in NoteBlock(kind: .todo, text: a.owner.isEmpty ? Self.actionLine(a) : "**\(a.owner)**: " + Self.actionLine(.init(task: a.task, owner: "", due: a.due))) }
        }
        if !w.topics.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Key discussion points"))
            for t in w.topics {
                blocks.append(.init(kind: .heading3, text: t.title))
                blocks += t.points.map { NoteBlock(kind: .bullet, text: $0) }
            }
        }
        if !w.decisions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Decisions"))
            blocks += w.decisions.map { NoteBlock(kind: .bullet, text: $0) }
        }
        if !w.questions.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Open questions"))
            blocks += w.questions.map { NoteBlock(kind: .bullet, text: $0) }
        }
        if !w.enhancedNotes.isEmpty {
            blocks.append(.init(kind: .heading2, text: "Your notes"))
            blocks += w.enhancedNotes.map { NoteBlock(kind: .bullet, text: $0) }
        }
        var transcriptBlock = NoteBlock(kind: .toggle, text: "Transcript")
        transcriptBlock.body = recorder.transcript
        transcriptBlock.collapsed = true
        blocks += [.init(kind: .divider, text: ""), transcriptBlock]

        let note: Note
        if let target {
            note = target
            note.blocks += blocks
            if note.title.trimmingCharacters(in: .whitespaces).isEmpty {
                note.title = await MeetingTitler.title(event: event, summary: w.summary, topics: w.topics.map(\.title), transcript: recorder.transcript)
            }
        } else {
            let name = await MeetingTitler.title(event: event, summary: w.summary, topics: w.topics.map(\.title), transcript: recorder.transcript)
            note = Note(title: name, blocks: blocks)
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
        recorder.finishMeeting()             // saved in the note; clear the recorder and its audio for next time
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
