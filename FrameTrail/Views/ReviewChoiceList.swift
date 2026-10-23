import SwiftUI
import FrameTrailCore

struct ReviewChoiceList: View {
    let choices: [ReviewChoice]
    @Binding var selected: [ReviewChoice]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(choices) { choice in
                let checked = selected.contains { $0.id == choice.id }
                Button {
                    if checked { selected.removeAll { $0.id == choice.id } }
                    else if selected.count < 30 { selected.append(choice) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(checked ? Theme.accent : Theme.muted)
                        Text(choice.text).font(.subheadline).multilineTextAlignment(.leading)
                            .foregroundStyle(Color.primary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(Theme.accent.opacity(checked ? 0.12 : 0.025), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(checked ? 0.65 : 0.18)))
                }.buttonStyle(.plain)
                    .accessibilityValue(checked ? "Выбрано" : "Не выбрано")
                    .accessibilityAddTraits(checked ? .isSelected : [])
                    .contextMenu {
                        if let source = choice.sourceURL { Link("Открыть источник", destination: source) }
                        ShareLink(item: choice.sourceQuote) { Label("Оригинал фрагмента", systemImage: "quote.bubble") }
                    }
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selected.map(\.id))
    }
}
