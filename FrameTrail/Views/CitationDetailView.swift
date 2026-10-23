import SwiftUI
import FrameTrailCore

struct CitationDetailView: View {
    let citation: AnswerCitation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(citation.label.isEmpty ? L10n.text("Добавленный текст") : citation.label, systemImage: "doc.text")
                        .font(.headline).foregroundStyle(Theme.accent)
                    LocalizedSourceText(text: citation.quote)
                    Text(L10n.text("Фрагмент сохранён вместе с ответом на языке оригинала."))
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let url = citation.sourceURL { Link(L10n.text("Открыть оригинал"), destination: url).buttonStyle(.bordered) }
                }.padding(24)
            }
            .background(Theme.background)
            .navigationTitle(L10n.text("Источник %@", String(describing: citation.number))).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Готово")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
