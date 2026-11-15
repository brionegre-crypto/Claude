import SwiftUI
import Charts

// MARK: - Strength: log lifts, see personal bests, get told what to lift next time, and see which muscles are worked

/// Muscle groups, each mapped onto the body map's regions.
enum Muscle: String, CaseIterable, Codable, Identifiable {
    case chest, shoulders, rearDelts, biceps, triceps, forearms, upperBack, lats, lowerBack, abs, glutes, quads, hamstrings, calves, hips
    var id: String { rawValue }
    var name: String {
        switch self {
        case .chest: "Chest"
        case .shoulders: "Shoulders"
        case .rearDelts: "Rear shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .upperBack: "Upper back"
        case .lats: "Lats"
        case .lowerBack: "Lower back"
        case .abs: "Core"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        case .hips: "Hips"
        }
    }
    /// Body-map regions this muscle covers.
    var regions: [String] {
        switch self {
        case .chest: ["f.chest"]
        case .shoulders: ["f.shoulderL", "f.shoulderR"]
        case .rearDelts: ["b.shoulderL", "b.shoulderR"]
        case .biceps: ["f.armL", "f.armR"]
        case .triceps: ["b.armL", "b.armR"]
        case .forearms: ["f.forearmL", "f.forearmR", "b.forearmL", "b.forearmR"]
        case .upperBack: ["b.upperback"]
        case .lats: ["b.lats"]
        case .lowerBack: ["b.lowerback"]
        case .abs: ["f.abs"]
        case .glutes: ["b.glutes"]
        case .quads: ["f.quadL", "f.quadR"]
        case .hamstrings: ["b.hamL", "b.hamR"]
        case .calves: ["b.calfL", "b.calfR"]
        case .hips: ["f.hips"]
        }
    }
}

struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let equipment: String
    let primary: [Muscle]
    let secondary: [Muscle]
    var bodyweight: Bool { equipment == "Bodyweight" }
}

