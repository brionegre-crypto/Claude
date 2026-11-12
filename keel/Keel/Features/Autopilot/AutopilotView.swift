import SwiftUI
import SwiftData

/// The approval inbox: everything Keel prepared, each one tap to do or dismiss.
struct AutopilotView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Suggestion> { $0.status == "pending" }, sort: \Suggestion.createdAt) private var items: [Suggestion]
    @State private var working: UUID?
    @State private var editing: Suggestion?
    @State private var refreshing = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.seal")
                } description: {
                    Text("When Keel spots a reply you owe, an overbooked day, a deadline without time, a slipping task, a promise, a bill or a meeting to prep, it prepares it here.")
                } actions: {
                    Button(refreshing ? "Looking…" : "Look now") { Task { refreshing = true; await Autopilot.refresh(ctx: ctx); refreshing = false } }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.accent).disabled(refreshing)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(items) { s in card(s).listRowSeparator(.hidden) }
        }
        .listStyle(.plain)
        .navigationTitle("Autopilot")
        .refreshable { await Autopilot.refresh(ctx: ctx) }
        .sheet(item: $editing) { s in DraftEditor(suggestion: s) }
    }

    private func card(_ s: Suggestion) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: s.icon).font(.title3).foregroundStyle(DS.Palette.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(DS.Font.headline)
                        Text(s.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                if s.kind == "reply" {
                    Text(s.payload).font(.callout).lineLimit(6)
                        .padding(DS.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                }
                HStack {
                    Button {
                        Task {
                            working = s.id
                            let result = await Autopilot.accept(s, ctx: ctx)
                            working = nil
                            Haptics.success()
                            UndoCenter.shared.notify(result)
                        }
                    } label: {
                        if working == s.id { ProgressView().frame(maxWidth: .infinity) } else { Text(s.acceptLabel).frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                    if s.kind == "reply" { Button("Edit") { editing = s }.buttonStyle(.bordered) }
                    Button { withAnimation { Autopilot.dismiss(s) } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered).accessibilityLabel("Dismiss")
                }
                .disabled(working != nil)
            }
        }
    }
}

/// Edit a drafted reply before it goes.
private struct DraftEditor: View {
    @Bindable var suggestion: Suggestion
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $suggestion.payload).padding()
                .navigationTitle(suggestion.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Today: a single line that opens Autopilot when Keel has something ready.
struct AutopilotTodayCard: View {
    @Query(filter: #Predicate<Suggestion> { $0.status == "pending" }) private var items: [Suggestion]
    var body: some View {
        if !items.isEmpty {
            NavigationLink { AutopilotView() } label: {
                GlassCard(tint: DS.Palette.accent) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(DS.Palette.accent)
                            .symbolEffect(.pulse, options: .repeat(2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keel prepared \(items.count) thing\(items.count == 1 ? "" : "s") for you").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text(items.prefix(3).map(\.title).joined(separator: " · ")).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
