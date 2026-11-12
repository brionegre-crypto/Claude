import SwiftUI
import SwiftData

/// "I'm overwhelmed": breathe for a minute, name the feeling, then shrink the day to one tiny step.
struct OverwhelmedView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @AppStorage(Prefs.calm) private var calm = false
    @State private var step = 0
    @State private var breathing = false
    @State private var phase = "Breathe in"
    @State private var feeling: String?
    @State private var lightened: Int?
    @State private var focusTask: TaskItem?
    @State private var showDump = false

    private var tiny: TaskItem? {
        let open = tasks.filter { !$0.isDone && !$0.isSomeday && !$0.isWaitingOn }
        let energy = EnergyLevel.low
        return ADHDCoach.nextThing(tasks: open, energy: energy)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                switch step {
                case 0: breathe
                case 1: name
                default: shrink
                }
            }
            .padding()
            .frame(maxHeight: .infinity)
            .background(LinearGradient(colors: [DS.Palette.calm.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $focusTask) { t in NavigationStack { FocusView(preselected: t) } }
            .sheet(isPresented: $showDump) { BrainDumpView() }
        }
    }

    // 1. One minute of box breathing.
    private var breathe: some View {
        VStack(spacing: DS.Space.l) {
            Text("You're okay. Let's slow down.").font(DS.Font.title).multilineTextAlignment(.center)
            ZStack {
                Circle().fill(DS.Palette.calm.opacity(0.2)).frame(width: 220, height: 220)
                Circle().fill(DS.Palette.calm.opacity(0.5))
                    .frame(width: breathing ? 210 : 90, height: breathing ? 210 : 90)
                Text(phase).font(DS.Font.headline)
            }
            .task {
                for _ in 0..<4 {                                    // 4 rounds × 16 s ≈ 1 minute
                    phase = "Breathe in"; withAnimation(.easeInOut(duration: 4)) { breathing = true }
                    try? await Task.sleep(for: .seconds(4)); phase = "Hold"
                    try? await Task.sleep(for: .seconds(4)); phase = "Breathe out"
                    withAnimation(.easeInOut(duration: 4)) { breathing = false }
                    try? await Task.sleep(for: .seconds(4)); phase = "Hold"
                    try? await Task.sleep(for: .seconds(4))
                    if Task.isCancelled { return }
                }
                withAnimation { step = 1 }
            }
            Button("Skip") { withAnimation { step = 1 } }.foregroundStyle(DS.Palette.inkSoft)
        }
    }

    // 2. Name it to tame it.
    private var name: some View {
        VStack(spacing: DS.Space.m) {
            Text("What's going on?").font(DS.Font.title)
            ForEach(["Too much to do", "Don't know where to start", "Anxious about something", "Just exhausted"], id: \.self) { f in
                Button { feeling = f; Haptics.tap(); withAnimation { step = 2 } } label: {
                    Text(f).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(DS.Palette.calm)
            }
        }
    }

    // 3. Shrink the day.
    private var shrink: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(feeling == "Just exhausted" ? "Rest is productive too." : "Let's make today smaller.").font(DS.Font.title)
                if feeling != "Just exhausted", let t = tiny {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("JUST THIS").font(.caption.weight(.bold)).foregroundStyle(DS.Palette.accent)
                            Text(t.microSteps.first { !$0.done }?.text ?? t.title).font(DS.Font.headline)
                            Button("Do it for 5 minutes") { focusTask = t }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                        }
                    }
                }
                if feeling == "Anxious about something" {
                    Button { showDump = true } label: { Label("Get the worry out of your head", systemImage: "brain.head.profile") }
                }
                Button {
                    lightened = lighten()
                } label: { Label(lightened.map { "Moved \($0) to tomorrow ✓" } ?? "Move everything non-urgent to tomorrow", systemImage: "arrow.uturn.forward") }
                .disabled(lightened != nil)
                Toggle(isOn: $calm) { Label("Calm mode for now", systemImage: "leaf") }
                NavigationLink { DopamineMenuView() } label: { Label("Pick something from my dopamine menu", systemImage: "fork.knife") }
                Button("I feel better") { Haptics.success(); dismiss() }.buttonStyle(.borderedProminent).tint(DS.Palette.calm).frame(maxWidth: .infinity)
            }
        }
    }

    /// Today's and overdue tasks that aren't high priority or timed go to tomorrow.
    private func lighten() -> Int {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let move = tasks.filter { !$0.isDone && ($0.dueDate ?? .distantFuture) < end && $0.priority != .high && !$0.hasDueTime }
        move.forEach { TaskActions.reschedule($0, to: end) }
        Haptics.success()
        return move.count
    }
}
