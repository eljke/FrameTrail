import SwiftUI

struct RatingSelector: View {
    @Binding var rating: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: rating == 0 ? "star" : "star.fill").foregroundStyle(Theme.accent)
                Text(rating == 0 ? "Твоя оценка" : "\(rating)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                if rating > 0 { Text("/ 10").foregroundStyle(.secondary) }
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { value in
                    Button { rating = value } label: {
                        Text(String(value)).font(.headline).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(rating == value ? Theme.background : Color.primary)
                            .background(rating == value ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(rating == value ? 1 : 0.25)))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Оценка \(value) из 10")
                        .accessibilityAddTraits(rating == value ? .isSelected : [])
                        .accessibilityIdentifier("rating-\(value)")
                }
            }
            Button("Без оценки") { rating = 0 }.font(.caption).disabled(rating == 0)
        }.padding(.vertical, 8)
    }
}
