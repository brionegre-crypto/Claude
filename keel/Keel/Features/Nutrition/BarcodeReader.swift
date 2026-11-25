import SwiftUI
import SwiftData
import AVFoundation
import Vision
import PhotosUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

// MARK: - Barcode reader
//
// A real reader: full screen, opens on the camera, asks for camera access the first time (the old scanner never asked,
// so the camera never started and you got a "type the number" form), locks onto a code by itself with a haptic tick,
// torch, pinch to zoom, scan from a photo, and "scan several" for a grocery haul. Three modes: Barcode, Label (Apple
// Intelligence reads the panel) and Menu (dishes ranked for you). Each result slides up over the live camera, with
// Apple Intelligence's verdict for you, and the camera is ready again the moment you log or close it.

struct BarcodeReaderView: View {
    enum Mode: String, CaseIterable { case barcode = "Barcode", label = "Label", menu = "Menu" }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var meal: String = FoodEntry.mealNow()

    @State private var mode: Mode = .barcode
    @State private var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torch = false
    @State private var busy = false
    @State private var note: String?
    @State private var lastCode = ""
    @State private var result: ScannedFood?
    @State private var several = false
    @State private var haul: [ScannedFood] = []
    @State private var seenText = ""
    @State private var pendingBarcode: String?
    @State private var menuPicks: [FoodAI.MenuPick] = []
    @State private var photo: PhotosPickerItem?
    @State private var typed = ""

