import SwiftUI
import SwiftData
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// Logging what you ate, from a scanned product or a description.
@MainActor
enum NutritionLog {
    @discardableResult
    static func log(_ p: FoodProduct, servings: Double, meal: String, ctx: ModelContext) -> FoodEntry {
        let e = FoodEntry(name: p.displayName, facts: p.facts.scaled(servings), meal: meal, verdict: p.verdict)
        e.servings = servings
        e.barcode = p.barcode
        e.tagsRaw = BrainFoods.tags(for: p.name + " " + p.ingredients).joined(separator: ",")
        finish(e, ctx: ctx)
        return e
    }

    @discardableResult
    static func logMeal(name: String, ingredients: String, facts: NutritionFacts, verdict: DietVerdict, meal: String, ctx: ModelContext) -> FoodEntry {
        let e = FoodEntry(name: name, facts: facts, meal: meal, verdict: verdict)
        e.tagsRaw = BrainFoods.tags(for: name + " " + ingredients).joined(separator: ",")
        finish(e, ctx: ctx)
        return e
    }

    private static func finish(_ e: FoodEntry, ctx: ModelContext) {
        if e.meal == "breakfast", (e.facts.protein ?? 0) >= 20 { e.tagsRaw += (e.tagsRaw.isEmpty ? "" : ",") + "protein" }
        ctx.insert(e)
        try? ctx.save()
        Haptics.success()
        Task { await NutritionHealth.save(e); try? ctx.save() }
    }

    static func delete(_ e: FoodEntry, ctx: ModelContext) {
        let id = e.id
        ctx.delete(e)
        try? ctx.save()
        Task { await NutritionHealth.remove(id) }
    }
}

