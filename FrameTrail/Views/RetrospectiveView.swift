import SwiftUI
import Charts
import FrameTrailCore

struct RetrospectiveView: View {
    let title: MediaTitle
    var throughEpisodeID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var selectedSeason = -1
    @State private var result = ""
    @State private var error: String?
    @State private var busy = false
    @State private var completed = 0
    @State private var total = 1
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var resultEpisodeCount = 0

    private var entry: LibraryEntry? { library.entry(for: title.id) }
    private var selectedRecords: [Reflection] {
        let records: [Reflection]
        if let throughEpisodeID, let entry {
            records = StoryCheckpoint(title: title, episodes: entry.episodes, progress: entry.progress, facts: [], records: entry.reflections, through: throughEpisodeID).reviews
        } else { records = entry?.reflections ?? [] }
        return selectedSeason < 0 ? records : records.filter { $0.episodeSeason == selectedSeason }
    }
    private var compilation: ReflectionCompilation {
        ReflectionCompilation(records: selectedRecords, watchedEpisodeIDs: entry?.progress.watchedEpisodeIDs ?? [])
    }
    private var ratedEpisodes: [Reflection] {
        let watched = entry?.progress.watchedEpisodeIDs ?? []
        let eligible = selectedRecords.filter { $0.episodeID.map(watched.contains) == true }
        return Dictionary(grouping: eligible, by: { $0.episodeID! }).values.compactMap {
            Reflection.latest(in: $0, episodeID: $0[0].episodeID)
        }.filter { $0.rating != nil }.sorted {
            ($0.episodeSeason ?? 0, $0.episodeNumber ?? 0) < ($1.episodeSeason ?? 0, $1.episodeNumber ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.title).font(.title3.bold())
                    Picker(L10n.text("Сезон"), selection: $selectedSeason) {
                        Text(L10n.text("Все сезоны")).tag(-1)
                        ForEach(Array(Set((entry?.reflections ?? []).compactMap(\.episodeSeason))).sorted(), id: \.self) { season in
                            Text(L10n.text("Сезон %@", String(season))).tag(season)
                        }
                    }.accessibilityIdentifier("retrospectiveSeason")
                    Label(L10n.text("Впечатления о сериях: %@", String(describing: compilation.episodeCount)), systemImage: "square.stack.3d.up")
                    Text(L10n.text("Помощник соберёт общую картину по твоим оценкам и заметкам: что работало, что мешало и как менялось впечатление. Это воспоминание о твоём опыте, а не пересказ неподтверждённых событий."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if compilation.shortened {
                        Text(L10n.text("Длинные записи сокращаются для обработки: до 180 символов каждого поля на серию. Полные оригиналы остаются в дневнике."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !ratedEpisodes.isEmpty { seasonRatings }
                Section {
                    Button(result.isEmpty ? L10n.text("Собрать общую картину") : L10n.text("Собрать заново")) { start() }
                        .disabled(busy || compilation.episodeCount == 0 || !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable)
                    if busy {
                        ProgressView(value: Double(completed), total: Double(total))
                        Text(L10n.text("Локальная обработка: %@ из %@ этапов. Для длинного сериала потребуется больше времени.", String(describing: completed), String(describing: total))).font(.caption)
                        Button(L10n.text("Остановить"), role: .cancel) { stop() }
                    }
                    if !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable {
                        Text(model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if compilation.episodeCount == 0 {
                        Text(L10n.text("Сначала оцени просмотренные серии или сохрани о них впечатления через меню серии. Ответы на вопросы необязательны.")).font(.footnote)
                    }
                } header: { Text(L10n.text("Apple Intelligence · на iPhone")) }
                if !result.isEmpty {
                    Section(L10n.text("Сводка — можно отредактировать")) {
                        TextEditor(text: $result).frame(minHeight: 240)
                            .disabled(busy)
                            .onChange(of: result) { _, text in if text.count > 10_000 { result = String(text.prefix(10_000)) } }
                        ShareLink(item: title.title + "\n\n" + result) { Label(L10n.text("Поделиться сводкой"), systemImage: "square.and.arrow.up") }
                        Text(L10n.text("Сохрани сводку в дневник, чтобы вернуться к ней позже. При входе в аккаунт она синхронизируется как личный итог."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Мой сезон"))
            .scrollContentBackground(.hidden).background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Закрыть")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Сохранить")) { save() }.disabled(busy || result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await model.assistant.refreshAvailability() }
            .onChange(of: selectedSeason) { _, _ in stop(); result = "" }
            .onChange(of: entry?.reflections) { _, _ in stop(); result = "" }
            .onChange(of: entry?.progress) { _, _ in stop(); result = "" }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onChange(of: model.answerLocaleIdentifier) { _, _ in stop() }
            .onDisappear { stop() }
        }
    }

    private var seasonRatings: some View {
        Section {
            let reviews = ratedEpisodes
            let average = Double(reviews.compactMap(\.rating).reduce(0, +)) / Double(reviews.count)
            HStack {
                Text(L10n.text("Средняя оценка серий"))
                Spacer()
                Text("\(average, format: .number.precision(.fractionLength(1)))/10").font(.title3.bold()).foregroundStyle(Theme.accent)
            }
            Chart(Array(reviews.enumerated()), id: \.element.id) { index, review in
                BarMark(x: .value(L10n.text("Серия"), index), y: .value(L10n.text("Оценка"), review.rating!))
                    .foregroundStyle(Theme.accent.gradient).cornerRadius(3)
                    .accessibilityLabel("S\(review.episodeSeason ?? 0) E\(review.episodeNumber ?? 0)")
                    .accessibilityValue("\(review.rating!)/10")
            }.chartYScale(domain: 0...10).chartXAxis(.hidden).frame(height: 130)
            if let best = reviews.max(by: { $0.rating! < $1.rating! }) {
                Label(L10n.text("Любимый эпизод по оценке"), systemImage: "star.fill").font(.caption).foregroundStyle(.secondary)
                Text("S\(best.episodeSeason ?? 0) E\(best.episodeNumber ?? 0) · \(best.rating!)/10").font(.headline)
                if !best.summary.isEmpty { Text(best.summary).font(.subheadline).lineLimit(4) }
            }
            Text(L10n.text("Оценки только просмотренных серий. Отсутствие оценки не считается нулём.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func start() {
        guard !busy, let snapshot = entry else { return }
        let accountID = library.activeAccountID
        let locale = model.answerLocaleIdentifier
        let plan = compilation
        let id = UUID()
        generationID = id
        busy = true
        completed = 0
        total = 1
        error = nil
        generationTask = Task {
            defer { if generationID == id { busy = false; generationID = nil; generationTask = nil } }
            do {
                let text = try await model.assistant.compileReflections(title: title.title, compilation: plan, localeIdentifier: locale, aliases: snapshot.nameAliases ?? []) { done, count in
                    if generationID == id { completed = done; total = count }
                }
                try Task.checkCancellation()
                guard generationID == id, library.activeAccountID == accountID,
                      entry?.progress == snapshot.progress, entry?.nameAliases == snapshot.nameAliases, model.answerLocaleIdentifier == locale else { return }
                guard entry?.reflections == snapshot.reflections else {
                    error = L10n.text("За время обработки записи изменились. Запусти сборку сводки ещё раз.")
                    return
                }
                result = text
                resultEpisodeCount = plan.episodeCount
            } catch is CancellationError {} catch {
                if generationID == id { self.error = L10n.error(error) }
            }
        }
    }

    private func stop() {
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        busy = false
    }

    private func save() {
        guard var entry else { return }
        let header = L10n.text("Сводка впечатлений · серий: %@", String(describing: resultEpisodeCount))
        let season: Int? = selectedSeason < 0 ? nil : selectedSeason
        let rating = Reflection.latest(in: entry.reflections, seasonNumber: season)?.rating
        entry.reflections.append(Reflection(titleID: title.id, summary: header + "\n\n" + result, rating: rating, seasonNumber: season))
        library.update(entry)
        if let failure = library.lastError { error = failure }
        else { InteractionFeedback.success(); dismiss() }
    }
}
