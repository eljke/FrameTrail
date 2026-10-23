import SwiftUI

struct RatingSelector: View {
    @Binding var rating: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(rating == 0 ? L10n.text("Твоя оценка") : "\(rating)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText()).accessibilityIdentifier("ratingValue")
                if rating > 0 { Text("/ 10").foregroundStyle(.secondary) }
                Spacer()
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(1...10, id: \.self) { value in
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.system(size: min(25, geometry.size.width / 10 - 4), weight: .medium))
                            .foregroundStyle(value <= rating ? Theme.accent : Theme.muted.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { select(at: $0.location.x, width: geometry.size.width) })
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        select(at: value.location.x, width: geometry.size.width)
                    }
                })
            }
            .frame(height: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("Моя оценка"))
            .accessibilityValue(rating == 0 ? L10n.text("Без оценки") : L10n.text("%@ из 10", String(describing: rating)))
            .accessibilityIdentifier("starRating")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(10, rating + 1)
                case .decrement: rating = max(0, rating - 1)
                @unknown default: break
                }
            }
            HStack {
                Text(L10n.text("Коснись звезды или проведи пальцем")).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(L10n.text("Без оценки")) { rating = 0 }.font(.caption).frame(minHeight: 44).disabled(rating == 0)
            }
        }
        .padding(.vertical, 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: rating)
        .sensoryFeedback(.selection, trigger: rating)
    }

    private func select(at location: CGFloat, width: CGFloat) {
        rating = min(10, max(1, Int(floor(location / width * 10)) + 1))
    }
}
