import SwiftUI
import Charts
import PDFKit
import Vision
import PhotosUI
import UniformTypeIdentifiers
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

// MARK: - Health records: lab reports and letters, read on this device, with the numbers pulled out into Biology
//
// Files stay in Keel's private storage on this iPhone (they aren't synced or uploaded). Text is read with Apple's
// on-device text recognition; the summary comes from Apple Intelligence on the device when it's available.

struct HealthRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date = Date()
    var fileName: String
    var isPDF: Bool
    var text = ""
    var summary = ""
}

struct BiomarkerReading: Codable, Identifiable, Hashable {
    var id = UUID()
    var marker: String          // Biomarker id
    var value: Double
    var date: Date
    var recordId: UUID?
}

struct FoundMarker: Identifiable, Hashable { let def: BiomarkerDef; let value: Double; var id: String { def.id } }

struct BiomarkerDef: Identifiable, Hashable {
    let id: String
    let name: String
    let unit: String
    let low: Double?
    let high: Double?
    let aliases: [String]
    let plausible: ClosedRange<Double>
    let about: String
}

@MainActor
enum Biomarkers {
    static let defs: [BiomarkerDef] = [
        BiomarkerDef(id: "chol", name: "Total cholesterol", unit: "mg/dL", low: nil, high: 200, aliases: ["total cholesterol", "cholesterol, total", "cholesterol total"], plausible: 60...500, about: "All the cholesterol in your blood."),
        BiomarkerDef(id: "ldl", name: "LDL cholesterol", unit: "mg/dL", low: nil, high: 100, aliases: ["ldl cholesterol", "ldl-c", "ldl chol", "ldl"], plausible: 10...400, about: "The kind that builds up in arteries. Lower is better."),
        BiomarkerDef(id: "hdl", name: "HDL cholesterol", unit: "mg/dL", low: 40, high: nil, aliases: ["hdl cholesterol", "hdl-c", "hdl"], plausible: 10...150, about: "The protective kind. Higher is better."),
        BiomarkerDef(id: "trig", name: "Triglycerides", unit: "mg/dL", low: nil, high: 150, aliases: ["triglycerides", "triglyceride"], plausible: 20...2000, about: "Fat in the blood; rises with sugar, alcohol and refined carbs."),
        BiomarkerDef(id: "glucose", name: "Glucose (fasting)", unit: "mg/dL", low: 70, high: 99, aliases: ["glucose, fasting", "fasting glucose", "glucose"], plausible: 30...600, about: "Blood sugar after not eating."),
        BiomarkerDef(id: "a1c", name: "HbA1c", unit: "%", low: nil, high: 5.6, aliases: ["hemoglobin a1c", "haemoglobin a1c", "hba1c", "a1c"], plausible: 3...15, about: "Average blood sugar over about 3 months."),
        BiomarkerDef(id: "vitd", name: "Vitamin D", unit: "ng/mL", low: 30, high: 100, aliases: ["vitamin d, 25-hydroxy", "25-hydroxy vitamin d", "25-oh vitamin d", "vitamin d"], plausible: 3...200, about: "Low levels are common, especially in winter."),
        BiomarkerDef(id: "b12", name: "Vitamin B12", unit: "pg/mL", low: 200, high: 900, aliases: ["vitamin b12", "b12", "cobalamin"], plausible: 50...3000, about: "Needed for energy and nerves."),
        BiomarkerDef(id: "ferritin", name: "Ferritin", unit: "ng/mL", low: 30, high: 300, aliases: ["ferritin"], plausible: 2...3000, about: "Your iron stores. Low ferritin can cause tiredness and restless legs."),
        BiomarkerDef(id: "iron", name: "Iron", unit: "µg/dL", low: 60, high: 170, aliases: ["iron, total", "serum iron", "iron"], plausible: 5...500, about: "Iron in the blood right now."),
        BiomarkerDef(id: "tsh", name: "TSH (thyroid)", unit: "mIU/L", low: 0.4, high: 4.0, aliases: ["tsh", "thyroid stimulating hormone"], plausible: 0.01...100, about: "How hard your brain is asking the thyroid to work."),
        BiomarkerDef(id: "ft4", name: "Free T4", unit: "ng/dL", low: 0.8, high: 1.8, aliases: ["free t4", "t4, free", "ft4"], plausible: 0.1...8, about: "Thyroid hormone."),
        BiomarkerDef(id: "hgb", name: "Hemoglobin", unit: "g/dL", low: 12, high: 17.5, aliases: ["hemoglobin", "haemoglobin", "hgb"], plausible: 4...25, about: "Carries oxygen. Low means anaemia."),
        BiomarkerDef(id: "wbc", name: "White blood cells", unit: "×10³/µL", low: 4, high: 11, aliases: ["white blood cell count", "wbc", "white blood cells", "leukocytes"], plausible: 0.5...60, about: "Your immune cells."),
        BiomarkerDef(id: "plt", name: "Platelets", unit: "×10³/µL", low: 150, high: 400, aliases: ["platelet count", "platelets", "plt"], plausible: 10...1500, about: "Help your blood clot."),
        BiomarkerDef(id: "creat", name: "Creatinine", unit: "mg/dL", low: 0.6, high: 1.3, aliases: ["creatinine"], plausible: 0.1...15, about: "A kidney marker."),
        BiomarkerDef(id: "egfr", name: "eGFR", unit: "mL/min", low: 90, high: nil, aliases: ["egfr", "estimated gfr"], plausible: 5...200, about: "How well your kidneys filter. Higher is better."),
        BiomarkerDef(id: "alt", name: "ALT (liver)", unit: "U/L", low: 7, high: 56, aliases: ["alt", "alanine aminotransferase", "sgpt"], plausible: 1...2000, about: "A liver enzyme."),
        BiomarkerDef(id: "ast", name: "AST (liver)", unit: "U/L", low: 10, high: 40, aliases: ["ast", "aspartate aminotransferase", "sgot"], plausible: 1...2000, about: "A liver and muscle enzyme."),
        BiomarkerDef(id: "crp", name: "CRP (inflammation)", unit: "mg/L", low: nil, high: 3, aliases: ["hs-crp", "hscrp", "c-reactive protein", "crp"], plausible: 0.01...300, about: "A marker of inflammation."),
        BiomarkerDef(id: "na", name: "Sodium", unit: "mmol/L", low: 135, high: 145, aliases: ["sodium"], plausible: 100...180, about: "A key salt in your blood."),
        BiomarkerDef(id: "k", name: "Potassium", unit: "mmol/L", low: 3.5, high: 5.1, aliases: ["potassium"], plausible: 1.5...9, about: "Important for heart and muscles."),
        BiomarkerDef(id: "ca", name: "Calcium", unit: "mg/dL", low: 8.5, high: 10.5, aliases: ["calcium"], plausible: 4...16, about: "Bones, nerves and muscles."),
        BiomarkerDef(id: "mg", name: "Magnesium", unit: "mg/dL", low: 1.7, high: 2.2, aliases: ["magnesium"], plausible: 0.5...5, about: "Sleep, muscles and nerves."),
        BiomarkerDef(id: "uric", name: "Uric acid", unit: "mg/dL", low: 3.5, high: 7.2, aliases: ["uric acid"], plausible: 0.5...20, about: "High levels can cause gout."),
        BiomarkerDef(id: "testo", name: "Testosterone", unit: "ng/dL", low: nil, high: nil, aliases: ["testosterone, total", "total testosterone", "testosterone"], plausible: 1...2000, about: "A hormone that affects energy, mood and muscle."),
    ]