    private var liveOK: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return access == .authorized && DataScannerViewController.isSupported
        #endif
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            camera
            if mode == .barcode && liveOK { viewfinder }
            VStack(spacing: 0) {
                topBar
                Spacer()
                status
                modePicker
                bottomTray
            }
        }
        .preferredColorScheme(.dark)
        .task { await askForCamera() }
        .sheet(item: $result, onDismiss: { lastCode = "" }) { f in
            ScanResultSheet(food: f, meal: meal) { logged in
                result = nil
                if logged { note = "Logged \(f.name)"; Haptics.success() }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onChange(of: photo) { _, item in if let item { Task { await readPhoto(item) } } }
        .onDisappear { setTorch(false) }
    }

    // MARK: Camera

    @ViewBuilder private var camera: some View {
        #if !targetEnvironment(macCatalyst)
        if liveOK {
            LiveScanner(mode: mode, onCode: handle(code:), onText: { seenText = $0 })
                .id(mode)
                .ignoresSafeArea()
        } else {
            noCamera
        }
        #else
        noCamera
        #endif
    }

    private var noCamera: some View {
        VStack(spacing: 14) {
            Image(systemName: access == .denied || access == .restricted ? "camera.badge.ellipsis" : "barcode.viewfinder")
                .font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
            if access == .denied || access == .restricted {
                Text("Keel needs the camera to read barcodes.").foregroundStyle(.white)
                Button("Turn on camera access") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent).tint(Nautical.chartRed)
            } else if access == .notDetermined {
                ProgressView().tint(.white)
            } else {
                Text("This device can't read barcodes live. Type the number or pick a photo of it.").foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            HStack {
                TextField("Barcode number", text: $typed).keyboardType(.numberPad)
                    .padding(10).background(.white.opacity(0.12), in: .rect(cornerRadius: 10)).foregroundStyle(.white)
                Button("Look up") { handle(code: typed) }.buttonStyle(.bordered).tint(.white).disabled(typed.count < 6)
            }
            .padding(.horizontal, 30)
        }
    }

    /// The target the camera reads inside, with a sweeping red line while it looks.
    private var viewfinder: some View {
        GeometryReader { g in
            let w = min(g.size.width - 80, 300), h = w * 0.52
            ZStack {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.94, green: 0.79, blue: 0.63), lineWidth: 3)
                    .frame(width: w, height: h)
                SweepLine(active: !busy && result == nil).frame(width: w - 30, height: h)
            }
            .position(x: g.size.width / 2, y: g.size.height * 0.42)
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle()) }
                .accessibilityLabel("Close")
            Spacer()
            Button { setTorch(!torch) } label: {
                Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill").font(.headline).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(torch ? "Torch off" : "Torch on")
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "photo").font(.headline).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Read a barcode from a photo")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 8) {
            if busy { ProgressView().tint(.white).padding(10).background(.ultraThinMaterial, in: Capsule()) }
            Text(note ?? hint).font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                .animation(.easeOut(duration: 0.2), value: note)
        }
        .padding(.bottom, 12)
    }

    private var hint: String {
        switch mode {
        case .barcode: several ? "Scan each item: they collect below" : "Hold steady: it reads by itself"
        case .label: seenText.count < 40 ? "Fill the frame with the nutrition panel" : "Got it. Tap Read label."
        case .menu: seenText.count < 40 ? "Point at the menu" : "Got it. Tap Rank dishes."
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { withAnimation(.snappy) { mode = m; seenText = ""; note = nil; menuPicks = [] } } label: {
                    Text(m.rawValue).font(.subheadline.weight(mode == m ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(mode == m ? Color.white : Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(mode == m ? Color.black : Color.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private var bottomTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .barcode:
                Toggle(isOn: $several) { Text("Scan several").font(.subheadline) }.tint(Nautical.chartRed)
                if !haul.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(haul) { f in Text(f.name).font(.caption).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.14), in: Capsule()) } }
                    }
                    Button { logHaul() } label: { Text("Log \(haul.count) item\(haul.count == 1 ? "" : "s")").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Nautical.chartRed)
                }
            case .label:
                Button { Task { await readLabel() } } label: {
                    Label(FoodAI.isAvailable ? "Read label with Apple Intelligence" : "Read label", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Nautical.chartRed).disabled(seenText.count < 20 || busy)
            case .menu:
                if menuPicks.isEmpty {
                    Button { Task { await rankMenu() } } label: { Label("Rank dishes for me", systemImage: "sparkles").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Nautical.chartRed).disabled(seenText.count < 30 || busy || !FoodAI.isAvailable)
                    if !FoodAI.isAvailable { Text("Menu ranking needs Apple Intelligence.").font(.caption).foregroundStyle(.white.opacity(0.7)) }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(menuPicks.enumerated()), id: \.offset) { i, p in
                                HStack(alignment: .top, spacing: 10) {
                                    WaypointBadge(number: i + 1, isNext: i == 0)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.dish).font(.subheadline.weight(.semibold))
                                        Text("~\(p.calories) kcal · \(p.protein) g protein · \(p.why)").font(.caption).foregroundStyle(.white.opacity(0.75))
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: Actions

    private func askForCamera() async {
        if access == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func handle(code raw: String) {
        let code = raw.filter(\.isNumber)
        guard !busy, result == nil, code.count >= 6, code != lastCode else { return }
        lastCode = code
        busy = true
        note = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { busy = false }
            switch await FoodLibrary.lookup(barcode: code, ctx: ctx) {
            case .found(let p, _):
                if let hit = MealPlanner.checkOff(productName: p.displayName, ctx: ctx) { note = "Checked “\(hit)” off your grocery list." }
                let f = ScannedFood(product: p)
                if several {
                    if !haul.contains(where: { $0.barcode == f.barcode }) { withAnimation(.snappy) { haul.append(f) } }
                    note = "Added \(f.name)"
                    try? await Task.sleep(for: .seconds(1.2)); lastCode = ""
                } else {
                    result = f
                }
            case .notFound(let c):
                pendingBarcode = c
                note = "Not in any database yet. Point at the nutrition panel."
                withAnimation(.snappy) { mode = .label }
            case .failed(let why):
                note = why
                lastCode = ""
            }
        }
    }

    private func readLabel() async {
        busy = true; defer { busy = false }
        let name: String
        if let l = await FoodAI.readLabel(seenText) {
            // Apple Intelligence read the panel: write it in the label parser's words so the library stores it the usual way.
            let text = """
            \(l.ingredients.isEmpty ? "" : "Ingredients: \(l.ingredients)")
            Serving size \(l.serving)
            Calories \(l.calories)
            Total Fat \(l.fat)g
            Sodium \(l.sodiumMg)mg
            Total Carbohydrate \(l.carbs)g
            Dietary Fiber \(l.fiber)g
            Total Sugars \(l.sugar)g
            Includes \(l.addedSugar)g Added Sugars
            Protein \(l.protein)g
            """
            name = l.name
            let p = FoodLibrary.fromLabel(text + "\n" + seenText, barcode: pendingBarcode, name: name, ctx: ctx)
            if !l.allergens.isEmpty { p.allergens = l.allergens.split(separator: ",").map { "en:" + $0.trimmingCharacters(in: .whitespaces).lowercased() } }
            try? ctx.save()
            result = ScannedFood(product: p, fromLabel: true)
        } else {
            let p = FoodLibrary.fromLabel(seenText, barcode: pendingBarcode, name: "", ctx: ctx)
            result = ScannedFood(product: p, fromLabel: true)
        }
        pendingBarcode = nil
        seenText = ""
    }

    private func rankMenu() async {
        busy = true; defer { busy = false }
        menuPicks = await FoodAI.rankMenu(seenText, ctx: ctx)
        if menuPicks.isEmpty { note = "Couldn't read enough of the menu. Get closer." }
    }

    private func logHaul() {
        for f in haul { _ = NutritionLog.log(f.product, servings: 1, meal: meal, ctx: ctx) }
        try? ctx.save()
        UndoCenter.shared.notify("Logged \(haul.count) items")
        Haptics.success()
        haul = []
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data)?.cgImage else { return }
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: img).perform([req])
        if let code = req.results?.compactMap(\.payloadStringValue).first { handle(code: code) }
        else { note = "No barcode found in that photo." }
        photo = nil
    }

    private func setTorch(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
        torch = on
    }
}

/// What a scan found, ready for the result card.
struct ScannedFood: Identifiable {
    let id = UUID()
    let product: FoodProduct
    var fromLabel = false
    var name: String { product.displayName }
    var barcode: String { product.barcode }
}

private struct SweepLine: View {
    let active: Bool
    @State private var down = false
    var body: some View {
        GeometryReader { g in
            Rectangle().fill(Nautical.chartRed).frame(height: 2).shadow(color: Nautical.chartRed, radius: 6)
                .offset(y: down ? g.size.height - 20 : 20)
                .opacity(active ? 1 : 0)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { down = true } }
    }
}

#if !targetEnvironment(macCatalyst)
/// VisionKit's live reader. Food barcodes (UPC, EAN, ITF), QR and the common 1-D codes; text for labels and menus.
private struct LiveScanner: UIViewControllerRepresentable {
    let mode: BarcodeReaderView.Mode
    let onCode: (String) -> Void
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .barcode
            ? [.barcode(symbologies: [.ean13, .ean8, .upce, .itf14, .i2of5, .code128, .code39, .code93, .qr, .dataMatrix])]
            : [.text()]
        let vc = DataScannerViewController(recognizedDataTypes: types, qualityLevel: mode == .barcode ? .fast : .accurate,
                                           recognizesMultipleItems: mode != .barcode, isHighFrameRateTrackingEnabled: mode == .barcode,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: mode != .barcode, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveScanner
        init(parent: LiveScanner) { self.parent = parent }
        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) { take(allItems) }
        func dataScanner(_ s: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) { take(allItems) }
        func dataScanner(_ s: DataScannerViewController, didTapOn item: RecognizedItem) { take([item]) }

        private func take(_ items: [RecognizedItem]) {
            var texts: [String] = []
            for item in items {
                switch item {
                case .barcode(let b): if parent.mode == .barcode, let v = b.payloadStringValue { parent.onCode(v); return }
                case .text(let t): texts.append(t.transcript)
                @unknown default: break
                }
            }
            if parent.mode != .barcode, !texts.isEmpty { parent.onText(texts.joined(separator: "\n")) }
        }
    }
}
#endif

