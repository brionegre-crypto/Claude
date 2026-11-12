import SwiftUI

/// Bolds the first part of every word so the eye can skim; many people with ADHD and dyslexia find it easier to stay on track.
enum Bionic {
    static func attributed(_ text: String, size: CGFloat) -> AttributedString {
        var out = AttributedString()
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let n = word.count <= 3 ? 1 : Int((Double(word.count) * 0.45).rounded(.up))
            var head = AttributedString(String(word.prefix(n)))
            head.font = .system(size: size, weight: .bold)
            var tail = AttributedString(String(word.dropFirst(n)))
            tail.font = .system(size: size, weight: .regular)
            out += head + tail
            word = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber { word.append(ch) }
            else {
                flush()
                var sep = AttributedString(String(ch))
                sep.font = .system(size: size)
                out += sep
            }
        }
        flush()
        return out
    }
}

/// Reading mode: comfortable text size, line spacing and optional bionic emphasis.
struct ReadingModeText: View {
    let text: String
    @AppStorage("reading.bionic") private var bionic = true
    @AppStorage("reading.size") private var size = 18.0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Toggle(isOn: $bionic) { Label("Bold word starts", systemImage: "bold") }.toggleStyle(.button)
                Spacer()
                Button { size = max(14, size - 2) } label: { Image(systemName: "textformat.size.smaller") }
                Button { size = min(30, size + 2) } label: { Image(systemName: "textformat.size.larger") }
            }
            .font(DS.Font.caption).buttonStyle(.bordered)
            Group {
                if bionic { Text(Bionic.attributed(text, size: size)) } else { Text(text).font(.system(size: size)) }
            }
            .lineSpacing(size * 0.45)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
