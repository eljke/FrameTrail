import SwiftUI
import FrameTrailCore

struct CitationDetailView: View {
    let citation: AnswerCitation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(citation.label.isEmpty ? "Добавленный текст" : citation.label, systemImage: "doc.text")
                        .font(.headline).foregroundStyle(Theme.accent)
                    Text(citation.quote).textSelection(.enabled)
                    Text("Фрагмент сохранён вместе с ответом на языке оригинала.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let url = citation.sourceURL { Link("Открыть оригинал", destination: url).buttonStyle(.bordered) }
                }.padding(24)
            }
            .background(Theme.background)
            .navigationTitle("Источник \(citation.number)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
