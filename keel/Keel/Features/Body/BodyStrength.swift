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
    /// No weight to set: bodyweight moves, stretches, yoga and cardio.
    var bodyweight: Bool { ["Bodyweight", "Mobility", "Yoga", "Cardio"].contains(equipment) }
    /// Logged in seconds (stretches, yoga, holds) or minutes (cardio) rather than reps.
    var timed: Bool { ["Mobility", "Yoga"].contains(equipment) || name.contains("Plank") || name.contains("Hold") || name.hasSuffix("Sit") }
    var minutes: Bool { equipment == "Cardio" }
    /// Counts toward muscle load and strength stats (stretching, yoga and cardio don't).
    var isLoad: Bool { !["Mobility", "Yoga", "Cardio"].contains(equipment) }
    var category: String {
        switch equipment {
        case "Mobility": "Mobility"
        case "Yoga": "Yoga"
        case "Cardio": "Cardio"
        default: "Strength"
        }
    }
    func amount(_ n: Int) -> String { minutes ? "\(n) min" : timed ? "\(n) s" : "× \(n)" }
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
    Smith Machine Press|Machine|chest|triceps
    Cable Chest Press|Cable|chest|triceps
    Machine Chest Press|Machine|chest|triceps
    Incline Smith Machine Press|Machine|chest,shoulders|triceps
    Incline Cable Chest Press|Cable|chest,shoulders|triceps
    Incline Kettlebell Press|Kettlebell|chest,shoulders|triceps
    Incline Band Chest Press|Band|chest,shoulders|triceps
    Incline Machine Chest Press|Machine|chest,shoulders|triceps
    Decline Smith Machine Press|Machine|chest|triceps
    Decline Cable Chest Press|Cable|chest|triceps
    Decline Kettlebell Press|Kettlebell|chest|triceps
    Decline Band Chest Press|Band|chest|triceps
    Decline Machine Chest Press|Machine|chest|triceps
    Single-Arm Dumbbell Bench Press|Dumbbell|chest|triceps,abs
    Single-Arm Dumbbell Shoulder Press|Dumbbell|shoulders|triceps,abs
    Single-Arm Lat Pulldown|Cable|lats|biceps
    Single-Arm Cable Fly|Cable|chest|
    Single-Arm Cable Lateral Raise|Cable|shoulders|
    Single-Arm Cable Curl|Cable|biceps|
    Single-Arm Overhead Tricep Extension|Dumbbell|triceps|
    Single-Arm Dumbbell Snatch|Dumbbell|shoulders,glutes|hamstrings
    Single-Arm Kettlebell Swing|Kettlebell|glutes,hamstrings|abs
    Single-Arm Farmer's Carry|Dumbbell|abs,forearms|upperBack
    Single-Arm Landmine Row|Barbell|lats|biceps
    Single-Arm Machine Row|Machine|lats,upperBack|biceps
    Single-Arm Chest Press Machine|Machine|chest|triceps
    Single-Arm Preacher Curl|Dumbbell|biceps|
    Single-Arm Rear Delt Fly|Cable|rearDelts|
    Single-Arm Dumbbell Row (Bench)|Dumbbell|lats|biceps
    Single-Arm Push-up|Bodyweight|chest,triceps|abs
    Single-Leg Glute Bridge|Bodyweight|glutes|hamstrings
    Single-Leg Leg Extension|Machine|quads|
    Single-Leg Leg Curl|Machine|hamstrings|
    Single-Leg Box Squat|Bodyweight|quads,glutes|
    Single-Leg Dumbbell Calf Raise|Dumbbell|calves|
    Single-Leg Kettlebell Deadlift|Kettlebell|hamstrings,glutes|abs
    Single-Leg Hip Thrust (Barbell)|Barbell|glutes|hamstrings
    Single-Leg Press Calf Raise|Machine|calves|
    Wide-Grip Lat Pulldown|Cable|lats|upperBack
    Neutral-Grip Lat Pulldown|Cable|lats|biceps
    Reverse-Grip Lat Pulldown|Cable|lats,biceps|
    Behind-the-Neck Pulldown|Cable|lats|upperBack
    Kneeling Lat Pulldown|Cable|lats|abs
    Underhand Barbell Row|Barbell|lats,upperBack|biceps
    Wide-Grip Seated Row|Cable|upperBack,rearDelts|lats
    Rope Cable Row|Cable|upperBack|biceps,rearDelts
    Incline Dumbbell Row|Dumbbell|upperBack,lats|rearDelts
    Yates Row|Barbell|lats,upperBack|biceps
    Smith Machine Row|Machine|upperBack,lats|biceps
    Gironda Pulldown|Cable|lats|biceps
    Wide-Grip Barbell Curl|Barbell|biceps|
    Close-Grip Barbell Curl|Barbell|biceps|forearms
    Cable Hammer Curl|Cable|biceps,forearms|
    Rope Hammer Curl|Cable|biceps,forearms|
    Cross-Body Hammer Curl|Dumbbell|biceps,forearms|
    Dumbbell Preacher Curl|Dumbbell|biceps|
    Machine Curl|Machine|biceps|
    High Cable Curl|Cable|biceps|
    Kettlebell Curl|Kettlebell|biceps|forearms
    21s Curl|Barbell|biceps|
    Waiter Curl|Dumbbell|biceps|
    Seated Dumbbell Curl|Dumbbell|biceps|
    Alternating Dumbbell Curl|Dumbbell|biceps|forearms
    Close-Grip Push-up|Bodyweight|triceps,chest|
    Cable Overhead Tricep Extension (Rope)|Cable|triceps|
    Cross-Body Tricep Extension|Cable|triceps|
    Dumbbell Skull Crusher|Dumbbell|triceps|
    EZ-Bar Skull Crusher|Barbell|triceps|
    Machine Tricep Extension|Machine|triceps|
    Machine Dip|Machine|triceps,chest|
    Assisted Dip|Machine|triceps,chest|shoulders
    Reverse-Grip Pushdown|Cable|triceps|
    V-Bar Pushdown|Cable|triceps|
    Dumbbell Floor Press|Dumbbell|chest,triceps|
    Close-Grip Dumbbell Press|Dumbbell|triceps,chest|
    Plate Front Raise|Plate|shoulders|
    Cable Front Raise|Cable|shoulders|
    Leaning Lateral Raise|Dumbbell|shoulders|
    Machine Lateral Raise|Machine|shoulders|
    Seated Lateral Raise|Dumbbell|shoulders|
    Bent-Over Lateral Raise|Dumbbell|rearDelts|upperBack
    Cable Upright Row|Cable|shoulders,upperBack|biceps
    Dumbbell Upright Row|Dumbbell|shoulders,upperBack|
    Cable Shrug|Cable|upperBack|
    Smith Machine Shrug|Machine|upperBack|
    Behind-the-Back Shrug|Barbell|upperBack|
    Smith Machine Overhead Press|Machine|shoulders|triceps
    Z Press|Barbell|shoulders|triceps,abs
    Bradford Press|Barbell|shoulders|triceps
    Kettlebell Bottoms-Up Press|Kettlebell|shoulders|forearms,abs
    Heels-Elevated Goblet Squat|Dumbbell|quads|glutes
    Landmine Squat|Barbell|quads,glutes|
    Kettlebell Front Squat|Kettlebell|quads|abs
    Dumbbell Front Squat|Dumbbell|quads|glutes,abs
    Overhead Squat|Barbell|quads,shoulders|abs,upperBack
    Anderson Squat|Barbell|quads,glutes|
    Tempo Squat|Barbell|quads,glutes|
    Low-Bar Squat|Barbell|glutes,quads|hamstrings,lowerBack
    High-Bar Squat|Barbell|quads|glutes
    Dumbbell Squat|Dumbbell|quads,glutes|
    Sumo Squat|Dumbbell|quads,hips,glutes|
    Smith Machine Split Squat|Machine|quads,glutes|
    Front-Foot-Elevated Split Squat|Dumbbell|quads,glutes|
    Deficit Reverse Lunge|Dumbbell|glutes,quads|
    Barbell Lunge|Barbell|quads,glutes|
    Smith Machine Lunge|Machine|quads,glutes|
    Jumping Lunge|Bodyweight|quads,glutes|calves
    Bodyweight Lunge|Bodyweight|quads,glutes|
    Lateral Step-up|Dumbbell|quads,glutes|hips
    Barbell Step-up|Barbell|quads,glutes|
    Snatch-Grip Deadlift|Barbell|upperBack,hamstrings,glutes|lowerBack
    Paused Deadlift|Barbell|hamstrings,glutes,lowerBack|
    Block Pull|Barbell|glutes,upperBack|hamstrings
    Dumbbell Deadlift|Dumbbell|hamstrings,glutes|lowerBack
    Smith Machine Romanian Deadlift|Machine|hamstrings,glutes|
    Cable Romanian Deadlift|Cable|hamstrings,glutes|
    Cable Pull-Through|Cable|glutes,hamstrings|
    Banded Good Morning|Band|hamstrings,lowerBack|
    Seated Good Morning|Barbell|lowerBack|hamstrings
    45-Degree Back Extension|Bodyweight|lowerBack,glutes|hamstrings
    Hip Thrust Machine|Machine|glutes|
    Smith Machine Hip Thrust|Machine|glutes|hamstrings
    Dumbbell Hip Thrust|Dumbbell|glutes|hamstrings
    Banded Hip Thrust|Band|glutes|
    B-Stance Hip Thrust|Barbell|glutes|hamstrings
    Kas Glute Bridge|Barbell|glutes|
    Glute Kickback Machine|Machine|glutes|
    Lying Leg Curl|Machine|hamstrings|
    Standing Leg Curl|Machine|hamstrings|
    Swiss Ball Leg Curl|Other|hamstrings|glutes
    Slider Leg Curl|Bodyweight|hamstrings|glutes
    Dumbbell Leg Curl|Dumbbell|hamstrings|
    V-Squat Machine|Machine|quads,glutes|
    Leg Press Calf Raise|Machine|calves|
    Smith Machine Calf Raise|Machine|calves|
    Dumbbell Calf Raise|Dumbbell|calves|
    Cable Hip Abduction|Cable|hips,glutes|
    Cable Hip Adduction|Cable|hips|
    Cable Squat|Cable|quads,glutes|
    Cable Lunge|Cable|quads,glutes|
    Spanish Squat|Band|quads|
    Reverse Nordic|Bodyweight|quads|
    Hip Airplane|Bodyweight|glutes,hips|abs
    Shoulder Tap Plank|Bodyweight|abs|shoulders
    Plank Jack|Bodyweight|abs|shoulders
    Side Plank Dip|Bodyweight|abs|hips
    Stir the Pot|Other|abs|
    Hanging Knee Raise|Bodyweight|abs|forearms
    Windshield Wiper|Bodyweight|abs|
    Dragon Flag|Bodyweight|abs|lats
    Flutter Kick|Bodyweight|abs|hips
    Scissor Kick|Bodyweight|abs|hips
    Heel Tap|Bodyweight|abs|
    Sit-up|Bodyweight|abs|hips
    Weighted Crunch|Plate|abs|
    Ab Crunch Machine|Machine|abs|
    Reverse Crunch|Bodyweight|abs|
    Jackknife|Bodyweight|abs|hips
    Oblique Crunch|Bodyweight|abs|
    Suitcase Deadlift|Dumbbell|abs,glutes|forearms
    Landmine Rotation|Barbell|abs|shoulders
    Half-Kneeling Cable Chop|Cable|abs|
    High-to-Low Woodchop|Cable|abs|shoulders
    Low-to-High Woodchop|Cable|abs|shoulders
    Hollow Rock|Bodyweight|abs|
    Superman|Bodyweight|lowerBack,glutes|
    Stability Ball Crunch|Other|abs|
    Stability Ball Rollout|Other|abs|lats
    Suspension Fallout|Other|abs|lats,shoulders
    Kneeling Cable Crunch|Cable|abs|
    Weighted Plank|Plate|abs|shoulders
    Plank to Push-up|Bodyweight|abs,triceps|chest
    Side Plank Reach-Through|Bodyweight|abs|
    Captain's Chair Leg Raise|Machine|abs|hips
    Decline Crunch|Bodyweight|abs|
    Toe Touch Crunch|Bodyweight|abs|
    Seated Knee Tuck|Bodyweight|abs|
    Kettlebell Windmill|Kettlebell|abs,shoulders|hamstrings
    Kettlebell Halo|Kettlebell|shoulders|abs
    Waiter's Carry|Kettlebell|shoulders,abs|
    Overhead Carry|Dumbbell|shoulders,abs|upperBack
    Bear Plank Hold|Bodyweight|abs|shoulders,quads
    Archer Push-up|Bodyweight|chest|triceps
    Pseudo Planche Push-up|Bodyweight|shoulders,chest|triceps,abs
    Clapping Push-up|Bodyweight|chest|triceps
    Hindu Push-up|Bodyweight|chest,shoulders|triceps
    Dive Bomber Push-up|Bodyweight|chest,shoulders|triceps
    Knee Push-up|Bodyweight|chest|triceps
    Wall Push-up|Bodyweight|chest|triceps
    Typewriter Pull-up|Bodyweight|lats|biceps
    L-Sit Pull-up|Bodyweight|lats,abs|biceps
    Archer Pull-up|Bodyweight|lats|biceps
    Negative Pull-up|Bodyweight|lats|biceps
    Scapular Pull-up|Bodyweight|upperBack,lats|
    Scapular Push-up|Bodyweight|shoulders|chest
    Australian Chin-up|Bodyweight|lats,biceps|
    Tuck Front Lever|Bodyweight|lats,abs|
    Tuck Back Lever|Bodyweight|shoulders,abs|chest
    Skin the Cat|Bodyweight|shoulders,lats|abs
    Ring Dip|Other|chest,triceps|shoulders
    Ring Row|Other|upperBack,lats|biceps
    Ring Push-up|Other|chest|triceps,abs
    Ring Muscle-up|Other|lats,chest|triceps,biceps
    Wall Handstand Hold|Bodyweight|shoulders|triceps,abs
    Planche Lean|Bodyweight|shoulders|chest,abs
    Shrimp Squat|Bodyweight|quads,glutes|
    Dragon Squat|Bodyweight|quads,glutes|hips
    Straight-Bar Dip|Bodyweight|chest,triceps|
    Tricep Dip (Parallel Bars)|Bodyweight|triceps|chest
    Hanging Scapular Shrug|Bodyweight|upperBack|lats
    Wall Slide|Bodyweight|upperBack,rearDelts|
    Broad Jump|Bodyweight|quads,glutes|calves
    Tuck Jump|Bodyweight|quads,glutes|abs
    Lateral Bound|Bodyweight|glutes,quads|hips
    Skater Jump|Bodyweight|glutes,quads|hips
    Depth Jump|Bodyweight|quads,calves|glutes
    Single-Leg Hop|Bodyweight|calves,quads|
    Plyo Push-up|Bodyweight|chest|triceps
    Medicine Ball Chest Pass|Other|chest|triceps
    Medicine Ball Rotational Throw|Other|abs|shoulders
    Medicine Ball Overhead Throw|Other|shoulders,abs|lats
    Jumping Jack|Bodyweight|calves|shoulders
    Star Jump|Bodyweight|quads,calves|shoulders
    Split Jump|Bodyweight|quads,glutes|
    Box Step-over|Bodyweight|quads,glutes|
    Pogo Hops|Bodyweight|calves|
    High Knees|Bodyweight|quads,hips|calves
    Butt Kicks|Bodyweight|hamstrings|calves
    A-Skip|Bodyweight|hips,calves|
    B-Skip|Bodyweight|hamstrings,hips|
    Lateral Shuffle|Bodyweight|hips,quads|
    Carioca|Bodyweight|hips|calves
    Sprint|Cardio|quads,hamstrings|calves,glutes
    Hill Sprint|Cardio|quads,glutes|calves
    Shuttle Run|Cardio|quads|calves
    Agility Ladder Drill|Bodyweight|calves|quads
    Kettlebell Thruster|Kettlebell|quads,shoulders|glutes
    Dumbbell Thruster|Dumbbell|quads,shoulders|glutes
    Devil Press|Dumbbell|shoulders,glutes|chest,quads
    Man Maker|Dumbbell|shoulders,chest|quads,lats
    Sandbag Clean|Other|glutes,upperBack|hamstrings
    Squat Thrust|Bodyweight|quads|abs,shoulders
    Frog Jump|Bodyweight|quads,glutes|
    Treadmill Run|Cardio|quads,calves|
    Incline Treadmill Walk|Cardio|glutes,calves|
    Stair Climber|Cardio|glutes,quads|
    Stationary Bike|Cardio|quads|
    Spin Class|Cardio|quads,calves|
    Ski Erg|Cardio|lats,triceps|
    Swimming|Cardio|lats,shoulders|
    Outdoor Run|Cardio|quads,calves|
    Outdoor Cycling|Cardio|quads,glutes|
    Hiking|Cardio|quads,glutes|
    Rucking|Cardio|glutes,upperBack|
    Double-Unders|Cardio|calves|
    Rowing Intervals|Cardio|upperBack,quads|
    Elliptical Trainer|Cardio|quads,glutes|
    Air Bike Intervals|Cardio|quads,shoulders|
    Brisk Walk|Cardio|calves|
    Trail Run|Cardio|quads,calves|
    Step Aerobics|Cardio|quads,calves|
    Dance Cardio|Cardio|quads,calves|
    Boxing (Bag Work)|Cardio|shoulders,abs|
    Shadow Boxing|Cardio|shoulders|
    Kickboxing|Cardio|hips,shoulders|
    Water Aerobics|Cardio|quads,shoulders|
    Stair Sprints|Cardio|quads,glutes|
    Standing Hamstring Stretch|Mobility|hamstrings|
    Seated Hamstring Stretch|Mobility|hamstrings|
    Standing Quad Stretch|Mobility|quads|
    Kneeling Hip Flexor Stretch|Mobility|hips|
    Couch Stretch|Mobility|quads,hips|
    Pigeon Stretch|Mobility|glutes,hips|
    Figure-Four Stretch|Mobility|glutes|
    Butterfly Stretch|Mobility|hips|
    Frog Stretch|Mobility|hips|
    90/90 Hip Switch|Mobility|hips,glutes|
    World's Greatest Stretch|Mobility|hips,hamstrings|
    Cat-Cow|Mobility|lowerBack,upperBack|
    Thread the Needle|Mobility|upperBack|
    Calf Stretch (Wall)|Mobility|calves|
    Soleus Stretch|Mobility|calves|
    Ankle Dorsiflexion Rock|Mobility|calves|
    Doorway Pec Stretch|Mobility|chest|
    Cross-Body Shoulder Stretch|Mobility|rearDelts|
    Overhead Triceps Stretch|Mobility|triceps|
    Sleeper Stretch|Mobility|shoulders|
    Wrist Flexor Stretch|Mobility|forearms|
    Wrist Extensor Stretch|Mobility|forearms|
    Neck Side Stretch|Mobility|upperBack|
    Chin Tuck|Mobility|upperBack|
    Levator Scapulae Stretch|Mobility|upperBack|
    Thoracic Extension on Roller|Mobility|upperBack|
    Open Book Rotation|Mobility|upperBack|
    Seated Spinal Twist|Mobility|lowerBack|
    Supine Twist|Mobility|lowerBack|
    Lat Stretch (Kneeling)|Mobility|lats|
    Band Shoulder Dislocate|Mobility|shoulders|
    Wall Angel|Mobility|upperBack,shoulders|
    Adductor Rock Back|Mobility|hips|
    Lizard Stretch|Mobility|hips|
    Hip CARs|Mobility|hips|
    Shoulder CARs|Mobility|shoulders|
    Ankle Circles|Mobility|calves|
    Front Leg Swing|Mobility|hips,hamstrings|
    Side Leg Swing|Mobility|hips|
    Arm Circles|Mobility|shoulders|
    Inchworm|Mobility|hamstrings,shoulders|
    Spiderman Lunge|Mobility|hips|
    Deep Squat Hold|Mobility|hips,quads|
    Jefferson Curl|Mobility|lowerBack,hamstrings|
    Sciatic Nerve Glide|Mobility|hamstrings|
    Foam Roll Quads|Mobility|quads|
    Foam Roll Hamstrings|Mobility|hamstrings|
    Foam Roll Calves|Mobility|calves|
    Foam Roll Upper Back|Mobility|upperBack|
    Foam Roll Lats|Mobility|lats|
    Foam Roll Glutes|Mobility|glutes|
    Foam Roll IT Band|Mobility|quads|
    Lacrosse Ball Foot Roll|Mobility|calves|
    Lacrosse Ball Pec Release|Mobility|chest|
    Knee-to-Chest Stretch|Mobility|lowerBack,glutes|
    Standing Side Bend|Mobility|abs|
    Prone Press-up|Mobility|lowerBack|
    Hip Flexor Stretch (Standing)|Mobility|hips|
    Groin Stretch (Side Lunge)|Mobility|hips|
    Tricep Wall Stretch|Mobility|triceps|
    Bicep Wall Stretch|Mobility|biceps|
    Kneeling Shin Stretch|Mobility|quads|
    Half-Kneeling Ankle Mobilisation|Mobility|calves|
    Scorpion Stretch|Mobility|hips,lowerBack|
    Quadruped Rock Back|Mobility|hips|
    Shoulder Pass-through (Stick)|Mobility|shoulders|
    Thoracic Rotation (Side-Lying)|Mobility|upperBack|
    Downward Dog|Yoga|hamstrings,shoulders|
    Upward Dog|Yoga|lowerBack,chest|
    Cobra Pose|Yoga|lowerBack|
    Child's Pose|Yoga|lowerBack,hips|
    Warrior I|Yoga|quads,hips|
    Warrior II|Yoga|quads,hips|
    Warrior III|Yoga|glutes,hamstrings|
    Triangle Pose|Yoga|hamstrings,hips|
    Extended Side Angle|Yoga|quads,hips|
    Chair Pose|Yoga|quads,glutes|
    Tree Pose|Yoga|calves,hips|
    Mountain Pose|Yoga|abs|
    Bridge Pose|Yoga|glutes,lowerBack|
    Wheel Pose|Yoga|lowerBack,shoulders|
    Camel Pose|Yoga|quads,chest|
    Bow Pose|Yoga|lowerBack,quads|
    Locust Pose|Yoga|lowerBack,glutes|
    Boat Pose|Yoga|abs,hips|
    Crow Pose|Yoga|shoulders,abs|
    Plank Pose|Yoga|abs,shoulders|
    Side Plank Pose|Yoga|abs,shoulders|
    Pigeon Pose|Yoga|glutes,hips|
    Low Lunge|Yoga|hips,quads|
    High Lunge|Yoga|quads,hips|
    Half Moon Pose|Yoga|glutes,hips|
    Seated Forward Fold|Yoga|hamstrings,lowerBack|
    Standing Forward Fold|Yoga|hamstrings|
    Happy Baby|Yoga|hips,lowerBack|
    Reclined Bound Angle|Yoga|hips|
    Legs Up the Wall|Yoga|hamstrings|
    Garland Pose|Yoga|hips,calves|
    Goddess Pose|Yoga|quads,hips|
    Eagle Pose|Yoga|shoulders,hips|
    Cow Face Pose|Yoga|shoulders,hips|
    Fish Pose|Yoga|chest,upperBack|
    Plow Pose|Yoga|upperBack,hamstrings|
    Shoulder Stand|Yoga|shoulders,abs|
    Headstand|Yoga|shoulders,abs|
    Dolphin Pose|Yoga|shoulders|
    Puppy Pose|Yoga|shoulders,upperBack|
    Sphinx Pose|Yoga|lowerBack|
    Revolved Triangle|Yoga|hamstrings,abs|
    Revolved Chair|Yoga|quads,abs|
    Dancer Pose|Yoga|quads,shoulders|
    Gate Pose|Yoga|abs,hips|
    Half Splits|Yoga|hamstrings|
    Front Splits|Yoga|hamstrings,hips|
    Sun Salutation A|Yoga|hamstrings,shoulders|
    Sun Salutation B|Yoga|quads,shoulders|
    Chaturanga|Yoga|triceps,chest|
    Wide-Legged Forward Fold|Yoga|hamstrings,hips|
    Reverse Warrior|Yoga|hips,abs|
    Humble Warrior|Yoga|hips,shoulders|
    Lizard Pose|Yoga|hips|
    Firefly Pose|Yoga|abs,triceps|
    Side Crow|Yoga|abs,shoulders|
    Reclined Pigeon|Yoga|glutes|
    Thread the Needle Pose|Yoga|upperBack|
    Supported Bridge|Yoga|lowerBack,glutes|
    Easy Seated Twist|Yoga|lowerBack|
    Clamshell|Band|glutes,hips|
    Side-Lying Leg Raise|Bodyweight|hips,glutes|
    Fire Hydrant|Bodyweight|glutes,hips|
    Monster Walk|Band|hips,glutes|
    Terminal Knee Extension|Band|quads|
    Straight Leg Raise|Bodyweight|quads,hips|
    Heel Slide|Bodyweight|hamstrings|
    Quad Set|Bodyweight|quads|
    Glute Squeeze|Bodyweight|glutes|
    McGill Curl-up|Bodyweight|abs|
    Prone Y Raise|Bodyweight|upperBack,rearDelts|
    Prone T Raise|Bodyweight|rearDelts,upperBack|
    Prone W Raise|Bodyweight|upperBack,rearDelts|
    Band External Rotation|Band|rearDelts|shoulders
    Band Internal Rotation|Band|shoulders|
    Cable External Rotation|Cable|rearDelts|
    Scapular Retraction|Band|upperBack|
    Eccentric Calf Raise|Bodyweight|calves|
    Towel Scrunch|Bodyweight|calves|
    Single-Leg Balance|Bodyweight|calves,glutes|
    Hip Hinge Drill|Bodyweight|hamstrings,glutes|
    Step-down|Bodyweight|quads,glutes|
    Lateral Step-down|Bodyweight|quads,glutes|hips
    Wrist Roller|Other|forearms|
    Finger Extension (Band)|Band|forearms|
    Neck Isometrics|Bodyweight|upperBack|
    Cuban Rotation|Dumbbell|rearDelts|shoulders
    Serratus Wall Slide|Bodyweight|shoulders|
    Bird Dog Row|Dumbbell|lats,abs|
    Pelvic Tilt|Bodyweight|abs,lowerBack|
    Isometric Hip Adduction (Ball Squeeze)|Other|hips|
    Banded Ankle Eversion|Band|calves|
    Seated Knee Extension (Band)|Band|quads|
    Shoulder Pendulum|Bodyweight|shoulders|
    Wall Sit Hold (Single-Leg)|Bodyweight|quads|glutes
    Dead Bug with Band|Band|abs|
    Atlas Stone Lift|Other|glutes,upperBack|hamstrings,lowerBack
    Yoke Walk|Other|quads,upperBack|abs
    Log Press|Other|shoulders|triceps,upperBack
    Axle Deadlift|Barbell|hamstrings,glutes,forearms|lowerBack
    Sandbag Carry|Other|abs,upperBack|glutes
    Tire Flip|Other|glutes,quads|upperBack,lowerBack
    Keg Carry|Other|abs,upperBack|
    Zercher Carry|Barbell|abs,upperBack|biceps
    Backward Sled Drag|Other|quads|calves
    Prowler Sprint|Other|quads,glutes|calves
    Battle Rope Slam|Other|shoulders,abs|
    Landmine Thruster|Barbell|quads,shoulders|glutes
    Landmine Row|Barbell|lats,upperBack|biceps
    Trap Bar Jump|Trap bar|quads,glutes|calves
    Hang Snatch|Barbell|glutes,shoulders,upperBack|hamstrings
    Power Snatch|Barbell|glutes,shoulders,upperBack|hamstrings
    Push Jerk|Barbell|shoulders,quads|triceps
    Split Jerk|Barbell|shoulders,quads|triceps
    Snatch Balance|Barbell|quads,shoulders|abs
    Clean Pull|Barbell|hamstrings,glutes,upperBack|
    Snatch Pull|Barbell|hamstrings,glutes,upperBack|
    Muscle Snatch|Barbell|shoulders,upperBack|
    Hang Power Clean|Barbell|glutes,upperBack|quads
    Front Rack Lunge|Barbell|quads,glutes|abs
    Drop Snatch|Barbell|quads,shoulders|
    Iso-Lateral Row|Machine|lats,upperBack|biceps
    Low Row Machine|Machine|lats|biceps
    High Row Machine|Machine|lats,upperBack|biceps
    Pullover Machine|Machine|lats|
    Back Extension Machine|Machine|lowerBack|
    Glute Drive Machine|Machine|glutes|
    Plate-Loaded Lat Pulldown|Machine|lats|biceps
    Seated Dip Machine|Machine|triceps|
    Cable Crossover|Cable|chest|
    Cable Shoulder Press|Cable|shoulders|triceps
    Cable Y-Raise|Cable|shoulders,upperBack|
    Cable Glute Kickback (Ankle Strap)|Cable|glutes|
    Cable Hip Flexion|Cable|hips|
    Cable Reverse Curl|Cable|forearms,biceps|
    Cable Wrist Curl|Cable|forearms|
    Cable Kickback (Triceps)|Cable|triceps|
    Cable Pullover (Rope)|Cable|lats|
    Leg Press (Narrow Stance)|Machine|quads|
    Leg Press (Wide Stance)|Machine|glutes,hips|quads
    Seated Hip Abduction (Lean Forward)|Machine|glutes|
    Pec Deck Rear Delt|Machine|rearDelts|
    Assisted Chin-up|Machine|lats,biceps|
    Smith Machine Bulgarian Split Squat|Machine|quads,glutes|
    Smith Machine Good Morning|Machine|hamstrings,lowerBack|
    Smith Machine Upright Row|Machine|shoulders,upperBack|
    Smith Machine Close-Grip Press|Machine|triceps,chest|
    Jumping Pull-up|Bodyweight|lats|biceps
    Kipping Pull-up|Bodyweight|lats|abs,biceps
    Burpee Box Jump|Bodyweight|quads,chest|glutes
    Burpee Pull-up|Bodyweight|lats,chest|quads
    Box Jump Over|Bodyweight|quads,glutes|calves
    Wall Walk|Bodyweight|shoulders,abs|triceps
    Handstand Walk|Bodyweight|shoulders|triceps,abs
    Rope Climb|Other|lats,biceps|forearms
    Goblet Reverse Lunge|Kettlebell|glutes,quads|
    Goblet Lateral Lunge|Kettlebell|quads,hips|
    Barbell Walking Lunge|Barbell|quads,glutes|hamstrings
    Overhead Walking Lunge|Dumbbell|quads,shoulders|abs
    Plate Pinch Hold|Plate|forearms|
    Towel Pull-up|Bodyweight|lats,forearms|biceps
    Fat Grip Curl|Dumbbell|biceps,forearms|
    Bench Hop|Bodyweight|calves,quads|
    Lateral Box Jump|Bodyweight|quads,glutes|hips
    Seated Box Jump|Bodyweight|quads,glutes|
    American Kettlebell Swing|Kettlebell|glutes,shoulders|hamstrings
    Medicine Ball Squat Throw|Other|quads,shoulders|glutes
    Medicine Ball Lunge Rotation|Other|quads,abs|
    Glute Bridge March|Bodyweight|glutes|abs
    Sled Row|Other|upperBack,lats|biceps
    Turkish Sit-up|Kettlebell|abs|shoulders
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
            lastCache = nil; bestsCache = nil; fatigueCache = nil
            let copy = newValue, file = url
            // Write in the background so finishing a workout never waits on the disk.
            Task.detached(priority: .utility) { if let d = try? JSONEncoder().encode(copy) { try? d.write(to: file, options: .atomic) } }
        }
    }

    // Worked out once and reused until a workout is saved: these were recomputed on every redraw.
    private static var lastCache: [String: LoggedExercise]?
    private static var bestsCache: [String: Double]?
    private static var fatigueCache: (at: Date, value: [Muscle: Double])?

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
        if list == nil, date == .distantFuture, let bestsCache { return bestsCache }
        var out: [String: Double] = [:]
        for s in (list ?? sessions) where s.start < date {
            for e in s.exercises {
                for set in e.sets where set.done && !set.warmup { out[e.exerciseId] = max(out[e.exerciseId] ?? 0, e1RM(set)) }
            }
        }
        if list == nil, date == .distantFuture { bestsCache = out }
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
        if list == nil, date == .distantFuture {
            if lastCache == nil {
                var map: [String: LoggedExercise] = [:]
                for s in sessions.sorted(by: { $0.start > $1.start }) {
                    for e in s.exercises where map[e.exerciseId] == nil && e.sets.contains(where: { $0.done && !$0.warmup }) { map[e.exerciseId] = e }
                }
                lastCache = map
            }
            return lastCache?[exerciseId]
        }
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
                guard let ex = ExerciseLibrary.exercise(e.exerciseId), ex.isLoad else { continue }
                for m in ex.primary { out[m, default: 0] += 1 }
                for m in ex.secondary { out[m, default: 0] += 0.5 }
            }
        }
        return out
    }

    /// How tired each muscle still is (0 fresh … 1 just hammered), fading over about 3 days.
    static func fatigue(now: Date = Date(), in list: [StrengthSession]? = nil) -> [Muscle: Double] {
        if list == nil, let c = fatigueCache, abs(now.timeIntervalSince(c.at)) < 300 { return c.value }
        var out: [Muscle: Double] = [:]
        for s in (list ?? sessions) {
            let hours = now.timeIntervalSince(s.end ?? s.start) / 3600
            guard hours >= 0, hours < 96 else { continue }
            let fade = exp(-hours / 36)
            for (e, set) in s.workingSets {
                guard let ex = ExerciseLibrary.exercise(e.exerciseId), ex.isLoad else { continue }
                let effort = 0.12 * (Double(set.rpe ?? 8) / 8)
                for m in ex.primary { out[m, default: 0] += effort * fade }
                for m in ex.secondary { out[m, default: 0] += effort * 0.5 * fade }
            }
        }
        let result = out.mapValues { min(1, $0) }
        if list == nil { fatigueCache = (now, result) }
        return result
    }

    /// Muscular strain for one session, 0–100: more hard sets → higher, levelling off like Swell.
    static func strain(_ s: StrengthSession) -> Int {
        let hard = s.workingSets.filter { ExerciseLibrary.exercise($0.0.exerciseId)?.isLoad ?? true }.reduce(0.0) { $0 + Double($1.1.rpe ?? 8) / 8 }
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
                                Stepper(value: $set.reps, in: 0...(ex.timed ? 600 : 300), step: ex.timed ? 5 : 1) { Text(ex.amount(set.reps)).monospacedDigit().font(.callout) }.fixedSize()
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
    @State private var category = "All"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Picker("Kind", selection: $category) {
                    ForEach(["All", "Strength", "Cardio", "Mobility", "Yoga"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
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
            (category == "All" || ex.category == category)
                && (muscle == nil || ex.primary.contains(muscle!) || ex.secondary.contains(muscle!))
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