    static func def(_ id: String) -> BiomarkerDef? { defs.first { $0.id == id } }

    static let readingsKey = "health.biomarkers"
    static var readings: [BiomarkerReading] {
        get { LocalLog.load(readingsKey) }
        set { LocalLog.save(Array(newValue.suffix(2000)), readingsKey) }
    }

    static func latest() -> [String: BiomarkerReading] {
        var out: [String: BiomarkerReading] = [:]
        for r in readings.sorted(by: { $0.date < $1.date }) { out[r.marker] = r }
        return out
    }

    static func status(_ d: BiomarkerDef, _ v: Double) -> (String, Color) {
        if let lo = d.low, v < lo { return ("Low", .orange) }
        if let hi = d.high, v > hi { return ("High", .orange) }
        return (d.low == nil && d.high == nil ? "Recorded" : "In range", DS.Palette.calm)
    }

    /// Finds known markers in report text: the marker's name, then the first number after it (same line, or the next).
    /// When names overlap ("hemoglobin a1c" contains "hemoglobin"), the longest match wins.
    static func extract(from text: String) -> [FoundMarker] {
        var found: [String: Double] = [:]
        let lines = text.components(separatedBy: .newlines)
        let number = try? NSRegularExpression(pattern: #"(?<![\d.A-Za-z])(\d{1,4}(?:[.,]\d{1,3})?)(?![\d.,]?\d)(?![A-Za-z])"#)
        func wholeWord(_ line: String, _ r: Range<String.Index>) -> Bool {
            let before: Character = r.lowerBound == line.startIndex ? " " : line[line.index(before: r.lowerBound)]
            let after: Character = r.upperBound == line.endIndex ? " " : line[r.upperBound]
            return !before.isLetter && !after.isLetter
        }
        func firstNumber(_ c: String, in d: BiomarkerDef) -> Double? {
            guard let number else { return nil }
            for m in number.matches(in: c, range: NSRange(c.startIndex..., in: c)) {
                guard let mr = Range(m.range(at: 1), in: c), let v = Double(c[mr].replacingOccurrences(of: ",", with: ".")) else { continue }
                return d.plausible.contains(v) ? v : nil          // the first number after the name is the result, or nothing
            }
            return nil
        }
        for (i, raw) in lines.enumerated() {
            let line = raw.lowercased()
            // Every marker name on this line, longest alias per marker.
            var hits: [(def: BiomarkerDef, range: Range<String.Index>)] = []
            for d in defs {
                let matches = d.aliases.compactMap { a -> Range<String.Index>? in
                    guard let r = line.range(of: a), wholeWord(line, r) else { return nil }
                    return r
                }
                if let best = matches.max(by: { line.distance(from: $0.lowerBound, to: $0.upperBound) < line.distance(from: $1.lowerBound, to: $1.upperBound) }) {
                    hits.append((d, best))
                }
            }
            // Drop a name that sits inside another, longer name on the line.
            let kept = hits.filter { h in
                !hits.contains { o in o.def.id != h.def.id && o.range != h.range && o.range.lowerBound <= h.range.lowerBound && o.range.upperBound >= h.range.upperBound }
            }
            for h in kept where found[h.def.id] == nil {
                let sameLine = String(line[h.range.upperBound...])
                let nextLine = i + 1 < lines.count ? lines[i + 1] : ""
                let hasNumberOnLine = (number?.firstMatch(in: sameLine, range: NSRange(sameLine.startIndex..., in: sameLine))) != nil
                if let v = hasNumberOnLine ? firstNumber(sameLine, in: h.def) : firstNumber(nextLine, in: h.def) { found[h.def.id] = v }
            }
        }
        return defs.compactMap { d in found[d.id].map { FoundMarker(def: d, value: $0) } }
    }
}

@MainActor
enum HealthRecordsStore {
    static var folder: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HealthRecords", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var indexURL: URL { folder.appendingPathComponent("index.json") }

