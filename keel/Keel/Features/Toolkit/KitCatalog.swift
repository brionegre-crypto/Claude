import SwiftUI

/// The everyday toolkit's entries in Compass, by group. Each opens its own screen, which explains itself at the top.
@MainActor
enum KitCatalog {
    private static func t<V: View>(_ id: String, _ title: String, _ icon: String, _ keywords: String, @ViewBuilder _ dest: @escaping () -> V) -> HubTool {
        HubTool(id: id, title: title, icon: icon, keywords: keywords, dest: { AnyView(dest()) })
    }

    static func tools(for group: String) -> [HubTool] { all[group] ?? [] }

    static var count: Int { all.values.reduce(0) { $0 + $1.count } }

    static let all: [String: [HubTool]] = [
        "go": [
            t("top3", "Top 3 today", "3.circle.fill", "top three priorities today most important") { KitTop3View() },
            t("frog", "Eat the frog", "tortoise.circle.fill", "frog hardest task first procrastinate avoid") { KitFrogView() },
            t("timebox", "Timebox list", "list.bullet.indent", "timebox list timer each task llama run through") { KitTimeboxView() },
            t("estimator", "Time estimator", "hourglass", "time blindness estimate how long guess actual") { KitEstimatorView() },
            t("transition", "Transition timer", "arrow.triangle.turn.up.right.diamond.fill", "transition switch next warn leave") { KitTransitionView() },
            t("chimes", "Time chimes", "bell.and.waves.left.and.right.fill", "chime hourly time blindness hyperfocus reminder") { KitChimesView() },
            t("phoneDown", "Phone down", "iphone.slash", "phone free forest distraction streak focus") { KitPhoneDownView() },
            t("timers", "Timers", "timer", "multiple timers laundry oven cooking countdown") { KitMultiTimersView() },
            t("workday", "Workday left", "sunset.fill", "workday hours left end of day progress") { KitWorkdayView() },
            t("roulette", "Task roulette", "dice.fill", "random pick task choose for me decide") { KitRouletteView() },
            t("whatFits", "What fits", "square.stack.3d.down.forward.fill", "gap minutes before meeting fits short time") { KitWhatFitsView() },
            t("spoons", "Spoons", "fork.knife", "spoon theory energy budget chronic illness") { KitSpoonsView() },
            t("mindSweep", "Mind sweep", "wind", "mind sweep gtd trigger list empty head capture") { KitMindSweepView() },
            t("morningPages", "Morning pages", "doc.plaintext.fill", "morning pages write free writing journal 750 words") { KitMorningPagesView() },
            t("sprint", "Writing sprint", "pencil.line", "writing sprint words goal timer") { KitSprintView() },
            t("meetingTimer", "Meeting timer", "person.3.sequence.fill", "meeting agenda timer run over") { KitMeetingTimerView() },
            t("firstStep", "Tomorrow's first step", "shoeprints.fill", "tomorrow first step shutdown breadcrumb start") { KitFirstStepView() },
        ],
        "calm": [
            t("reframe", "Reframe a thought", "arrow.triangle.2.circlepath", "cbt thought record reframe anxious negative trap") { KitReframeView() },
            t("worry", "Worry time", "cloud.drizzle.fill", "worry anxiety park later") { KitWorryTimeView() },
            t("feelings", "Name the feeling", "heart.circle.fill", "emotion feeling wheel name label") { KitFeelingsView() },
            t("grounding", "Grounding 5-4-3-2-1", "leaf.circle.fill", "grounding panic senses calm") { KitGroundingView() },
            t("battery", "Social battery", "battery.75percent", "social battery introvert energy people") { KitBatteryView() },
            t("affirmations", "Affirmations", "quote.bubble.fill", "affirmations kind self talk critic") { KitAffirmationsView() },
        ],
        "top": [
            t("whereIsIt", "Where did I put it?", "magnifyingglass.circle.fill", "lost item where put keys passport safe place") { KitWhereView() },
            t("parking", "Parking", "car.fill", "parking car spot meter time limit") { KitParkingView() },
            t("returns", "Returns & warranties", "shippingbox.and.arrow.backward.fill", "return window warranty purchase receipt") { KitReturnsView() },
            t("waitlist", "Impulse waiting list", "hourglass.bottomhalf.filled", "impulse buy shopping wait 30 days save money") { KitWaitlistView() },
            t("noSpend", "No-spend days", "creditcard.trianglebadge.exclamationmark", "no spend streak budget saving") { KitNoSpendView() },
            t("jars", "Savings jars", "banknote.fill", "savings goals jar money") { KitJarsView() },
            t("tipSplit", "Tip & split", "person.2.fill", "tip split bill restaurant calculator") { KitTipSplitView() },
            t("deal", "Better deal", "scalemass.fill", "unit price compare cheaper shopping") { KitDealView() },
            t("chores", "Chore rotation", "arrow.3.trianglepath", "chores rota household family rotate") { KitChoresView() },
            t("tidy", "Tidy sprint", "sparkles", "tidy clean room 15 minutes house") { KitTidyView() },
            t("pets", "Pet care", "pawprint.fill", "pet dog cat fed walked vet") { KitPetsView() },
            t("counters", "Counters", "plus.forwardslash.minus", "count tally counter clicker") { KitCountersView() },
        ],
        "back": [
            t("doneList", "Done list", "checkmark.seal.fill", "done list ta-da wins accomplished today") { KitDoneListView() },
            t("winsJar", "Wins jar", "star.circle.fill", "wins jar proud achievements bad day") { KitWinsJarView() },
            t("gratitude", "Three good things", "sun.max.fill", "gratitude three good things evening") { KitGratitudeView() },
            t("chains", "Chains", "link", "don't break the chain streak daily") { KitChainsView() },
            t("reading", "Reading", "books.vertical.fill", "books reading goal pages") { KitReadingView() },
            t("practice", "Practice log", "music.note.list", "practice skill hours learning") { KitPracticeView() },
        ],
        "ahead": [
            t("themeDays", "Theme days", "calendar.day.timeline.left", "theme days weekday batching") { KitThemeDaysView() },
            t("ifThen", "If-then plans", "arrow.right.circle.fill", "if then implementation intention plan habit") { KitIfThenView() },
            t("dontDo", "Don't-do list", "hand.raised.fill", "dont do not to do list boundaries") { KitDontDoView() },
            t("decide", "Decide for me", "arrow.triangle.branch", "decide choose options coin flip") { KitDecideView() },
            t("experiments", "Experiments", "flask.fill", "experiment habit trial try test") { KitExperimentsView() },
            t("ideas", "Idea vault", "lightbulb.max.fill", "ideas vault someday inspiration") { KitIdeaVaultView() },
            t("bucket", "Bucket list", "globe.europe.africa.fill", "bucket list dreams one day travel") { KitBucketListView() },
            t("letter", "Letter to future you", "envelope.badge.fill", "letter future self time capsule") { KitFutureLetterView() },
            t("lifeWeeks", "Life in weeks", "square.grid.4x3.fill", "life in weeks perspective memento mori") { KitLifeWeeksView() },
        ],
    ]
}
