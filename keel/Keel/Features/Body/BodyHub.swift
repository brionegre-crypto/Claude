import SwiftUI
import SwiftData

// MARK: - Medications on Body: today's doses, add a medication, refills, how it's working

struct BodyMedsCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @Query(sort: \MedDose.takenAt, order: .reverse) private var doses: [MedDose]
    @State private var adding = false
    @State private var logging = false
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let active = meds.filter(\.isActive)
        let todaysDoses = doses.filter { Calendar.current.isDateInToday($0.day) }
        let ratings = DoseEffect.ratings
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Medications", systemImage: "pills.fill").font(DS.Font.headline).foregroundStyle(.mint)
                Spacer()
                Button { logging = true } label: { Label("Log a dose", systemImage: "checkmark.circle.fill").font(DS.Font.caption.weight(.semibold)) }
                    .buttonStyle(.borderedProminent).tint(.mint)
                Button { adding = true } label: { Label("Add", systemImage: "plus").font(DS.Font.caption.weight(.semibold)) }
                    .buttonStyle(.bordered).tint(.mint)
            }
            if active.isEmpty {
                Text("Add your medications to get reminders with a Taken button, refill warnings, and always know whether you already took it.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text(MedEngine.statusSentence(ctx: ctx)).font(DS.Font.caption)
                ForEach(active) { m in
                    ForEach(m.times.sorted(), id: \.self) { slot in MedDoseRow(med: m, slot: slot, doses: doses) }
                }
                // How did it work? One tap per dose taken today.
                ForEach(todaysDoses.filter { ratings[$0.id.uuidString] == nil }.prefix(3)) { d in
                    if let m = meds.first(where: { $0.id == d.medicationId }) {
                        HStack(spacing: 6) {
                            Text("How's \(m.name) working today?").font(.caption)
                            Spacer()
                            ForEach(1...5, id: \.self) { r in
                                Button("\(r)") { DoseEffect.rate(d, r); tick += 1; Haptics.tap() }
                                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                            }
                        }
                    }
                }
                // Refills: how many days you have left.
                ForEach(active.filter { $0.pillsLeft != nil }) { m in
                    let perDay = max(1, m.times.count)
                    let daysLeft = (m.pillsLeft ?? 0) / perDay
                    if daysLeft <= 14 {
                        HStack {
                            Label("\(m.name): about \(daysLeft) day\(daysLeft == 1 ? "" : "s") left", systemImage: "cross.vial")
                                .font(.caption).foregroundStyle(daysLeft <= 5 ? .red : .orange)
                            Spacer()
                            Button("I ordered it") {
                                let t = TaskItem(title: "Pick up \(m.name) refill", dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), priority: .medium)
                                t.listName = "Errands"; ctx.insert(t); try? CalendarService.shared.push(t)
                                UndoCenter.shared.notify("Reminder to pick it up in 2 days")
                            }
                            .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
                ForEach(active) { m in
                    if let avg = DoseEffect.average(m, doses: doses) {
                        Text(String(format: "%@: rated %.1f of 5 for how well it works (last 2 weeks)", m.name, avg)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            RecentDosesList(meds: meds, doses: doses)
            NavigationLink { LazyView(MedsView()) } label: { Label("All medications & history", systemImage: "list.bullet").font(DS.Font.caption) }
        }
        .bodyCard()
        .sheet(isPresented: $adding) { MedEditor(med: nil) }
        .sheet(isPresented: $logging, onDismiss: { tick += 1 }) { LogDoseSheet() }
    }
}

// MARK: - Every health screen, in one place

struct HealthTilesSection: View {
    let extras: HealthExtras
    private struct Tile: Identifiable { let id: String; let title: String; let icon: String; let color: Color; let dest: () -> AnyView }

    private var tiles: [Tile] {
        [
            Tile(id: "strength", title: "Training", icon: "dumbbell.fill", color: BodyStyle.swell, dest: { BodyHubs.training }),
            Tile(id: "bioage", title: "Biological age", icon: "hourglass.circle.fill", color: .purple, dest: { AnyView(BioAgeView()) }),
            Tile(id: "records", title: "Medical", icon: "cross.vial.fill", color: .red, dest: { BodyHubs.medical }),
            Tile(id: "biology", title: "Biology", icon: "drop.fill", color: .red, dest: { AnyView(BiologyView()) }),
            Tile(id: "ask", title: "Ask about my body", icon: "sparkles", color: .indigo, dest: { AnyView(AskBodyView()) }),
            Tile(id: "metrics", title: "Health metrics", icon: "heart.text.clipboard", color: .red, dest: { BodyHubs.metrics }),
            Tile(id: "guides", title: "Metric guides", icon: "book.pages", color: .indigo, dest: { AnyView(MetricGuideIndex()) }),
            Tile(id: "map", title: "Recovery map", icon: "figure.stand", color: BodyStyle.swell, dest: { AnyView(BodyMapView()) }),
            Tile(id: "meds", title: "Medications", icon: "pills.fill", color: .mint, dest: { BodyHubs.meds }),
            Tile(id: "symptoms", title: "Symptoms", icon: "thermometer.medium", color: .pink, dest: { AnyView(SymptomsView()) }),
            Tile(id: "bp", title: "Blood pressure", icon: "heart.text.square.fill", color: .red, dest: { AnyView(BloodPressureView()) }),
            Tile(id: "weight", title: "Weight", icon: "scalemass.fill", color: .blue, dest: { AnyView(WeightView(x: extras)) }),
            Tile(id: "food", title: "Food", icon: "fork.knife.circle.fill", color: .green, dest: { BodyHubs.food }),
            Tile(id: "sleepSounds", title: "Sleep sounds", icon: "moon.zzz.fill", color: BodyStyle.anchor, dest: { AnyView(SleepSoundsView()) }),
            Tile(id: "breathe", title: "Breathe", icon: "wind", color: .teal, dest: { AnyView(BreatheView()) }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health").font(DS.Font.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(tiles) { t in
                    NavigationLink { LazyView(t.dest()) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.icon).font(.title3).foregroundStyle(t.color)
                            Text(t.title).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2).foregroundStyle(DS.Palette.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


/// Body's combined screens: one Food place (today, log, scan, library, diet guide, drinks, fasting) and one
/// Medications place (daily and as-needed), instead of a tile for each.
@MainActor
enum BodyHubs {
    private static func tool<V: View>(_ id: String, _ title: String, _ icon: String, @ViewBuilder _ v: @escaping () -> V) -> HubTool {
        HubTool(id: id, title: title, icon: icon, keywords: "", dest: { AnyView(v()) })
    }

    static var food: AnyView {
        let spec = ToolHubSpec(id: "bodyFood", title: "Food", icon: "fork.knife.circle.fill", keywords: "", group: "food", intro: "", members: [])
        return AnyView(ToolHubView(spec: spec, tools: [
            (tool("b.food", "Today", "fork.knife.circle.fill") { NutritionView() }, "Today"),
            (tool("b.log", "Log", "fork.knife") { LogFoodView() }, "Log a meal"),
            (tool("b.scan", "Scan", "barcode.viewfinder") { FoodScanView() }, "Scan"),
            (tool("b.library", "Library", "books.vertical.fill") { FoodLibraryView() }, "Library"),
            (tool("b.diet", "Diet guide", "book.closed.fill") { DietGuideView() }, "Diet guide"),
            (tool("b.drinks", "Drinks", "cup.and.saucer.fill") { ScrollView { VStack(spacing: 16) { DrinksCard(); CaffeineCurveCard() }.padding() }.navigationTitle("Caffeine & water") }, "Drinks"),
            (tool("b.fast", "Fasting", "timer") { FastingView() }, "Fasting"),
        ]))
    }

    /// Strength, cardio and every workout: one Training place.
    static var training: AnyView {
        let spec = ToolHubSpec(id: "bodyTraining", title: "Training", icon: "dumbbell.fill", keywords: "", group: "food", intro: "", members: [])
        return AnyView(ToolHubView(spec: spec, tools: [
            (tool("b.strength", "Strength", "dumbbell.fill") { StrengthHomeView() }, "Strength"),
            (tool("b.cardio", "Cardio & load", "heart.circle.fill") { CardioChartsView() }, "Cardio & load"),
            (tool("b.workouts", "Workouts", "figure.run") { WorkoutHistoryView() }, "Workouts"),
            (tool("b.recovery", "Recovery", "figure.stand") { BodyMapView() }, "Recovery"),
        ]))
    }

    /// Records, your emergency medical card and the summary for your doctor: one Medical place.
    static var medical: AnyView {
        let spec = ToolHubSpec(id: "bodyMedical", title: "Medical", icon: "cross.vial.fill", keywords: "", group: "food", intro: "", members: [])
        return AnyView(ToolHubView(spec: spec, tools: [
            (tool("b.records", "Records", "cross.vial.fill") { HealthRecordsView() }, "Records"),
            (tool("b.card", "Medical card", "staroflife.fill") { MedicalCardView() }, "Medical card"),
            (tool("b.doctor", "For my doctor", "stethoscope") { DoctorSummaryView() }, "For my doctor"),
        ]))
    }

    /// Every Apple Health measurement and the long-view trends of your Body scores, together.
    static var metrics: AnyView {
        let spec = ToolHubSpec(id: "bodyMetrics", title: "Health metrics", icon: "heart.text.clipboard", keywords: "", group: "food", intro: "", members: [])
        return AnyView(ToolHubView(spec: spec, tools: [
            (tool("b.metrics", "All metrics", "heart.text.clipboard") { HealthMetricsView() }, "All metrics"),
            (tool("b.trends", "90-day trends", "chart.xyaxis.line") { BodyTrendsView() }, "Score trends"),
        ]))
    }

    static var meds: AnyView {
        let spec = ToolHubSpec(id: "bodyMeds", title: "Medications", icon: "pills.fill", keywords: "", group: "food", intro: "", members: [])
        return AnyView(ToolHubView(spec: spec, tools: [
            (tool("b.meds", "Daily", "pills.fill") { MedsView() }, "Daily"),
            (tool("b.prn", "As needed", "cross.case.fill") { PRNView() }, "As needed"),
        ]))
    }
}