    static var records: [HealthRecord] {
        get { (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([HealthRecord].self, from: $0) } ?? [] }
        set { if let d = try? JSONEncoder().encode(newValue) { try? d.write(to: indexURL, options: [.atomic, .completeFileProtection]) } }
    }

    static func fileURL(_ r: HealthRecord) -> URL { folder.appendingPathComponent(r.fileName) }

    /// Saves a copy, reads its text on the device, and returns the new record (not yet summarised).
    static func add(data: Data, isPDF: Bool, title: String) async -> HealthRecord {
        let name = UUID().uuidString + (isPDF ? ".pdf" : ".jpg")
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        var r = HealthRecord(title: title, fileName: name, isPDF: isPDF)
        r.text = await readText(data: data, isPDF: isPDF)
        return r
    }

    static func readText(data: Data, isPDF: Bool) async -> String {
        if isPDF, let doc = PDFDocument(data: data) {
            let typed = doc.string ?? ""
            if typed.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return typed }
            // A scanned PDF: read each page as an image.
            var out = ""
            for i in 0..<min(doc.pageCount, 8) {
                guard let page = doc.page(at: i) else { continue }
                let img = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
                out += await ocr(img) + "\n"
            }
            return out
        }
        guard let img = UIImage(data: data) else { return "" }
        return await ocr(img)
    }

    static func ocr(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    static func summarize(_ text: String) async -> String {
        guard text.count > 40 else { return "" }
        let prompt = """
        Summarise this medical document for the patient in plain, calm language: what kind of document it is, the date if shown, \
        anything flagged high or low, and what to ask their doctor. 5 short bullet points at most. Don't diagnose. Document:
        \(text.prefix(6000))
        """
        return await AIRouter.shared.write(prompt) ?? ""
    }
}

// MARK: - Screens

struct HealthRecordsView: View {
    @State private var records: [HealthRecord] = []
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var busy = false
    @State private var review: (HealthRecord, [FoundMarker])?

