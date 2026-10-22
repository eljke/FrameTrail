import Charts
import SwiftUI
import FrameTrailCore

struct LibraryStatistics {
    struct RatingBucket: Identifiable, Equatable {
        var id: Int { rating }
        let rating: Int
        let count: Int
    }

    let titleCount: Int
    let completedTitleCount: Int
    let watchedEpisodeCount: Int
    let reflectionCount: Int
    let movieCount: Int
    let seriesCount: Int
    let ratedReflectionCount: Int
    let averageRating: Double?
    let ratingDistribution: [RatingBucket]

    init(entries: [LibraryEntry]) {
        titleCount = entries.count
        completedTitleCount = entries.filter { $0.progress.finished }.count
        watchedEpisodeCount = entries.reduce(0) { $0 + $1.progress.watchedEpisodeIDs.count }
        movieCount = entries.filter { $0.title.kind == .movie }.count
        seriesCount = entries.filter { $0.title.kind == .series }.count
        let reflections = entries.flatMap { $0.reflections }
        reflectionCount = reflections.count
        let ratings = reflections.compactMap { $0.rating }
        ratedReflectionCount = ratings.count
        averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        let frequencies = Dictionary(grouping: ratings, by: { $0 }).mapValues(\.count)
        ratingDistribution = (1...10).map { RatingBucket(rating: $0, count: frequencies[$0, default: 0]) }
    }
}

struct LibraryStatisticsView: View {
    let entries: [LibraryEntry]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let statistics = LibraryStatistics(entries: entries)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Label("Фильмы: \(statistics.movieCount)", systemImage: "film")
                Label("Сериалы: \(statistics.seriesCount)", systemImage: "tv")
            }
            .font(.caption).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                statisticCard(statistics.titleCount, label: "Историй в библиотеке", symbol: "books.vertical")
                statisticCard(statistics.completedTitleCount, label: "Досмотрено", symbol: "checkmark.seal")
                statisticCard(statistics.watchedEpisodeCount, label: "Просмотрено серий", symbol: "play.rectangle.on.rectangle")
                statisticCard(statistics.reflectionCount, label: "Личных итогов", symbol: "text.book.closed")
            }

            VStack(alignment: .leading, spacing: 12) {
                if let average = statistics.averageRating {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(average, format: .number.precision(.fractionLength(1)))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit().foregroundStyle(Theme.accent)
                        Text("/ 10").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Text("Средняя оценка записей").font(.subheadline.weight(.medium))
                    Text("Записей с оценкой: \(statistics.ratedReflectionCount)")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Chart(statistics.ratingDistribution) { bucket in
                        BarMark(x: .value("Оценка", bucket.rating), y: .value("Записей", bucket.count))
                            .foregroundStyle(Theme.accent.gradient)
                            .cornerRadius(4)
                            .accessibilityLabel("Оценка \(bucket.rating)")
                            .accessibilityValue("Записей: \(bucket.count)")
                    }
                    .chartXAxis { AxisMarks(values: [1, 5, 10]) }
                    .chartYAxis(.hidden)
                    .frame(height: 80)
                    .accessibilityLabel("Распределение оценок личных итогов")
                } else {
                    Label("Твоя история оценок", systemImage: "star")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                    Text("Добавь оценку в личном итоге, и здесь появятся среднее значение и распределение.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityIdentifier("libraryStatistics")
    }

    private func statisticCard(_ count: Int, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
            Text(count, format: .number)
                .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue(count.formatted())
    }
}