@MainActor
enum ExerciseLibrary {
    /// "Name|Equipment|primary,primary|secondary,secondary"
    private static let raw = """
    Bench Press|Barbell|chest|triceps,shoulders
    Incline Bench Press|Barbell|chest,shoulders|triceps
    Decline Bench Press|Barbell|chest|triceps
    Dumbbell Bench Press|Dumbbell|chest|triceps,shoulders
    Incline Dumbbell Press|Dumbbell|chest,shoulders|triceps
    Dumbbell Fly|Dumbbell|chest|shoulders
    Cable Fly|Cable|chest|shoulders
    Pec Deck|Machine|chest|shoulders
    Chest Press Machine|Machine|chest|triceps,shoulders
    Push-up|Bodyweight|chest|triceps,shoulders,abs
    Dip|Bodyweight|chest,triceps|shoulders
    Overhead Press|Barbell|shoulders|triceps,upperBack
    Dumbbell Shoulder Press|Dumbbell|shoulders|triceps
    Arnold Press|Dumbbell|shoulders|triceps
    Machine Shoulder Press|Machine|shoulders|triceps
    Lateral Raise|Dumbbell|shoulders|upperBack
    Cable Lateral Raise|Cable|shoulders|
    Front Raise|Dumbbell|shoulders|
    Rear Delt Fly|Dumbbell|rearDelts|upperBack
    Face Pull|Cable|rearDelts,upperBack|biceps
    Upright Row|Barbell|shoulders,upperBack|biceps
    Shrug|Dumbbell|upperBack|forearms
    Deadlift|Barbell|hamstrings,glutes,lowerBack|upperBack,forearms,quads
    Romanian Deadlift|Barbell|hamstrings,glutes|lowerBack
    Dumbbell Romanian Deadlift|Dumbbell|hamstrings,glutes|lowerBack
    Sumo Deadlift|Barbell|glutes,hamstrings,quads|lowerBack,upperBack
    Trap Bar Deadlift|Trap bar|quads,glutes,hamstrings|lowerBack,upperBack
    Barbell Row|Barbell|upperBack,lats|biceps,rearDelts,lowerBack
    Dumbbell Row|Dumbbell|lats,upperBack|biceps,rearDelts
    Seated Cable Row|Cable|upperBack,lats|biceps,rearDelts
    T-Bar Row|Barbell|upperBack,lats|biceps
    Chest-Supported Row|Machine|upperBack,lats|biceps,rearDelts
    Pull-up|Bodyweight|lats|biceps,upperBack
    Chin-up|Bodyweight|lats,biceps|upperBack
    Lat Pulldown|Cable|lats|biceps,upperBack
    Straight-Arm Pulldown|Cable|lats|triceps
    Assisted Pull-up|Machine|lats|biceps
    Inverted Row|Bodyweight|upperBack,lats|biceps
    Back Extension|Bodyweight|lowerBack,glutes|hamstrings
    Good Morning|Barbell|hamstrings,lowerBack|glutes
    Barbell Curl|Barbell|biceps|forearms
    Dumbbell Curl|Dumbbell|biceps|forearms
    Hammer Curl|Dumbbell|biceps,forearms|
    Incline Dumbbell Curl|Dumbbell|biceps|
    Preacher Curl|Machine|biceps|
    Cable Curl|Cable|biceps|forearms
    Concentration Curl|Dumbbell|biceps|
    Tricep Pushdown|Cable|triceps|
    Overhead Tricep Extension|Cable|triceps|
    Skull Crusher|Barbell|triceps|
    Close-Grip Bench Press|Barbell|triceps,chest|shoulders
    Dumbbell Kickback|Dumbbell|triceps|
    Bench Dip|Bodyweight|triceps|chest,shoulders
    Wrist Curl|Dumbbell|forearms|
    Farmer's Carry|Dumbbell|forearms,upperBack|abs,glutes
    Back Squat|Barbell|quads,glutes|hamstrings,lowerBack,abs
    Front Squat|Barbell|quads|glutes,abs,upperBack
    Goblet Squat|Dumbbell|quads,glutes|abs
    Hack Squat|Machine|quads|glutes
    Leg Press|Machine|quads,glutes|hamstrings
    Bulgarian Split Squat|Dumbbell|quads,glutes|hamstrings
    Lunge|Dumbbell|quads,glutes|hamstrings
    Walking Lunge|Dumbbell|quads,glutes|hamstrings,calves
    Step-up|Dumbbell|quads,glutes|hamstrings
    Leg Extension|Machine|quads|
    Leg Curl|Machine|hamstrings|calves
    Seated Leg Curl|Machine|hamstrings|
    Nordic Curl|Bodyweight|hamstrings|glutes
    Hip Thrust|Barbell|glutes|hamstrings
    Glute Bridge|Bodyweight|glutes|hamstrings
    Cable Kickback|Cable|glutes|
    Hip Abduction|Machine|hips,glutes|
    Hip Adduction|Machine|hips|
    Standing Calf Raise|Machine|calves|
    Seated Calf Raise|Machine|calves|
    Bodyweight Squat|Bodyweight|quads,glutes|
    Jump Squat|Bodyweight|quads,glutes|calves
    Box Jump|Bodyweight|quads,glutes|calves
    Kettlebell Swing|Kettlebell|glutes,hamstrings|lowerBack,shoulders,abs
    Kettlebell Goblet Squat|Kettlebell|quads,glutes|abs
    Turkish Get-up|Kettlebell|shoulders,abs|glutes,quads
    Clean|Barbell|glutes,hamstrings,upperBack|quads,shoulders
    Power Clean|Barbell|glutes,hamstrings,upperBack|quads,shoulders
    Snatch|Barbell|glutes,shoulders,upperBack|quads,hamstrings
    Thruster|Barbell|quads,shoulders|glutes,triceps
    Plank|Bodyweight|abs|shoulders,glutes
    Side Plank|Bodyweight|abs|hips
    Crunch|Bodyweight|abs|
    Hanging Leg Raise|Bodyweight|abs|hips,forearms
    Cable Crunch|Cable|abs|
    Russian Twist|Bodyweight|abs|
    Ab Wheel Rollout|Bodyweight|abs|lats,shoulders
    Dead Bug|Bodyweight|abs|
    Mountain Climber|Bodyweight|abs|shoulders,quads
    Burpee|Bodyweight|quads,chest|shoulders,abs
    Pallof Press|Cable|abs|
    Landmine Press|Barbell|shoulders,chest|triceps
    Sled Push|Machine|quads,glutes|calves
    Battle Ropes|Other|shoulders|abs,forearms
    Resistance Band Row|Band|upperBack,lats|biceps
    Resistance Band Pull-apart|Band|rearDelts,upperBack|
    Smith Machine Squat|Machine|quads,glutes|hamstrings
    Smith Machine Bench Press|Machine|chest|triceps,shoulders
    Pendlay Row|Barbell|upperBack,lats|biceps,lowerBack
    Zercher Squat|Barbell|quads,glutes|abs,upperBack
    Single-Leg Romanian Deadlift|Dumbbell|hamstrings,glutes|lowerBack,abs
    Copenhagen Plank|Bodyweight|hips,abs|
    Reverse Fly Machine|Machine|rearDelts|upperBack
    Pullover|Dumbbell|lats,chest|triceps
    Muscle-up|Bodyweight|lats,chest|triceps,biceps
    Pistol Squat|Bodyweight|quads,glutes|abs
    Calf Raise|Bodyweight|calves|
    Floor Press|Barbell|chest,triceps|shoulders
    Svend Press|Plate|chest|shoulders
    Decline Push-up|Bodyweight|chest,shoulders|triceps
    Incline Push-up|Bodyweight|chest|triceps
    Diamond Push-up|Bodyweight|triceps,chest|shoulders
    Pike Push-up|Bodyweight|shoulders|triceps
    Handstand Push-up|Bodyweight|shoulders|triceps,upperBack
    Low-to-High Cable Fly|Cable|chest|shoulders
    Incline Cable Fly|Cable|chest|shoulders
    Dumbbell Pullover|Dumbbell|chest,lats|triceps
    Push Press|Barbell|shoulders|triceps,quads
    Seated Dumbbell Press|Dumbbell|shoulders|triceps
    Single-Arm Landmine Press|Barbell|shoulders|chest,abs
    Lu Raise|Dumbbell|shoulders|upperBack
    Reverse Cable Fly|Cable|rearDelts|upperBack
    Band Face Pull|Band|rearDelts|upperBack
    Y-Raise|Dumbbell|upperBack,rearDelts|
    Barbell Shrug|Barbell|upperBack|forearms
    Rack Pull|Barbell|upperBack,glutes|hamstrings,forearms
    Deficit Deadlift|Barbell|hamstrings,glutes,lowerBack|quads
    Stiff-Leg Deadlift|Barbell|hamstrings|glutes,lowerBack
    Kettlebell Deadlift|Kettlebell|glutes,hamstrings|lowerBack
    Meadows Row|Barbell|lats|upperBack,biceps
    Kroc Row|Dumbbell|lats,upperBack|biceps,forearms
    Seal Row|Barbell|upperBack|lats,rearDelts
    Single-Arm Cable Row|Cable|lats|biceps
    Close-Grip Lat Pulldown|Cable|lats|biceps
    Wide-Grip Pull-up|Bodyweight|lats|upperBack
    Neutral-Grip Pull-up|Bodyweight|lats,biceps|
    Weighted Pull-up|Other|lats|biceps,upperBack
    Machine Row|Machine|upperBack,lats|biceps
    Renegade Row|Dumbbell|lats,abs|shoulders
    Reverse Hyperextension|Machine|glutes,lowerBack|hamstrings
    EZ-Bar Curl|Barbell|biceps|forearms
    Spider Curl|Dumbbell|biceps|
    Bayesian Cable Curl|Cable|biceps|
    Reverse Curl|Barbell|forearms,biceps|
    Zottman Curl|Dumbbell|biceps,forearms|
    Drag Curl|Barbell|biceps|
    Rope Pushdown|Cable|triceps|
    Single-Arm Pushdown|Cable|triceps|
    JM Press|Barbell|triceps|chest
    Dumbbell Overhead Extension|Dumbbell|triceps|
    Tate Press|Dumbbell|triceps|
    Reverse Wrist Curl|Dumbbell|forearms|
    Dead Hang|Bodyweight|forearms,lats|
    Suitcase Carry|Dumbbell|abs,forearms|glutes
    Box Squat|Barbell|quads,glutes|hamstrings
    Pause Squat|Barbell|quads|glutes,abs
    Safety Bar Squat|Barbell|quads,glutes|upperBack
    Belt Squat|Machine|quads,glutes|
    Pendulum Squat|Machine|quads|glutes
    Sissy Squat|Bodyweight|quads|
    Split Squat|Dumbbell|quads,glutes|
    Reverse Lunge|Dumbbell|glutes,quads|hamstrings
    Lateral Lunge|Dumbbell|quads,hips|glutes
    Curtsy Lunge|Dumbbell|glutes,hips|quads
    Single-Leg Leg Press|Machine|quads,glutes|
    Single-Leg Hip Thrust|Bodyweight|glutes|hamstrings
    Frog Pump|Bodyweight|glutes|
    Glute Ham Raise|Machine|hamstrings|glutes
    Kettlebell Romanian Deadlift|Kettlebell|hamstrings,glutes|
    Cossack Squat|Bodyweight|quads,hips|glutes
    Wall Sit|Bodyweight|quads|
    Donkey Calf Raise|Machine|calves|
    Single-Leg Calf Raise|Bodyweight|calves|
    Tibialis Raise|Bodyweight|calves|
    Kettlebell Clean|Kettlebell|glutes,hamstrings|shoulders
    Kettlebell Snatch|Kettlebell|glutes,shoulders|hamstrings,upperBack
    Kettlebell Press|Kettlebell|shoulders|triceps
    Kettlebell Row|Kettlebell|lats,upperBack|biceps
    Hang Clean|Barbell|upperBack,glutes|quads,hamstrings
    Clean and Jerk|Barbell|quads,shoulders,glutes|upperBack,triceps
    Wall Ball|Other|quads,shoulders|glutes
    Medicine Ball Slam|Other|abs,shoulders|lats
    Bicycle Crunch|Bodyweight|abs|
    Hollow Hold|Bodyweight|abs|
    Leg Raise|Bodyweight|abs|hips
    Toes to Bar|Bodyweight|abs|lats,forearms
    V-Up|Bodyweight|abs|
    Bird Dog|Bodyweight|abs,lowerBack|glutes
    Cable Woodchop|Cable|abs|shoulders
    Decline Sit-up|Bodyweight|abs|hips
    L-Sit|Bodyweight|abs|triceps
    Farmer's Walk|Kettlebell|forearms,upperBack|abs
    Sled Pull|Other|hamstrings,glutes|upperBack
    Rowing Machine|Machine|upperBack,quads|lats,biceps
    Assault Bike|Machine|quads|shoulders
    Jump Rope|Other|calves|shoulders
    Bear Crawl|Bodyweight|shoulders,abs|quads
    Band Pull-apart|Band|rearDelts,upperBack|
    Band Squat|Band|quads,glutes|
    Band Glute Kickback|Band|glutes|
    Band Lateral Walk|Band|hips,glutes|
    Band Chest Press|Band|chest|triceps
    Band Overhead Press|Band|shoulders|triceps
    Band Curl|Band|biceps|
    Band Tricep Extension|Band|triceps|
    """

