import SwiftUI

// MARK: - Binnacle
//
// Keel's own navigation on iPhone in the nautical looks: a floating dark bar with your tabs and, in the middle, the red
// Log button (tap: one line that becomes a task, event, note, reminder or meal; hold: speak). Each tab is built the first
// time you open it and then kept ready, so switching back is instant. The classic looks, iPad and Mac keep the system
// tab bar and sidebar. Settings → Customize Keel → Look → "Floating tab bar" turns it off.

@MainActor
enum Binnacle {
    static let key = "binnacle.on"
    static var isOn: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && PaletteCache.look.isNautical
            && (UserDefaults.standard.object(forKey: key) as? Bool ?? true)
    }
}

struct BinnacleShell: View {
    @Bindable var router: AppRouter
    let items: [String]
    @State private var built: Set<String> = []
    @State private var showLog = false
    @State private var showVoice = false
    @State private var keyboardUp = false
    @AppStorage(FocusBarSetting.key) private var focusBarOn = true
    @State private var pushed = false                 // the visible tab has gone into a screen: bar steps aside

    private var current: String {
        items.first { TabBarConfig.value($0) == router.tab } ?? items.first ?? "today"
    }

    var body: some View {
        let sel = current
        ZStack {
            ForEach(items, id: \.self) { id in
                if built.contains(id) || id == sel {
                    // The screen itself, not TabBarConfig.content: that wrapper waits until the tab is selected,
                    // which undid the build-ahead below. `built` already decides when each tab is made.
                    TabBarConfig.screen(id)
                        .opacity(id == sel ? 1 : 0)
                        .allowsHitTesting(id == sel)
                        .accessibilityHidden(id != sel)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp && !router.chromeHidden && !pushed {
                VStack(spacing: 8) {
                    if focusBarOn {
                        FocusAccessory { router.showFocus = true }
                            .frame(height: 44)
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .padding(.horizontal, 22)
                    }
                    bar(selected: sel)
                }
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: keyboardUp)
        .animation(.easeOut(duration: 0.2), value: pushed)
        // Like iOS's hidesBottomBarWhenPushed: on a screen you've gone into, the floating bar steps aside so that
        // screen's own bottom buttons aren't hidden behind it (meeting notes' "Write up" was). Back on the tab's
        // first screen, it returns. (The bar's space doesn't reach screens pushed inside a tab, so it can't make room.)
        .task {
            while !Task.isCancelled {
                let now = NavDepth.visibleTabIsPushed()
                if now != pushed { pushed = now }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onAppear { built.insert(sel) }
        // Build the other tabs ahead of time, one at a time while Keel is idle after launch. Each screen's first build
        // (SwiftUI and Swift setting up its view types, the first fetch and layout) took 250–450 ms on the main thread,
        // and it used to happen on your first tap of Inbox, Tasks or Calendar.
        .task {
            try? await Task.sleep(for: .seconds(3))
            for id in items where !built.contains(id) {
                guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
                built.insert(id)
                try? await Task.sleep(for: .milliseconds(1200))
            }
        }
        .onChange(of: router.tab) { _, _ in built.insert(current) }
        .sheet(isPresented: $showLog) { UniversalCaptureSheet() }
        .sheet(isPresented: $showVoice) { VoiceNoteView() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
    }

    private func bar(selected: String) -> some View {
        let left = Array(items.prefix((items.count + 1) / 2))
        let right = Array(items.dropFirst(left.count))
        let fill = DS.Palette.ink
        return HStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(left, id: \.self) { tabButton($0, selected: selected) } }.frame(maxWidth: .infinity)
            logButton
            HStack(spacing: 0) { ForEach(right, id: \.self) { tabButton($0, selected: selected) } }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(fill.opacity(0.95), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .padding(.horizontal, 14)
    }

    private func tabButton(_ id: String, selected: String) -> some View {
        let on = id == selected
        let lit: Color = PaletteCache.look == .chart ? Color(red: 0.94, green: 0.79, blue: 0.63) : DS.Palette.accent
        return Button {
            if on { return }
            var t = Transaction(); t.disablesAnimations = true          // tabs switch instantly, no cross-fade
            withTransaction(t) { router.tab = TabBarConfig.value(id) }
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: TabBarConfig.icon(id)).font(.system(size: 18, weight: on ? .semibold : .regular))
                    .symbolVariant(on ? .fill : .none)
                Text(TabBarConfig.title(id)).font(.system(size: 9.5, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? lit : DS.Palette.canvas.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TabBarConfig.title(id))
        .accessibilityIdentifier("tab." + id)              // stable for UI tests ("Today" also labels Calendar's button)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    /// Tap: the one-line Log. Hold: speak it.
    private var logButton: some View {
        let red = PaletteCache.look == .chart ? Nautical.chartRed : DS.Palette.accent
        return Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(red, in: Circle())
            .overlay(Circle().strokeBorder(DS.Palette.canvas, lineWidth: 4))
            .shadow(color: red.opacity(0.45), radius: 8, y: 4)
            .offset(y: -18)
            .contentShape(Circle())
            .onTapGesture { Haptics.tap(); showLog = true }
            .onLongPressGesture(minimumDuration: 0.35) { Haptics.capture(); showVoice = true }
            .accessibilityElement()
            .accessibilityLabel("Log")
            .accessibilityIdentifier("tab.log")
            .accessibilityHint("Add a task, event, note, reminder or meal. Hold to speak.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showLog = true }
            .accessibilityAction(named: "Speak") { showVoice = true }
    }
}

/// Whether the tab on screen has gone deeper than its first page (a UINavigationController that's visible, not in a
/// sheet, with more than one screen). Hidden tabs are kept built at opacity 0, so only visible ones count.
@MainActor
enum NavDepth {
    static func visibleTabIsPushed() -> Bool {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
        else { return false }
        return search(root)
    }

    private static func search(_ vc: UIViewController) -> Bool {
        if let nav = vc as? UINavigationController, nav.viewControllers.count > 1, isVisible(nav.view) { return true }
        return vc.children.contains { search($0) }              // not presentedViewController: sheets have no tab bar
    }

    private static func isVisible(_ v: UIView?) -> Bool {
        var view = v
        guard view?.window != nil else { return false }
        while let x = view {
            if x.isHidden || x.alpha < 0.01 || x.layer.opacity < 0.01 { return false }
            view = x.superview
        }
        return true
    }
}
