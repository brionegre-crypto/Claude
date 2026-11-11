import SwiftUI
import SwiftData

/// Odyssey plan: sketch three different 5-year futures, rate each, and notice which one pulls at you.
struct OdysseyView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var paths: [OdysseyPath]
    @State private var selected: OdysseyKind = .current

    var body: some View {
        VStack(spacing: 0) {
            Picker("Path", selection: $selected) {
                ForEach(OdysseyKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if let path = paths.first(where: { $0.kind == selected }) {
                OdysseyPathEditor(path: path)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("Odyssey Plan")
        .toolbar {
            NavigationLink { OdysseyCompare(paths: paths) } label: { Text("Compare") }
                .disabled(paths.allSatisfy { $0.title.isEmpty })
        }
        .onAppear {
            for kind in OdysseyKind.allCases where !paths.contains(where: { $0.kind == kind }) {
                ctx.insert(OdysseyPath(kind: kind))
            }
        }
    }
}

struct OdysseyPathEditor: View {
    @Bindable var path: OdysseyPath

    var body: some View {
        Form {
            Section {
                Text(path.kind.prompt).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                TextField("Give this life a six-word title", text: $path.title).font(DS.Font.headline)
            }
            Section("The next five years") {
                ForEach(0..<5, id: \.self) { i in
                    TextField("Year \(i + 1): where you are, what you're doing", text: Binding(
                        get: { path.years.indices.contains(i) ? path.years[i] : "" },
                        set: { v in
                            while path.years.count <= i { path.years.append("") }
                            path.years[i] = v
                        }), axis: .vertical)
                }
            }
            Section("Questions this path raises") {
                TextField("What would you need to find out?", text: $path.questions, axis: .vertical).lineLimit(2...5)
            }
            Section {
                rating("Resources", "Do I have the time, money and skills?", $path.resources)
                rating("Likability", "How much do I like this?", $path.likability)
                rating("Confidence", "How sure am I that I can pull it off?", $path.confidence)
                rating("Coherence", "Does it fit who I am and what I value?", $path.coherence)
            } header: { Text("Gut check") }
        }
    }

    private func rating(_ title: String, _ help: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(DS.Font.headline)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { n in
                        Circle()
                            .fill(n <= value.wrappedValue ? DS.Palette.accent : DS.Palette.inkSoft.opacity(0.2))
                            .frame(width: 18, height: 18)
                            .onTapGesture { value.wrappedValue = n; Haptics.tap() }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(title): \(value.wrappedValue) of 5")
                .accessibilityAdjustableAction { dir in
                    if dir == .increment { value.wrappedValue = min(5, value.wrappedValue + 1) } else { value.wrappedValue = max(1, value.wrappedValue - 1) }
                }
            }
            Text(help).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(.vertical, 4)
    }
}

struct OdysseyCompare: View {
    let paths: [OdysseyPath]

    var body: some View {
        List {
            ForEach(OdysseyKind.allCases) { kind in
                if let p = paths.first(where: { $0.kind == kind }) {
                    let total = p.resources + p.likability + p.confidence + p.coherence
                    Section(kind.title) {
                        Text(p.title.isEmpty ? "Untitled" : p.title).font(DS.Font.headline)
                        bar("Resources", p.resources)
                        bar("Likability", p.likability)
                        bar("Confidence", p.confidence)
                        bar("Coherence", p.coherence)
                        LabeledContent("Total", value: "\(total) / 20")
                    }
                }
            }
            Section {
                Text("There's no right answer. Notice which path you light up talking about, then pick one small experiment to try this month.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .navigationTitle("Compare")
    }

    private func bar(_ label: String, _ v: Int) -> some View {
        HStack {
            Text(label).frame(width: 100, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(DS.Palette.accent.opacity(0.15))
                    .overlay(alignment: .leading) { Capsule().fill(DS.Palette.accent).frame(width: g.size.width * CGFloat(v) / 5) }
            }
            .frame(height: 8)
        }
        .font(DS.Font.caption)
    }
}
