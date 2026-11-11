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

    func start() async {
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
        transcript = ""; finalized = ""
        isRecording = true
        startedAt = Date()
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

struct MeetingWriteUp {
    var summary: String
    var decisions: [String]
    var actionItems: [String]
}

@Generable
struct MeetingNotesOutput {
    @Guide(description: "Three to five sentence summary of what was discussed")
    var summary: String
    @Guide(description: "Decisions that were made", .maximumCount(8))
    var decisions: [String]
    @Guide(description: "Concrete follow-up actions, each starting with a verb, with the owner's name if mentioned", .maximumCount(10))
    var actionItems: [String]
}

enum MeetingAI {
    /// On-device write-up. Long meetings are summarized in parts, then combined.
    @MainActor
    static func writeUp(_ transcript: String) async -> MeetingWriteUp {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIRouter.shared.onDeviceAvailable, text.count > 40 else {
            return MeetingWriteUp(summary: String(text.prefix(400)), decisions: [], actionItems: [])
        }
        var source = text
        if text.count > 9_000 {
            var partials: [String] = []
            var i = text.startIndex
            while i < text.endIndex {
                let j = text.index(i, offsetBy: 8_000, limitedBy: text.endIndex) ?? text.endIndex
                if let s = await AIRouter.shared.summarize(String(text[i..<j])) { partials.append(s) }
                i = j
            }
            source = partials.joined(separator: "\n")
        }
        do {
            let session = LanguageModelSession(instructions: "You turn meeting transcripts into clear, short meeting notes. Never invent details.")
            let out = try await session.respond(to: "Transcript:\n\(source.prefix(9_000))", generating: MeetingNotesOutput.self).content
            return MeetingWriteUp(summary: out.summary, decisions: out.decisions, actionItems: out.actionItems)
        } catch {
            return MeetingWriteUp(summary: await AIRouter.shared.summarize(String(source.prefix(9_000))) ?? String(text.prefix(400)),
                                  decisions: [], actionItems: [])
        }
    }
}

struct MeetingRecorderView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MeetingRecorder()
    @State private var event: EKEvent?
    @State private var writing = false
    @State private var makeTasks = true
    @State private var savedNote: Note?

    var body: some View {
        VStack(spacing: DS.Space.l) {
            VStack(spacing: 4) {
                Text(event?.title ?? "Meeting").font(DS.Font.title).multilineTextAlignment(.center)
                if let e = event {
                    Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \((e.attendees ?? []).compactMap(\.name).prefix(4).joined(separator: ", "))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
            }

            Button {
                Task {
                    if recorder.isRecording { recorder.stop() } else { await recorder.start() }
                }
            } label: {
                ZStack {
                    Circle().fill(recorder.isRecording ? Color.red : DS.Palette.accent).frame(width: 96, height: 96)
                        .shadow(color: (recorder.isRecording ? Color.red : DS.Palette.accent).opacity(0.4), radius: 16)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 36)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .symbolEffect(.pulse, isActive: recorder.isRecording)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

            if let start = recorder.startedAt, recorder.isRecording {
                Text(start, style: .timer).font(DS.Font.headline.monospacedDigit()).foregroundStyle(.red)
            }
            if let err = recorder.error { Text(err).font(DS.Font.caption).foregroundStyle(.red).multilineTextAlignment(.center) }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(recorder.transcript.isEmpty ? "The transcript appears here as people talk. Everything stays on this iPhone." : recorder.transcript)
                        .font(DS.Font.body)
                        .foregroundStyle(recorder.transcript.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("end")
                }
                .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                .onChange(of: recorder.transcript) { proxy.scrollTo("end", anchor: .bottom) }
            }

            if !recorder.isRecording && !recorder.transcript.isEmpty {
                Toggle("Turn action items into tasks", isOn: $makeTasks).font(DS.Font.body)
                Button { Task { await writeUp() } } label: {
                    Label(writing ? "Writing up…" : (savedNote == nil ? "Write up meeting notes" : "Saved to Notes"),
                          systemImage: savedNote == nil ? "sparkles" : "checkmark")
                        .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                        .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                }
                .disabled(writing || savedNote != nil)
            }
        }
        .padding()
        .navigationTitle("Record Meeting")
        .task {
            await CalendarService.shared.requestAccess()
            let now = Date()
            event = CalendarService.shared.events(from: now.addingTimeInterval(-3_600), to: now.addingTimeInterval(3_600))
                .first { !$0.isAllDay && $0.startDate <= now.addingTimeInterval(900) && $0.endDate >= now }
        }
        .onDisappear { if recorder.isRecording { recorder.stop() } }
    }

    private func writeUp() async {
        writing = true; defer { writing = false }
        let w = await MeetingAI.writeUp(recorder.transcript)
        var blocks: [NoteBlock] = []
        if let e = event {
            blocks.append(.init(kind: .text, text: "\(e.startDate.formatted(date: .abbreviated, time: .shortened)) · \((e.attendees ?? []).compactMap(\.name).joined(separator: ", "))"))
        }
        blocks += [.init(kind: .heading, text: "Summary"), .init(kind: .text, text: w.summary)]
        if !w.decisions.isEmpty {
            blocks.append(.init(kind: .heading, text: "Decisions"))
            blocks += w.decisions.map { NoteBlock(kind: .bullet, text: $0) }
        }
        if !w.actionItems.isEmpty {
            blocks.append(.init(kind: .heading, text: "Action items"))
            blocks += w.actionItems.map { NoteBlock(kind: .todo, text: $0) }
        }
        blocks += [.init(kind: .divider, text: ""), .init(kind: .heading, text: "Transcript"), .init(kind: .quote, text: recorder.transcript)]
        let note = Note(title: event?.title ?? "Meeting · \(Date().formatted(date: .abbreviated, time: .shortened))", blocks: blocks)
        note.linkedEventId = event?.eventIdentifier
        note.aiSummary = w.summary
        ctx.insert(note)
        if makeTasks {
            for item in w.actionItems {
                let t = TaskItem(title: item, dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
                t.sourceNoteId = note.id
                t.tags = ["meeting"]
                ctx.insert(t)
                try? CalendarService.shared.push(t)
            }
        }
        savedNote = note
        Haptics.milestone()
    }
}
