import SwiftUI
import FrameTrailCore

struct TasteStudioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var recommendations: [PersonalRecommendation] = []
    @State private var seen: Set<String> = []
    @State private var page = 1
    @State private var answer: SourceAnswer?
    @State private var citation: AnswerCitation?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var portrait: TastePortrait {
        TastePortrait(samples: library.entries.map { TasteSample(title: $0.title, progress: $0.progress, reviews: $0.reflections) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sparkles.rectangle.stack").font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(L10n.text("Что объединяет любимые истории?")).font(.title2.bold())
                Text(L10n.text("Разбор по твоим оценкам и заметкам. Только на устройстве, с цитатами из записей. Это гипотезы о вкусе, а не выводы о личности.")).font(.subheadline).foregroundStyle(Theme.muted)
                Picker(L10n.text("Режим"), selection: $mode) {
                    Text(L10n.text("Мой вкус")).tag(0)
                    Text(L10n.text("Связи")).tag(1)
                    Text(L10n.text("Что смотреть")).tag(2)
                }.pickerStyle(.segmented)
                if portrait.context.evidence.count < 2 {
                    ContentUnavailableView(L10n.text("Нужно немного впечатлений"), systemImage: "text.bubble", description: Text(L10n.text("Оставь хотя бы два отзыва о просмотренном. Чем конкретнее заметки, тем интереснее разбор.")))
                }
                if busy { HStack { ProgressView(); Button(L10n.text("Остановить")) { stop() } } }
                else {
                    Button { if mode == 2 { recommend() } else { generate() } } label: { Label(mode == 2 ? L10n.text("Ещё варианты") : L10n.text("Разобрать мои впечатления"), systemImage: "sparkles") }
                        .buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(Theme.background)
                        .disabled(portrait.context.evidence.count < 2 || !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable || (mode == 2 && (!model.hasCatalogToken || page > 500)))
                }
                if !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable { Text(model.assistant.availability(localeIdentifier: model.localeIdentifier).message).font(.caption).foregroundStyle(Theme.muted) }
                if mode == 2 {
                    Text(L10n.text("TMDB: от 7/10, минимум 300 голосов для фильмов и 150 для сериалов. Популярность учитывается после отбора. Показанное не повторяется в этой подборке.")).font(.caption).foregroundStyle(Theme.muted)
                    if !model.hasCatalogToken {
                        Button(L10n.text("Подключить TMDB в настройках")) { model.selectedTab = 3 }.buttonStyle(.glass)
                    }
                    ForEach(recommendations) { match in
                        VStack(alignment: .leading, spacing: 14) {
                            NavigationLink(value: match.candidate.title) {
                                HStack(spacing: 14) {
                                    PosterView(title: match.candidate.title, width: 56)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(match.candidate.title.title).font(.headline)
                                        Text("TMDB \(match.candidate.rating, format: .number.precision(.fractionLength(1)))/10 · \(match.candidate.votes)").font(.caption).foregroundStyle(Theme.accent)
                                        Text(L10n.text("Голоса TMDB · не личная оценка")).font(.caption2).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(); Image(systemName: "chevron.right")
                                }
                            }.buttonStyle(.plain)
                            LocalizedSourceText(text: match.explanation.text)
                            ForEach(match.explanation.citations) { item in
                                Button { citation = item } label: { Label("[\(item.number)] " + L10n.text("Почему мне"), systemImage: "quote.bubble") }.buttonStyle(.glass)
                            }
                            Button(L10n.text("Не интересно")) { recommendations.removeAll { $0.id == match.id } }.font(.caption)
                        }.padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                if let error { ErrorNotice(message: error) }
                if let answer {
                    LocalizedSourceText(text: answer.text)
                    ForEach(answer.citations) { item in
                        Button { citation = item } label: { Label("[\(item.number)] " + L10n.text("Моя запись"), systemImage: "quote.bubble") }.buttonStyle(.glass)
                    }
                    ShareLink(item: answer.text) { Label(L10n.text("Поделиться"), systemImage: "square.and.arrow.up") }
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(L10n.text("Кинопочерк")).navigationBarTitleDisplayMode(.inline)
        .task { await model.assistant.refreshAvailability() }
        .onChange(of: mode) { _, _ in stop() }
        .onChange(of: library.entries) { _, _ in resetRecommendations() }
        .onChange(of: library.activeAccountID) { _, _ in resetRecommendations() }
        .onChange(of: model.catalogRevision) { _, _ in resetRecommendations() }
        .onDisappear { stop() }
        .sheet(item: $citation) { CitationDetailView(citation: $0) }
    }

    private func stop() { task?.cancel(); task = nil; busy = false; answer = nil; recommendations = []; error = nil }

    private func resetRecommendations() {
        stop(); seen = []; page = 1
        Task { await model.catalog.clearRecommendationCache() }
    }

    private func recommend() {
        guard !busy, page <= 500 else { return }
        let snapshot = library.entries
        let account = library.activeAccountID
        let packet = portrait.context
        let locale = model.localeIdentifier
        let language = model.catalogLanguage
        let seeds = snapshot.filter { $0.progress.finished && (Reflection.latest(in: $0.reflections)?.rating ?? 0) >= 8 }.sorted { $0.updatedAt > $1.updatedAt }.map(\.title)
        let currentPage = page
        let excluded = seen.union(snapshot.map(\.id))
        busy = true; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let loaded = try await model.catalog.recommendationCandidates(language: language, seeds: seeds, page: currentPage)
                let candidates = RecommendationPool.ranked(loaded, excluding: excluded).filter { candidate in
                    !snapshot.contains { entry in
                        let names = [entry.title.title, entry.title.originalTitle].compactMap { $0 }.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
                        let matches = [candidate.title.title, candidate.title.originalTitle].compactMap { $0 }.contains { names.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))) }
                        return matches && (entry.title.year == nil || candidate.title.year == nil || entry.title.year == candidate.title.year)
                    }
                }
                let result = candidates.isEmpty ? [] : try await model.assistant.recommend(context: packet, candidates: candidates, localeIdentifier: locale)
                try Task.checkCancellation()
                guard account == library.activeAccountID, snapshot == library.entries, locale == model.localeIdentifier else { return }
                recommendations = result
                seen.formUnion(result.map(\.id))
                page += 1
                if result.isEmpty { error = L10n.text("Убедительных совпадений в этой порции нет. Попробуй ещё варианты или добавь впечатления.") }
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }

    private func generate() {
        let packet = portrait.context
        let prompt = mode == 0
            ? "Read these personal viewing notes. Propose two or three tentative patterns in what the viewer enjoys or dislikes. Explain with concrete examples from supplied reviews. Avoid personality judgments, plot details and claims about films absent from these notes. Say when notes are too sparse."
            : "Find a surprising thematic connection or tension between the viewer's opinions about different titles. Compare specific notes or a score with its review text. Present it as a question or hypothesis, not a fact about personality. Do not invent preferences or story events. If no meaningful connection is supported, say so."
        let locale = model.localeIdentifier
        busy = true; answer = nil; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let result = try await model.assistant.respond(question: prompt, context: packet, history: [], localeIdentifier: locale, preparedQuestion: prompt)
                try Task.checkCancellation()
                answer = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
