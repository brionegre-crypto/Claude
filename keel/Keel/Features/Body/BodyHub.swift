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
            NavigationLink { MedsView() } label: { Label("All medications & history", systemImage: "list.bullet").font(DS.Font.caption) }
        }
        .bodyCard()
        .sheet(isPresented: $adding) { MedEditor(med: nil) }
        .sheet(isPresented: $logging, onDismiss: { tick += 1 }) { LogDoseSheet() }
    }
}

// MARK: - Every health screen, in one place

struct HealthTilesSection: View {
    let extras: HealthExtras
    private struct Tile: Identifiable { let id: String; let title: String; let icon: String; let color: Color; let dest: AnyView }

    private var tiles: [Tile] {
        [
            Tile(id: "map", title: "Body map", icon: "figure.stand", color: BodyStyle.swell, dest: AnyView(BodyMapView())),
            Tile(id: "meds", title: "Medications", icon: "pills.fill", color: .mint, dest: AnyView(MedsView())),
            Tile(id: "prn", title: "As-needed medicines", icon: "cross.case.fill", color: .mint, dest: AnyView(PRNView())),
            Tile(id: "symptoms", title: "Symptoms", icon: "thermometer.medium", color: .pink, dest: AnyView(SymptomsView())),
            Tile(id: "bp", title: "Blood pressure", icon: "heart.text.square.fill", color: .red, dest: AnyView(BloodPressureView())),
            Tile(id: "weight", title: "Weight", icon: "scalemass.fill", color: .blue, dest: AnyView(WeightView(x: extras))),
            Tile(id: "food", title: "Food today", icon: "fork.knife.circle.fill", color: .green, dest: AnyView(NutritionView())),
            Tile(id: "meal", title: "Log a meal", icon: "text.bubble.fill", color: .green, dest: AnyView(DescribeMealView())),
            Tile(id: "scan", title: "Scan food", icon: "barcode.viewfinder", color: .green, dest: AnyView(FoodScanView())),
            Tile(id: "library", title: "Food library", icon: "books.vertical.fill", color: .green, dest: AnyView(FoodLibraryView())),
            Tile(id: "diet", title: "Diet guide", icon: "book.closed.fill", color: .green, dest: AnyView(DietGuideView())),
            Tile(id: "drinks", title: "Caffeine & water", icon: "cup.and.saucer.fill", color: .brown, dest: AnyView(ScrollView { VStack(spacing: 16) { DrinksCard(); CaffeineCurveCard() }.padding() }.navigationTitle("Caffeine & water"))),
            Tile(id: "fast", title: "Fasting", icon: "timer", color: .green, dest: AnyView(FastingView())),
            Tile(id: "workouts", title: "Workouts", icon: "figure.run", color: BodyStyle.swell, dest: AnyView(WorkoutHistoryView())),
            Tile(id: "trends", title: "90-day trends", icon: "chart.xyaxis.line", color: .purple, dest: AnyView(BodyTrendsView())),
            Tile(id: "sleepSounds", title: "Sleep sounds", icon: "moon.zzz.fill", color: BodyStyle.anchor, dest: AnyView(SleepSoundsView())),
            Tile(id: "breathe", title: "Breathe", icon: "wind", color: .teal, dest: AnyView(BreatheView())),
            Tile(id: "card", title: "Medical card", icon: "staroflife.fill", color: .red, dest: AnyView(MedicalCardView())),
            Tile(id: "doctor", title: "For my doctor", icon: "stethoscope", color: .indigo, dest: AnyView(DoctorSummaryView())),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health").font(DS.Font.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(tiles) { t in
                    NavigationLink { t.dest } label: {
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