    static let all: [Exercise] = raw.split(separator: "\n").compactMap { line in
        let p = line.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 4 else { return nil }
        func muscles(_ s: String) -> [Muscle] { s.split(separator: ",").compactMap { Muscle(rawValue: String($0)) } }
        let id = p[0].lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "")
        return Exercise(id: id, name: p[0], equipment: p[1], primary: muscles(p[2]), secondary: muscles(p[3]))
    }

    static func exercise(_ id: String) -> Exercise? { byId[id] ?? StrengthStore.custom.first { $0.id == id } }
    private static let byId: [String: Exercise] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
}

// MARK: Logged workouts

struct LiftSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var reps: Int
    var weight: Double          // in the unit you log in (kg or lb), 0 for bodyweight
    var done = false
    var warmup = false
    var rpe: Int?               // how hard, 6–10
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseId: String
    var sets: [LiftSet]
    var note = ""
}

struct StrengthSession: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var start = Date()
    var end: Date?
    var exercises: [LoggedExercise] = []

    var workingSets: [(LoggedExercise, LiftSet)] { exercises.flatMap { e in e.sets.filter { $0.done && !$0.warmup }.map { (e, $0) } } }
    var volume: Double { workingSets.reduce(0) { $0 + Double($1.1.reps) * $1.1.weight } }
    var setCount: Int { workingSets.count }
    var minutes: Int { Int(((end ?? Date()).timeIntervalSince(start) / 60).rounded()) }
}