// MARK: - The result card

/// Slides up over the live camera: the product, a serving, and Apple Intelligence's verdict for you.
struct ScanResultSheet: View {
    let food: ScannedFood
    var meal: String
    var onDone: (Bool) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var servings = 1.0
    @State private var pickedMeal = ""
    @State private var verdict: FoodAI.Verdict?
    @State private var thinking = true

    var body: some View {
        let p = food.product
        let facts = p.facts.scaled(servings)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AsyncImage(url: p.imageURL.flatMap(URL.init(string:))) { img in img.resizable().scaledToFill() } placeholder: {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .frame(width: 56, height: 56).background(DS.Palette.elevated).clipShape(.rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(.system(.title3, design: .serif).weight(.semibold)).lineLimit(2)
                        Text([p.brand, p.facts.servingLabel, food.fromLabel ? "from the label" : p.barcode].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                            .font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                    }
                }
                aiCard
                HStack {
                    Text("Serving").font(.subheadline)
                    Spacer()
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { s in
                        Button { servings = s; Haptics.tap() } label: {
                            Text(s == 0.5 ? "½" : s == 1.5 ? "1½" : "\(Int(s))").font(.subheadline.weight(.semibold))
                                .frame(minWidth: 34).padding(.vertical, 6)
                                .background(servings == s ? DS.Palette.ink : DS.Palette.elevated, in: Capsule())
                                .foregroundStyle(servings == s ? DS.Palette.canvas : DS.Palette.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("\(Int(facts.calories ?? 0)) kcal · \(Int(facts.protein ?? 0)) P · \(Int(facts.carbs ?? 0)) C · \(Int(facts.fat ?? 0)) F")
                    .font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                MealChips(meal: $pickedMeal)
                Button {
                    _ = NutritionLog.log(p, servings: servings, meal: pickedMeal, ctx: ctx)
                    try? ctx.save()
                    onDone(true)
                } label: { Text("Log it").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).tint(DS.Palette.ink)
            }
            .padding(18)
        }
        .onAppear { if pickedMeal.isEmpty { pickedMeal = meal } }
        .task {
            verdict = await FoodAI.verdict(name: p.displayName, brand: p.brand, ingredients: p.ingredients, facts: p.facts, ctx: ctx)
            thinking = false
        }
    }

    @ViewBuilder private var aiCard: some View {
        if FoodAI.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Label("Apple Intelligence · for you", systemImage: "sparkles").font(DS.Font.mono).foregroundStyle(Color.purple)
                if let v = verdict {
                    Text(v.headline).font(.subheadline.weight(.semibold))
                        .foregroundStyle(v.rating.lowercased() == "poor" ? Nautical.chartRed : v.rating.lowercased() == "good" ? DS.Palette.calm : DS.Palette.warmth)
                    Text(v.detail).font(.subheadline).foregroundStyle(DS.Palette.ink)
                    if !v.allergens.isEmpty { Label("Contains \(v.allergens)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Nautical.chartRed) }
                    HStack {
                        if !v.swap.isEmpty { Text("Swap: \(v.swap)").font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(DS.Palette.elevated, in: Capsule()) }
                        if !v.addOn.isEmpty { Text("Add: \(v.addOn)").font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(DS.Palette.elevated, in: Capsule()) }
                    }
                } else if thinking {
                    HStack { ProgressView(); Text("Checking it against your day…").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.purple.opacity(0.35), lineWidth: 1))
        } else if let r = food.product.result {
            Label(r.verdict.label + (r.guideNote.map { " · " + $0 } ?? ""), systemImage: "circle.fill")
                .font(.subheadline).foregroundStyle(r.verdict.color)
        }
    }
}

/// Breakfast · Lunch · Dinner · Snack as one row of chips (no hidden menu).
struct MealChips: View {
    @Binding var meal: String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { m in
                Button { meal = m; Haptics.tap() } label: {
                    Text(m.capitalized).font(.caption.weight(meal == m ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(meal == m ? DS.Palette.ink : DS.Palette.elevated, in: Capsule())
                        .foregroundStyle(meal == m ? DS.Palette.canvas : DS.Palette.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