    var body: some View {
        List {
            Section {
                KitIntro(icon: "cross.vial.fill", color: .red, text: "Health records. Add lab results, scans and letters as PDFs or photos. Keel reads them on this iPhone, writes a plain-language summary, and pulls blood results into Biology so you can see them over time. Files stay private on this device.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                Button { importing = true } label: { Label("Add a PDF or file", systemImage: "doc.badge.plus") }
                PhotosPicker(selection: $photo, matching: .images) { Label("Add a photo", systemImage: "photo.badge.plus") }
                #if !targetEnvironment(macCatalyst)
                if VNDocumentCameraViewController.isSupported {
                    Button { scanning = true } label: { Label("Scan a paper document", systemImage: "doc.viewfinder") }
                }
                #endif
                if busy { HStack { ProgressView(); Text("Reading it…").foregroundStyle(DS.Palette.inkSoft) } }
            }
            Section { NavigationLink { LazyView(BiologyView()) } label: { Label("Biology: your blood results", systemImage: "drop.fill") } }
            Section("Records") {
                if records.isEmpty { Text("Nothing yet.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(records.sorted { $0.date > $1.date }) { r in
                    NavigationLink { LazyView(HealthRecordDetail(record: r)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(r.title, systemImage: r.isPDF ? "doc.text.fill" : "photo.fill")
                            Text(r.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                .onDelete { idx in
                    let sorted = records.sorted { $0.date > $1.date }
                    for i in idx { try? FileManager.default.removeItem(at: HealthRecordsStore.fileURL(sorted[i])) }
                    let ids = idx.map { sorted[$0].id }
                    records.removeAll { ids.contains($0.id) }; HealthRecordsStore.records = records
                }
            }
        }
        .navigationTitle("Health records")
        .onAppear { records = HealthRecordsStore.records }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let isPDF = url.pathExtension.lowercased() == "pdf"
            ingest(data, isPDF: isPDF, title: url.deletingPathExtension().lastPathComponent)
        }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self),
                   let jpg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                    ingest(jpg, isPDF: false, title: "Photo record")
                }
                self.photo = nil
            }
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $scanning) {
            RecordScanner { pdf in scanning = false; if let pdf { ingest(pdf, isPDF: true, title: "Scanned document") } }
                .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
            if let review { BiomarkerReviewSheet(record: review.0, found: review.1) { review = nil } }
        }
    }

    private func ingest(_ data: Data, isPDF: Bool, title: String) {
        busy = true
        Task {
            var r = await HealthRecordsStore.add(data: data, isPDF: isPDF, title: title)
            r.summary = await HealthRecordsStore.summarize(r.text)
            records.append(r); HealthRecordsStore.records = records
            busy = false
            let found = Biomarkers.extract(from: r.text)
            if !found.isEmpty { review = (r, found) }
            Haptics.success()
        }
    }
}

/// Check what Keel read before it's saved: untick anything it got wrong, fix the date.
struct BiomarkerReviewSheet: View {
    let record: HealthRecord
    let found: [FoundMarker]
    var done: () -> Void
    @State private var keep: Set<String> = []
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section { DatePicker("Test date", selection: $date, in: ...Date(), displayedComponents: .date) }
                Section {
                    ForEach(found) { f in
                        let d = f.def
                        let v = f.value
                        Button {
                            if keep.contains(d.id) { keep.remove(d.id) } else { keep.insert(d.id) }
                        } label: {
                            HStack {
                                Image(systemName: keep.contains(d.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(keep.contains(d.id) ? DS.Palette.calm : DS.Palette.inkSoft)
                                Text(d.name).foregroundStyle(DS.Palette.ink)
                                Spacer()
                                Text("\(v.formatted()) \(d.unit)").monospacedDigit().foregroundStyle(Biomarkers.status(d, v).1)
                            }
                        }
                    }
                } footer: { Text("Keel read these from the document. Untick any that look wrong before saving.") }
            }
            .navigationTitle("Found \(found.count) results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { done() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Biomarkers.readings += found.filter { keep.contains($0.id) }.map { BiomarkerReading(marker: $0.id, value: $0.value, date: date, recordId: record.id) }
                        Haptics.success(); done()
                    }
                }
            }
            .onAppear { keep = Set(found.map(\.id)) }
        }
    }
}