struct StrengthRoutine: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var items: [Item]
    struct Item: Codable, Hashable { var exerciseId: String; var sets: Int; var reps: Int }
}

struct CustomExercise: Codable, Hashable { var name: String; var equipment: String; var primary: [String]; var secondary: [String] }

@MainActor
enum StrengthStore {
    private static var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("strength.json")
    }
    private static var cached: [StrengthSession]?

    static var sessions: [StrengthSession] {
        get {
            if let cached { return cached }
            let s = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([StrengthSession].self, from: $0) } ?? []
            cached = s
            return s
        }
        set {
            cached = newValue
            if let d = try? JSONEncoder().encode(newValue) { try? d.write(to: url, options: .atomic) }
        }
    }

    static let unitKey = "strength.unit"
    static var unit: String { UserDefaults.standard.string(forKey: unitKey) ?? (Locale.current.measurementSystem == .metric ? "kg" : "lb") }
    static var increment: Double { unit == "kg" ? 2.5 : 5 }

    static let routinesKey = "strength.routines"
    static var routines: [StrengthRoutine] {
        get {
            let mine: [StrengthRoutine] = LocalLog.load(routinesKey)
            return mine.isEmpty ? builtInRoutines : mine
        }
        set { LocalLog.save(newValue, routinesKey) }
    }

    static let customKey = "strength.custom"
    static var custom: [Exercise] {
        (LocalLog.load(customKey) as [CustomExercise]).map { c in
            Exercise(id: "custom-" + c.name.lowercased().replacingOccurrences(of: " ", with: "-"), name: c.name, equipment: c.equipment,
                     primary: c.primary.compactMap(Muscle.init(rawValue:)), secondary: c.secondary.compactMap(Muscle.init(rawValue:)))
        }
    }

    static let builtInRoutines: [StrengthRoutine] = [
        StrengthRoutine(name: "Full body (beginner)", items: [.init(exerciseId: "goblet-squat", sets: 3, reps: 10), .init(exerciseId: "dumbbell-bench-press", sets: 3, reps: 10),
                                                            .init(exerciseId: "dumbbell-row", sets: 3, reps: 10), .init(exerciseId: "dumbbell-romanian-deadlift", sets: 3, reps: 10),
                                                            .init(exerciseId: "plank", sets: 3, reps: 30)]),
        StrengthRoutine(name: "Push", items: [.init(exerciseId: "bench-press", sets: 4, reps: 8), .init(exerciseId: "overhead-press", sets: 3, reps: 8),
                                              .init(exerciseId: "incline-dumbbell-press", sets: 3, reps: 10), .init(exerciseId: "lateral-raise", sets: 3, reps: 15),
                                              .init(exerciseId: "tricep-pushdown", sets: 3, reps: 12)]),
        StrengthRoutine(name: "Pull", items: [.init(exerciseId: "deadlift", sets: 3, reps: 5), .init(exerciseId: "pull-up", sets: 3, reps: 8),
                                              .init(exerciseId: "seated-cable-row", sets: 3, reps: 10), .init(exerciseId: "face-pull", sets: 3, reps: 15),
                                              .init(exerciseId: "dumbbell-curl", sets: 3, reps: 12)]),
        StrengthRoutine(name: "Legs", items: [.init(exerciseId: "back-squat", sets: 4, reps: 6), .init(exerciseId: "romanian-deadlift", sets: 3, reps: 8),
                                              .init(exerciseId: "leg-press", sets: 3, reps: 12), .init(exerciseId: "leg-curl", sets: 3, reps: 12),
                                              .init(exerciseId: "standing-calf-raise", sets: 4, reps: 12)]),
        StrengthRoutine(name: "Upper", items: [.init(exerciseId: "bench-press", sets: 3, reps: 8), .init(exerciseId: "barbell-row", sets: 3, reps: 8),
                                               .init(exerciseId: "dumbbell-shoulder-press", sets: 3, reps: 10), .init(exerciseId: "lat-pulldown", sets: 3, reps: 10),
                                               .init(exerciseId: "hammer-curl", sets: 2, reps: 12), .init(exerciseId: "overhead-tricep-extension", sets: 2, reps: 12)]),
        StrengthRoutine(name: "Lower", items: [.init(exerciseId: "trap-bar-deadlift", sets: 3, reps: 6), .init(exerciseId: "bulgarian-split-squat", sets: 3, reps: 10),
                                               .init(exerciseId: "hip-thrust", sets: 3, reps: 10), .init(exerciseId: "leg-extension", sets: 3, reps: 12),
                                               .init(exerciseId: "hanging-leg-raise", sets: 3, reps: 12)]),
    ]

    /// Estimated one-rep max (Epley): weight × (1 + reps / 30). Bodyweight moves use reps.
    static func e1RM(_ s: LiftSet) -> Double { s.weight > 0 ? s.weight * (1 + Double(s.reps) / 30) : Double(s.reps) }

    /// Best estimated 1RM per exercise, before a given session (for spotting new records).
    static func bests(before date: Date = .distantFuture, in list: [StrengthSession]? = nil) -> [String: Double] {
        var out: [String: Double] = [:]
        for s in (list ?? sessions) where s.start < date {
            for e in s.exercises {
                for set in e.sets where set.done && !set.warmup { out[e.exerciseId] = max(out[e.exerciseId] ?? 0, e1RM(set)) }
            }
        }
        return out
    }

    /// New personal records in this session.
    struct Record: Identifiable { let exercise: Exercise; let value: Double; var id: String { exercise.id } }

    static func records(in session: StrengthSession, history: [StrengthSession]? = nil) -> [Record] {
        let before = bests(before: session.start, in: history)
        var out: [Record] = []
        for e in session.exercises {
            let best = e.sets.filter { $0.done && !$0.warmup }.map(e1RM).max() ?? 0
            if best > 0, best > (before[e.exerciseId] ?? 0), before[e.exerciseId] != nil, let ex = ExerciseLibrary.exercise(e.exerciseId) { out.append(Record(exercise: ex, value: best)) }
        }
        return out
    }

    /// The last time you did this exercise.
    static func last(_ exerciseId: String, before date: Date = .distantFuture, in list: [StrengthSession]? = nil) -> LoggedExercise? {
        for s in (list ?? sessions).sorted(by: { $0.start > $1.start }) where s.start < date {
            if let e = s.exercises.first(where: { $0.exerciseId == exerciseId && $0.sets.contains { $0.done && !$0.warmup } }) { return e }
        }
        return nil
    }

    /// Progressive overload: if you hit your reps on every working set last time, add weight; otherwise repeat it.
    static func suggestion(_ exerciseId: String, targetReps: Int, in list: [StrengthSession]? = nil) -> (weight: Double, reps: Int, why: String)? {
        guard let last = last(exerciseId, in: list) else { return nil }
        let working = last.sets.filter { $0.done && !$0.warmup }
        guard let top = working.max(by: { $0.weight < $1.weight }) else { return nil }
        let hitAll = working.allSatisfy { $0.reps >= targetReps }
        let hard = working.contains { ($0.rpe ?? 8) >= 10 }
        if top.weight == 0 {
            return (0, top.reps + 1, "Last time \(top.reps) reps. Try one more.")
        }
        if hitAll && !hard {
            return (top.weight + increment, targetReps, "You hit every set last time. Add \(format(increment)).")
        }
        return (top.weight, targetReps, hard ? "Last time was a max effort. Repeat it and own it." : "Repeat \(format(top.weight)) until you get all your reps.")
    }

    static func format(_ w: Double) -> String {
        (w.rounded() == w ? String(Int(w)) : String(format: "%.1f", w)) + " " + unit
    }

    /// Working sets per muscle over the last `days` (primary counts 1, secondary ½).
    static func setsPerMuscle(days: Int = 7, now: Date = Date(), in list: [StrengthSession]? = nil) -> [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        for s in (list ?? sessions) where s.start > since {
            for (e, _) in s.workingSets {
                guard let ex = ExerciseLibrary.exercise(e.exerciseId) else { continue }
                for m in ex.primary { out[m, default: 0] += 1 }
                for m in ex.secondary { out[m, default: 0] += 0.5 }
            }
        }
        return out
    }

    /// How tired each muscle still is (0 fresh … 1 just hammered), fading over about 3 days.
    static func fatigue(now: Date = Date(), in list: [StrengthSession]? = nil) -> [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        for s in (list ?? sessions) {
            let hours = now.timeIntervalSince(s.end ?? s.start) / 3600
            guard hours >= 0, hours < 96 else { continue }
            let fade = exp(-hours / 36)
            for (e, set) in s.workingSets {
                guard let ex = ExerciseLibrary.exercise(e.exerciseId) else { continue }
                let effort = 0.12 * (Double(set.rpe ?? 8) / 8)
                for m in ex.primary { out[m, default: 0] += effort * fade }
                for m in ex.secondary { out[m, default: 0] += effort * 0.5 * fade }
            }
        }
        return out.mapValues { min(1, $0) }
    }

    /// Muscular strain for one session, 0–100: more hard sets → higher, levelling off like Swell.
    static func strain(_ s: StrengthSession) -> Int {
        let hard = s.workingSets.reduce(0.0) { $0 + Double($1.1.rpe ?? 8) / 8 }
        return Int((100 * (1 - exp(-hard / 18))).rounded())
    }

    /// Body-map glow from strength work (feeds Body map and Muscle freshness).
    static func regionLoad(now: Date = Date()) -> [String: Double] {
        var out: [String: Double] = [:]
        for (m, f) in fatigue(now: now) { for r in m.regions { out[r] = max(out[r] ?? 0, f) } }
        return out
    }
}