/// Point the camera at a barcode, or switch to Label to read the ingredients and nutrition panel.
struct FoodScanView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    enum Mode: String, CaseIterable { case barcode = "Barcode", label = "Label" }
    @State private var mode: Mode = .barcode
    @State private var busy = false
    @State private var message: String?
    @State private var product: FoodProduct?
    @State private var labelText = ""
    @State private var pendingBarcode: String?
    @State private var labelName = ""
    @State private var typed = ""
    @State private var lastCode = ""

    private var cameraOK: Bool {
        #if targetEnvironment(macCatalyst)
        return false              // Macs don't have the live scanner: type the barcode or paste the label
        #else
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if cameraOK {
                    #if !targetEnvironment(macCatalyst)
                    ScannerCamera(mode: mode, onBarcode: handle, onText: { labelText = $0 })
                        .id(mode)
                        .ignoresSafeArea(edges: .horizontal)
                    #endif
                } else if mode == .label {
                    TextEditor(text: $labelText)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                        .overlay(alignment: .topLeading) {
                            if labelText.isEmpty {
                                Text("Paste or type the ingredients and nutrition facts from the label.")
                                    .foregroundStyle(DS.Palette.inkSoft).padding(18).allowsHitTesting(false)
                            }
                        }
                        .padding()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera.slash",
                                           description: Text("Type the barcode number below, or switch to Label and paste the ingredients."))
                }
                VStack(spacing: 8) {
                    if busy { ProgressView().padding(10).background(.ultraThinMaterial, in: Capsule()) }
                    if let message {
                        Text(message).font(DS.Font.caption).multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                    }
                    if mode == .label && cameraOK {
                        Text(labelText.isEmpty ? "Hold the ingredients list and nutrition panel in view" : "Reading… \(labelText.count) characters")
                            .font(DS.Font.caption).padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                Picker("Scan", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented)
                if mode == .label {
                    TextField("Product name (optional)", text: $labelName).textFieldStyle(.roundedBorder)
                    Button { useLabel() } label: {
                        Label("Check this label", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(labelText.count < 20)
                } else {
                    HStack {
                        TextField("Or type the barcode number", text: $typed).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Button("Check") { handle(typed) }.buttonStyle(.bordered).disabled(typed.count < 6)
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Scan food")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $product) { FoodResultView(product: $0) }
        .onChange(of: product) { _, p in if p == nil { lastCode = "" } }
    }

    private func handle(_ code: String) {
        guard !busy, code != lastCode else { return }
        lastCode = code
        busy = true
        message = nil
        Haptics.tap()
        Task {
            let outcome = await FoodLibrary.lookup(barcode: code, ctx: ctx)
            busy = false
            switch outcome {
            case .found(let p, _):
                product = p
            case .notFound(let c):
                pendingBarcode = c
                message = "Not in the database yet. Scan the label and Keel will add it to your library."
                withAnimation { mode = .label }
            case .failed(let why):
                message = why
                lastCode = ""
            }
        }
    }

    private func useLabel() {
        let p = FoodLibrary.fromLabel(labelText, barcode: pendingBarcode, name: labelName.trimmingCharacters(in: .whitespaces), ctx: ctx)
        pendingBarcode = nil
        labelText = ""
        labelName = ""
        product = p
    }
}

#if !targetEnvironment(macCatalyst)
/// VisionKit's live scanner: barcodes, or all the text in view.
private struct ScannerCamera: UIViewControllerRepresentable {
    let mode: FoodScanView.Mode
    let onBarcode: (String) -> Void
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .barcode
            ? [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .itf14])]
            : [.text()]
        let vc = DataScannerViewController(recognizedDataTypes: types, qualityLevel: mode == .barcode ? .balanced : .accurate,
                                           recognizesMultipleItems: mode == .label, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: ScannerCamera
        init(parent: ScannerCamera) { self.parent = parent }

        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) { take(allItems) }
        func dataScanner(_ s: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) { take(allItems) }

        private func take(_ items: [RecognizedItem]) {
            var texts: [String] = []
            for item in items {
                switch item {
                case .barcode(let b):
                    if let v = b.payloadStringValue, parent.mode == .barcode { parent.onBarcode(v); return }
                case .text(let t):
                    texts.append(t.transcript)
                @unknown default: break
                }
            }
            if parent.mode == .label, !texts.isEmpty { parent.onText(texts.joined(separator: "\n")) }
        }
    }
}
#endif

/// "Two eggs scrambled in butter with spinach": checked against your diet and estimated on device.
struct DescribeMealView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var meal = FoodEntry.mealNow()
    @State private var busy = false
    @State private var estimateName = ""
    @State private var ingredients = ""
    @State private var facts: NutritionFacts?
    @State private var result: DietResult?

    var body: some View {
        Form {
            Section {
                TextField("What did you eat?", text: $text, axis: .vertical).lineLimit(2...5)
                Picker("Meal", selection: $meal) {
                    ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized) }
                }
            } footer: { Text(MealEstimator.isAvailable ? "Apple Intelligence estimates the numbers on your iPhone." : "Keel checks it against your diet. Add Apple Intelligence for calorie and protein estimates.") }

            Section {
                Button { Task { await check() } } label: {
                    HStack { Text("Check it"); if busy { Spacer(); ProgressView() } }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).count < 3 || busy)
            }

            if let result {
                Section {
                    VerdictHeader(verdict: result.verdict, title: estimateName.isEmpty ? text : estimateName, subtitle: nil)
                    ForEach(result.findings) { FindingRow(f: $0) }
                }
                if let f = facts { Section("Estimate") { FactsGrid(facts: f) } }
                Section {
                    Button("Log it", systemImage: "plus.circle.fill") {
                        NutritionLog.logMeal(name: estimateName.isEmpty ? text : estimateName, ingredients: ingredients.isEmpty ? text : ingredients,
                                             facts: facts ?? NutritionFacts(), verdict: result.verdict, meal: meal, ctx: ctx)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Describe a meal")
    }

    private func check() async {
        busy = true
        defer { busy = false }
        let est = await MealEstimator.estimate(text)
        estimateName = est?.name ?? ""
        ingredients = est?.ingredients ?? ""
        facts = est?.facts
        result = DietChecker.check(name: text, ingredientsText: text + ", " + ingredients, facts: facts)
    }
}