struct HealthRecordDetail: View {
    let record: HealthRecord
    var body: some View {
        List {
            if !record.summary.isEmpty { Section("Summary") { Text(record.summary).font(.callout) } }
            Section {
                if record.isPDF {
                    RecordPDFView(url: HealthRecordsStore.fileURL(record)).frame(height: 480)
                } else if let img = UIImage(contentsOfFile: HealthRecordsStore.fileURL(record).path) {
                    Image(uiImage: img).resizable().scaledToFit()
                }
            }
            if !record.text.isEmpty {
                Section("Text Keel read") { Text(record.text).font(.caption).textSelection(.enabled) }
            }
        }
        .navigationTitle(record.title)
        .toolbar { ShareLink(item: HealthRecordsStore.fileURL(record)) }
    }
}

struct RecordPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: url); return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

#if !targetEnvironment(macCatalyst)
struct RecordScanner: UIViewControllerRepresentable {
    var done: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController(); vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let doc = PDFDocument()
            for i in 0..<scan.pageCount { if let page = PDFPage(image: scan.imageOfPage(at: i)) { doc.insert(page, at: doc.pageCount) } }
            done(doc.dataRepresentation())
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}
#endif

struct BiologyView: View {
    @State private var readings: [BiomarkerReading] = []
    @State private var adding: BiomarkerDef?
    @State private var value = ""
    @State private var date = Date()

    var body: some View {
        let latest = Dictionary(grouping: readings, by: \.marker).compactMapValues { $0.max { $0.date < $1.date } }
        List {
            Section {
                KitIntro(icon: "drop.fill", color: .red, text: "Biology. Your blood results over time, with the usual healthy range. Results come from records you add, or type one in. Ranges vary between labs, so check anything flagged with your doctor.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if !latest.isEmpty {
                Section("Your results") {
                    ForEach(Biomarkers.defs.filter { latest[$0.id] != nil }) { d in
                        let r = latest[d.id]!
                        let (label, color) = Biomarkers.status(d, r.value)
                        NavigationLink { LazyView(BiomarkerTrendView(def: d)) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name)
                                    Text(r.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(r.value.formatted()) \(d.unit)").monospacedDigit()
                                    Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
                                }
                            }
                        }
                    }
                }
            }
            Section("Add a result") {
                Menu {
                    ForEach(Biomarkers.defs) { d in Button(d.name) { adding = d; value = ""; date = Date() } }
                } label: { Label("Type one in", systemImage: "plus.circle") }
                NavigationLink { LazyView(HealthRecordsView()) } label: { Label("From a lab report", systemImage: "doc.text.magnifyingglass") }
            }
        }
        .navigationTitle("Biology")
        .onAppear { readings = Biomarkers.readings }
        .alert(adding?.name ?? "", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            TextField("Value in \(adding?.unit ?? "")", text: $value).keyboardType(.decimalPad)
            Button("Save") {
                if let d = adding, let v = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    Biomarkers.readings += [BiomarkerReading(marker: d.id, value: v, date: date)]
                    readings = Biomarkers.readings; Haptics.success()
                }
                adding = nil
            }
            Button("Cancel", role: .cancel) { adding = nil }
        }
    }
}

struct BiomarkerTrendView: View {
    let def: BiomarkerDef
    var body: some View {
        let points = Biomarkers.readings.filter { $0.marker == def.id }.sorted { $0.date < $1.date }
        List {
            Section {
                Chart {
                    if let hi = def.high {
                        RuleMark(y: .value("High", hi)).foregroundStyle(.orange.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if let lo = def.low {
                        RuleMark(y: .value("Low", lo)).foregroundStyle(.orange.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value(def.name, p.value)).foregroundStyle(.red.gradient)
                        PointMark(x: .value("Date", p.date), y: .value(def.name, p.value)).foregroundStyle(Biomarkers.status(def, p.value).1)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
            }
            Section("About") {
                Text(def.about)
                Text("Usual range: \(def.low.map { "\($0.formatted())" } ?? "–") to \(def.high.map { "\($0.formatted())" } ?? "–") \(def.unit)").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Section("Readings") {
                ForEach(points.reversed()) { p in
                    LabeledContent(p.date.formatted(date: .abbreviated, time: .omitted), value: "\(p.value.formatted()) \(def.unit)")
                }
            }
        }
        .navigationTitle(def.name)
    }
}