// MARK: - Screens

struct StrengthHomeView: View {
    @State private var sessions: [StrengthSession] = []
    @State private var active: StrengthSession?
    @State private var routines: [StrengthRoutine] = []
    @AppStorage(StrengthStore.unitKey) private var unit = Locale.current.measurementSystem == .metric ? "kg" : "lb"
    @AppStorage("strength.saveToHealth") private var saveHealth = true

    var body: some View {
        List {
            Section {
                KitIntro(icon: "dumbbell.fill", color: BodyStyle.swell, text: "Strength. Log your sets, and Keel tracks personal records, suggests what to lift next time (progressive overload), shows how many hard sets each muscle got this week, and how recovered each muscle is.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                BuildWorkoutCard(tide: BodyEngine.shared.today?.tide)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            let notes = StrengthCoach.plateaus(in: sessions) + [StrengthCoach.deload(days: BodyEngine.shared.days, sessions: sessions)].compactMap { $0 }
            if !notes.isEmpty {
                Section("Coach notes") { ForEach(notes, id: \.self) { Label($0, systemImage: "lightbulb.fill").font(.callout) } }
            }
            Section {
                Button { start(StrengthSession(name: "Workout")) } label: { Label("Start an empty workout", systemImage: "plus.circle.fill") }
                ForEach(routines) { r in
                    Button { start(from: r) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).foregroundStyle(DS.Palette.ink)
                            Text(r.items.compactMap { ExerciseLibrary.exercise($0.exerciseId)?.name }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                        }
                    }
                }
                .onDelete { idx in routines.remove(atOffsets: idx); StrengthStore.routines = routines }
            } header: { Text("Start") }
            Section("This week") {
                let perMuscle = StrengthStore.setsPerMuscle(in: sessions)
                if perMuscle.isEmpty {
                    Text("Log a workout to see hard sets per muscle. Around 10–20 a week per muscle is the sweet spot for most people.").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    Chart(Muscle.allCases.filter { (perMuscle[$0] ?? 0) > 0 }) { m in
                        BarMark(x: .value("Sets", perMuscle[m] ?? 0), y: .value("Muscle", m.name))
                            .foregroundStyle((perMuscle[m] ?? 0) >= 10 ? DS.Palette.calm.gradient : BodyStyle.swell.gradient)
                            .cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: [0, 10, 20]) }
                    .frame(height: CGFloat(max(3, perMuscle.count)) * 26)
                    Text("Hard sets per muscle in the last 7 days. Green: 10 or more.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                NavigationLink { LazyView(MuscleFreshnessView()) } label: { Label("Muscle freshness", systemImage: "figure.stand") }
            }
            let prs = StrengthStore.bests(in: sessions).sorted { $0.value > $1.value }.prefix(8)
            if !prs.isEmpty {
                Section("Best lifts (estimated 1-rep max)") {
                    ForEach(Array(prs), id: \.key) { id, best in
                        if let ex = ExerciseLibrary.exercise(id) {
                            NavigationLink { LazyView(ExerciseHistoryView(exercise: ex)) } label: {
                                HStack { Text(ex.name); Spacer(); Text(ex.bodyweight ? "\(Int(best)) reps" : StrengthStore.format(best)).monospacedDigit().foregroundStyle(BodyStyle.swell) }
                            }
                        }
                    }
                }
            }
            Section("History") {
                if sessions.isEmpty { Text("No workouts yet.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(sessions.sorted { $0.start > $1.start }.prefix(30)) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name).font(.headline)
                            Spacer()
                            Text("Strain \(StrengthStore.strain(s))").font(.caption.weight(.semibold)).foregroundStyle(BodyStyle.swell)
                        }
                        Text("\(s.start.formatted(date: .abbreviated, time: .shortened)) · \(s.minutes) min · \(s.setCount) sets · \(StrengthStore.format(s.volume)) total")
                            .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onDelete { idx in
                    let sorted = sessions.sorted { $0.start > $1.start }
                    let ids = idx.map { sorted[$0].id }
                    sessions.removeAll { ids.contains($0.id) }; StrengthStore.sessions = sessions
                }
            }
            Section {
                Picker("Units", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }.pickerStyle(.segmented)
                Toggle("Save workouts to Apple Health", isOn: $saveHealth)
            } footer: { Text("Turn this off if you also record strength workouts on your Apple Watch, so they aren't counted twice.") }
        }
        .navigationTitle("Strength")
        .onAppear { sessions = StrengthStore.sessions; routines = StrengthStore.routines }
        .fullScreenCover(item: $active) { s in
            NavigationStack {
                ActiveWorkoutView(session: s) { finished in
                    if let finished, finished.setCount > 0 {
                        sessions.append(finished); StrengthStore.sessions = sessions
                        StrengthHealth.save(finished)
                    }
                    active = nil
                }
            }
        }
    }

    private func start(_ s: StrengthSession) { active = s; Haptics.start() }
    private func start(from r: StrengthRoutine) {
        var s = StrengthSession(name: r.name)
        s.exercises = r.items.map { item in
            let sug = StrengthStore.suggestion(item.exerciseId, targetReps: item.reps)
            let w = sug?.weight ?? StrengthStore.last(item.exerciseId)?.sets.last?.weight ?? 0
            return LoggedExercise(exerciseId: item.exerciseId, sets: (0..<item.sets).map { _ in LiftSet(reps: sug?.reps ?? item.reps, weight: w) })
        }
        start(s)
    }
}

struct ActiveWorkoutView: View {
    @State var session: StrengthSession
    var done: (StrengthSession?) -> Void
    @State private var adding = false
    @State private var restEnds: Date?
    @AppStorage("strength.rest") private var restSeconds = 90
    @State private var summary: StrengthSession?
    @State private var saveRoutine = false
    @State private var routineName = ""

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: session.start, by: 1)) { tl in
                    HStack {
                        Label(Kit.clock(Int(tl.date.timeIntervalSince(session.start))), systemImage: "clock").monospacedDigit()
                        Spacer()
                        Text("\(session.setCount) sets · \(StrengthStore.format(session.volume))").font(.caption).monospacedDigit()
                    }
                    .font(.headline)
                }
                if let restEnds {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = Int(restEnds.timeIntervalSince(tl.date))
                        HStack {
                            Label(left > 0 ? "Rest \(Kit.clock(left))" : "Rest over: next set", systemImage: "timer")
                                .foregroundStyle(left > 0 ? BodyStyle.swell : DS.Palette.calm)
                            Spacer()
                            Button("+30s") { self.restEnds = restEnds.addingTimeInterval(30); scheduleRest() }.buttonStyle(.bordered).controlSize(.small)
                            Button("Skip") { self.restEnds = nil; Kit.cancel(["strength.rest"]) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        .monospacedDigit()
                    }
                }
            }
            ForEach($session.exercises) { $e in
                if let ex = ExerciseLibrary.exercise(e.exerciseId) {
                    Section {
                        if let sug = StrengthStore.suggestion(e.exerciseId, targetReps: e.sets.first?.reps ?? 8) {
                            Label(sug.why, systemImage: "arrow.up.right.circle").font(.caption).foregroundStyle(DS.Palette.calm)
                        }
                        ForEach($e.sets) { $set in
                            HStack(spacing: 10) {
                                Button { set.warmup.toggle() } label: {
                                    Text(set.warmup ? "W" : "\((e.sets.firstIndex(of: set) ?? 0) + 1)").font(.caption.weight(.bold))
                                        .frame(width: 24, height: 24).background(Circle().fill(set.warmup ? Color.orange.opacity(0.25) : Color.gray.opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                                if !ex.bodyweight {
                                    Stepper(value: $set.weight, in: 0...1000, step: StrengthStore.increment) {
                                        Text(StrengthStore.format(set.weight)).monospacedDigit().font(.callout)
                                    }
                                    .fixedSize()
                                }
                                Stepper(value: $set.reps, in: 0...100) { Text("× \(set.reps)").monospacedDigit().font(.callout) }.fixedSize()
                                Spacer(minLength: 0)
                                Button {
                                    set.done.toggle()
                                    if set.done { Haptics.done(); restEnds = Date().addingTimeInterval(Double(restSeconds)); scheduleRest() }
                                } label: {
                                    Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title3)
                                        .foregroundStyle(set.done ? DS.Palette.calm : DS.Palette.inkSoft)
                                }
                                .buttonStyle(.plain)
                            }
                            .contextMenu {
                                Menu("How hard (RPE)") {
                                    ForEach(6...10, id: \.self) { r in Button("\(r)\(r == 10 ? " · max" : "")") { set.rpe = r } }
                                }
                            }
                        }
                        .onDelete { e.sets.remove(atOffsets: $0) }
                        HStack {
                            Button("Add set", systemImage: "plus") {
                                let last = e.sets.last
                                e.sets.append(LiftSet(reps: last?.reps ?? 8, weight: last?.weight ?? 0))
                            }
                            Spacer()
                            if !ex.bodyweight, let top = e.sets.map(\.weight).max(), top > PlateMath.bar(StrengthStore.unit), !e.sets.contains(where: \.warmup) {
                                Button("Warm-ups") { e.sets.insert(contentsOf: PlateMath.warmups(to: top, unit: StrengthStore.unit, step: StrengthStore.increment), at: 0) }
                            }
                            if !ex.bodyweight, ["Barbell", "Trap bar"].contains(ex.equipment) {
                                NavigationLink { LazyView(PlateCalculatorView(weight: e.sets.map(\.weight).max() ?? PlateMath.bar(StrengthStore.unit), unit: StrengthStore.unit)) } label: { Text("Plates") }
                            }
                        }
                        .font(.caption).buttonStyle(.borderless)
                    } header: {
                        HStack {
                            Text(ex.name)
                            Spacer()
                            if let best = StrengthStore.bests()[ex.id] { Text("Best \(ex.bodyweight ? "\(Int(best)) reps" : StrengthStore.format(best))").font(.caption2) }
                        }
                    }
                }
            }
            .onDelete { session.exercises.remove(atOffsets: $0) }
            Section {
                Button("Add exercise", systemImage: "plus.circle.fill") { adding = true }
                Stepper("Rest timer: \(restSeconds) s", value: $restSeconds, in: 30...300, step: 15)
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Discard", role: .destructive) { Kit.cancel(["strength.rest"]); done(nil) } }
            ToolbarItem(placement: .confirmationAction) { Button("Finish") { finish() }.fontWeight(.semibold) }
        }
        .sheet(isPresented: $adding) {
            ExercisePicker { ex in
                let last = StrengthStore.last(ex.id)
                session.exercises.append(LoggedExercise(exerciseId: ex.id, sets: last?.sets.filter { !$0.warmup }.map { LiftSet(reps: $0.reps, weight: $0.weight) }
                                                         ?? [LiftSet(reps: 8, weight: 0), LiftSet(reps: 8, weight: 0), LiftSet(reps: 8, weight: 0)]))
                adding = false
            }
        }
        .sheet(item: $summary) { s in
            NavigationStack {
                List {
                    Section {
                        LabeledContent("Time", value: "\(s.minutes) min")
                        LabeledContent("Working sets", value: "\(s.setCount)")
                        LabeledContent("Volume", value: StrengthStore.format(s.volume))
                        LabeledContent("Muscular strain", value: "\(StrengthStore.strain(s)) / 100")
                    }
                    let prs = StrengthStore.records(in: s)
                    if !prs.isEmpty {
                        Section("New personal records") {
                            ForEach(prs) { p in Label("\(p.exercise.name): \(p.exercise.bodyweight ? "\(Int(p.value)) reps" : StrengthStore.format(p.value))", systemImage: "trophy.fill").foregroundStyle(.orange) }
                        }
                    }
                    Section {
                        TextField("Save as a routine (name)", text: $routineName)
                        Button("Save routine") {
                            var r = StrengthStore.routines
                            r.append(StrengthRoutine(name: routineName, items: s.exercises.map { .init(exerciseId: $0.exerciseId, sets: max(1, $0.sets.filter { !$0.warmup }.count), reps: $0.sets.last?.reps ?? 8) }))
                            StrengthStore.routines = r; routineName = ""; Haptics.success()
                        }
                        .disabled(routineName.isEmpty)
                    }
                }
                .navigationTitle("Nice work")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { summary = nil; done(s) } } }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
    }

    private func scheduleRest() {
        Kit.cancel(["strength.rest"])
        if let restEnds { Kit.notify("strength.rest", title: "Rest over", body: "Time for your next set.", at: restEnds) }
    }

    private func finish() {
        Kit.cancel(["strength.rest"])
        session.end = Date()
        if session.setCount == 0 { done(nil) } else { summary = session; Haptics.milestone() }
    }
}

struct ExercisePicker: View {
    var pick: (Exercise) -> Void
    @State private var search = ""
    @State private var muscle: Muscle?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("All", muscle == nil) { muscle = nil }
                        ForEach(Muscle.allCases) { m in chip(m.name, muscle == m) { muscle = m } }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                ForEach(results) { ex in
                    Button { pick(ex) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).foregroundStyle(DS.Palette.ink)
                            Text("\(ex.equipment) · \(ex.primary.map(\.name).joined(separator: ", "))").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "\(ExerciseLibrary.all.count) exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var results: [Exercise] {
        (ExerciseLibrary.all + StrengthStore.custom).filter { ex in
            (muscle == nil || ex.primary.contains(muscle!) || ex.secondary.contains(muscle!))
                && (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search) || ex.equipment.localizedCaseInsensitiveContains(search))
        }
    }

    private func chip(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? AnyShapeStyle(BodyStyle.swell) : AnyShapeStyle(BodyStyle.swell.opacity(0.12)), in: Capsule())
            .foregroundStyle(on ? Color.white : BodyStyle.swell).buttonStyle(.plain)
    }
}

