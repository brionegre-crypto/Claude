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

    private var current: String {
        items.first { TabBarConfig.value($0) == router.tab } ?? items.first ?? "today"
    }

    var body: some View {
        let sel = current
        ZStack {
            ForEach(items, id: \.self) { id in
                if built.contains(id) || id == sel {
                    TabBarConfig.content(id)
                        .opacity(id == sel ? 1 : 0)
                        .allowsHitTesting(id == sel)
                        .accessibilityHidden(id != sel)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp && !router.chromeHidden {
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
        .onAppear { built.insert(sel) }
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
            .accessibilityHint("Add a task, event, note, reminder or meal. Hold to speak.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showLog = true }
            .accessibilityAction(named: "Speak") { showVoice = true }
    }
}
