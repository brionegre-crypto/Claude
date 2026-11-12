import SwiftUI
import SwiftData

/// Settings → Mail → Rules.
struct MailRulesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MailRule.createdAt) private var rules: [MailRule]
    @State private var editing: MailRule?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(rules) { r in
                    Button { editing = r } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(MailRules.Field(rawValue: r.field)?.label ?? r.field) contains “\(r.contains)”")
                                    .foregroundStyle(DS.Palette.ink)
                                Text("→ \(MailRules.label(for: r.action)) · used \(r.timesApplied)×")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { r.isOn }, set: { r.isOn = $0 })).labelsHidden()
                        }
                    }
                }
                .onDelete { for i in $0 { ctx.delete(rules[i]) } }
            } footer: {
                Text("Rules run on new mail as it arrives, before AI sorting. Archive, star and read changes sync back to your mail account.")
            }
            if rules.isEmpty {
                ContentUnavailableView("No rules yet", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Tip: long-press any email and choose Create Rule."))
            }
        }
        .navigationTitle("Rules")
        .toolbar { Button("Add", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { MailRuleEditor(rule: nil) }
        .sheet(item: $editing) { MailRuleEditor(rule: $0) }
    }
}

struct MailRuleEditor: View {
    var rule: MailRule?
    var prefillField: String = "from"
    var prefillText: String = ""
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var field = "from"
    @State private var text = ""
    @State private var action = "archive"
    @State private var runNow = true

    var body: some View {
        NavigationStack {
            Form {
                Section("If") {
                    Picker("Field", selection: $field) {
                        ForEach(MailRules.Field.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    TextField("contains…", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Then") {
                    Picker("Action", selection: $action) {
                        ForEach(MailRules.actions, id: \.id) { Label($0.label, systemImage: $0.icon).tag($0.id) }
                    }
                }
                if rule == nil {
                    Section { Toggle("Also apply to mail already in Inbox", isOn: $runNow) }
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let r = rule { field = r.field; text = r.contains; action = r.action }
                else { field = prefillField; text = prefillText }
            }
        }
    }

    private func save() {
        if let r = rule {
            r.field = field; r.contains = text; r.action = action
        } else {
            let r = MailRule(field: field, contains: text, action: action)
            ctx.insert(r)
            if runNow {
                let inbox = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived }))) ?? [])
                    .filter { MailRules.matches(r, $0) }
                let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
                Task { await MailRules.apply(to: inbox, accounts: accounts, ctx: ctx) }
            }
        }
        Haptics.success()
        dismiss()
    }
}