struct ExerciseHistoryView: View {
    let exercise: Exercise
    var body: some View {
        let points: [BodyPoint] = StrengthStore.sessions.sorted { $0.start < $1.start }.compactMap { s in
            let best = s.exercises.filter { $0.exerciseId == exercise.id }.flatMap { $0.sets.filter { $0.done && !$0.warmup } }.map(StrengthStore.e1RM).max()
            return best.map { BodyPoint(day: s.start, v: $0) }
        }
        List {
            Section {
                if points.count >= 2 {
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.day), y: .value("Best", p.v)).foregroundStyle(BodyStyle.swell.gradient).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", p.day), y: .value("Best", p.v)).foregroundStyle(BodyStyle.swell)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    Text(exercise.bodyweight ? "Most reps in a set" : "Estimated 1-rep max per workout").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    Text("Do this exercise a couple of times to see your progress.").foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Section("Works") {
                Text(exercise.primary.map(\.name).joined(separator: ", ")).font(.callout.weight(.semibold))
                if !exercise.secondary.isEmpty { Text("Also: " + exercise.secondary.map(\.name).joined(separator: ", ")).font(.caption) }
            }
            if let sug = StrengthStore.suggestion(exercise.id, targetReps: StrengthStore.last(exercise.id)?.sets.last?.reps ?? 8) {
                Section("Next time") {
                    Text(exercise.bodyweight ? "\(sug.reps) reps" : "\(StrengthStore.format(sug.weight)) × \(sug.reps)").font(.headline)
                    Text(sug.why).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}
