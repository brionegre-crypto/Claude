import SwiftUI

/// Settings → AI & Privacy → What Keel Knows.
struct MemoryView: View {
    @State private var memory = KeelMemory.shared
    @State private var newFact = ""
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                ForEach(Array(memory.facts.enumerated()), id: \.offset) { i, f in
                    TextField("Fact", text: Binding(get: { f }, set: { memory.update(i, $0) }), axis: .vertical)
                }
                .onDelete { memory.remove(at: $0) }
                HStack {
                    TextField("Teach Keel something…", text: $newFact)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newFact.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                // Many at once: copy a list (one fact per line) from Notes, a message or anywhere, then tap.
                Button("Paste a list of facts", systemImage: "doc.on.clipboard") { pasteMany() }
            } footer: {
                Text("Keel uses these to personalize plans, reply drafts, briefings and answers. You can also just tell Ask Keel: “Remember that my manager is Dana.” Stored only on this iPhone.")
            }
            if memory.facts.isEmpty {
                Section("Ideas") {
                    ForEach(["I'm sharpest before noon", "My manager is …", "I don't take meetings on Fridays", "Keep my emails short and warm", "My kids are … and …"], id: \.self) { idea in
                        Button(idea) { newFact = idea }
                    }
                }
            } else {
                Section { Button("Forget Everything", role: .destructive) { confirmClear = true } }
            }
        }
        .navigationTitle("What Keel Knows")
        .confirmationDialog("Forget everything Keel has learned about you?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Forget Everything", role: .destructive) { memory.clear() }
        }
    }

    private func add() { memory.add(newFact); newFact = ""; Haptics.success() }

    private func pasteMany() {
        let text = UIPasteboard.general.string ?? ""
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•*")) }
            .filter { $0.count > 2 && !$0.hasSuffix(":") }          // skip blank lines and headings like "Work:"
        for l in lines { memory.add(l) }
        if !lines.isEmpty { Haptics.success() }
    }
}
