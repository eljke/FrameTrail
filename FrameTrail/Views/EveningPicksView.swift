import SwiftUI
import FrameTrailCore

struct EveningPicksView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @State private var request = ""
    @State private var kind = 0
    @State private var minutes = 0
    @State private var watchlistOnly = false
    @State private var picks: [PersonalRecommendation] = []
    @State private var seen: Set<String> = []
    @State private var page = 1
    @State private var activeBrief: RecommendationBrief?
    @State private var busy = false
    @State private var stage = ""
    @State private var error: String?
    @State private var citation: AnswerCitation?
    @State private var task: Task<Void, Never>?
    @State private var lastHidden: MediaTitle?

    private var selectedKind: MediaKind? { kind == 1 ? .movie : kind == 2 ? .series : nil }
    private var enabled: Bool { model.hasCatalogToken && model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                controls
                if let activeBrief { briefSummary(activeBrief) }
                if busy {
                    HStack { ProgressView(); Text(stage).font(.subheadline); Spacer(); Button(L10n.text("Остановить")) { stop() } }
                } else {
                    Button(picks.isEmpty && page == 1 ? L10n.text("Подобрать на вечер") : L10n.text("Ещё варианты"), systemImage: "sparkles") { load() }
                        .buttonStyle(.glassProminent).tint(Theme.accent).disabled(!enabled || page > 500)
                        .accessibilityIdentifier("moreEveningPicks")
                }
                if let lastHidden {
                    HStack {
                        Text(L10n.text("Больше не предлагаю: %@", lastHidden.title)).font(.caption)
                        Spacer()
                        Button(L10n.text("Отменить")) { library.restoreRecommendation(lastHidden.id); self.lastHidden = nil }
                    }
                }
                if let error { ErrorNotice(message: error) }
                if !enabled { setupNotice }
                ForEach(picks) { pick in pickCard(pick) }
                if !picks.isEmpty && !busy {
                    Button(L10n.text("Ещё варианты"), systemImage: "arrow.clockwise") { load() }.buttonStyle(.glass).disabled(page > 500)
                }
                Text(L10n.text("Рейтинг и число голосов проверяются отдельно от совпадения со вкусом. Чувствительные темы нельзя надёжно исключить по короткому описанию — проверь карточку перед просмотром."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(L10n.text("На вечер")).navigationBarTitleDisplayMode(.inline)
        .task { await model.assistant.refreshAvailability() }
        .onChange(of: request) { _, value in if value.count > 1200 { request = String(value.prefix(1200)) }; edited() }
        .onChange(of: kind) { _, _ in edited() }
        .onChange(of: minutes) { _, _ in edited() }
        .onChange(of: watchlistOnly) { _, _ in edited() }
        .onChange(of: library.entries) { old, new in
            stop()
            if old.filter({ $0.recommendationHidden != true }) != new.filter({ $0.recommendationHidden != true }) { edited() }
            picks.removeAll { pick in new.contains { $0.id == pick.id } }
        }
        .onChange(of: library.activeAccountID) { _, _ in edited(); seen = []; lastHidden = nil }
        .onChange(of: model.catalogRevision) { _, _ in edited(); seen = [] }
        .onChange(of: model.answerLocaleIdentifier) { _, _ in edited() }
        .onDisappear { stop() }
        .sheet(item: $citation) { CitationDetailView(citation: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "moon.stars").font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(L10n.text("Что хочется сегодня?")).font(.title.bold())
            Text(L10n.text("Опиши настроение, вспомни любимый фильм или выбери из отложенного. Можно уточнять запрос и просить ещё."))
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(L10n.text("Например: напряжённое, до двух часов, без фантастики"), text: $request, axis: .vertical)
                .lineLimit(3...5).padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("eveningRequest")
            Picker(L10n.text("Тип"), selection: $kind) {
                Text(L10n.text("Любой")).tag(0); Text(L10n.text("Фильм")).tag(1); Text(L10n.text("Сериал")).tag(2)
            }.pickerStyle(.segmented)
            HStack {
                Picker(L10n.text("Длительность"), selection: $minutes) {
                    Text(L10n.text("Без лимита")).tag(0)
                    ForEach([60, 90, 120, 180], id: \.self) { Text(L10n.text("До %@ мин", String($0))).tag($0) }
                }
                Spacer()
                Toggle(L10n.text("Из моих планов"), isOn: $watchlistOnly).toggleStyle(.button).font(.caption)
            }
            if !picks.isEmpty {
                HStack {
                    Button(L10n.text("Полегче")) { request += "\n" + L10n.text("Полегче") }
                    Button(L10n.text("Менее известное")) { request += "\n" + L10n.text("Менее известное") }
                }.buttonStyle(.glass).font(.caption)
            }
        }
    }

    private func briefSummary(_ brief: RecommendationBrief) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
            Text(brief.kind == .movie ? L10n.text("Фильм") : brief.kind == .series ? L10n.text("Сериал") : L10n.text("Любой"))
            if let max = brief.maximumMinutes { Text(L10n.text("До %@ мин", String(max))) }
        }.font(.caption).foregroundStyle(Theme.accent)
    }

    private var setupNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.hasCatalogToken { Text(L10n.text("Для подбора нужен ключ TMDB в настройках.")) }
            let status = model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier)
            if !status.isAvailable { Text(status.message) }
            Button(L10n.text("Настройки")) { model.selectedTab = 3 }.buttonStyle(.glass)
        }.font(.footnote).foregroundStyle(Theme.muted)
    }

    private func pickCard(_ pick: PersonalRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: pick.candidate.title) {
                HStack(alignment: .top, spacing: 16) {
                    PosterView(title: pick.candidate.title, width: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pick.candidate.title.title).font(.title3.bold())
                        Text(pick.candidate.title.kind == .movie ? L10n.text("Фильм") : L10n.text("Сериал")).font(.caption).foregroundStyle(Theme.muted)
                        Text("TMDB \(pick.candidate.rating, format: .number.precision(.fractionLength(1)))/10 · \(pick.candidate.votes)").font(.caption).foregroundStyle(Theme.accent)
                        if let runtime = pick.candidate.runtimeMinutes { Text(L10n.text("%@ мин", String(runtime))).font(.caption) }
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
            LocalizedSourceText(text: pick.explanation.text)
            ForEach(pick.explanation.citations) { item in
                Button { citation = item } label: { Label(L10n.text("Основание подбора"), systemImage: "quote.bubble") }.font(.caption)
            }
            HStack {
                Button(L10n.text("В планы"), systemImage: "plus") { library.add(pick.candidate.title); InteractionFeedback.success() }.buttonStyle(.glass)
                Spacer()
                Button(L10n.text("Не интересно")) {
                    library.hideRecommendation(pick.candidate.title)
                    if library.lastError == nil { lastHidden = pick.candidate.title; picks.removeAll { $0.id == pick.id }; InteractionFeedback.selection() }
                }.font(.caption)
            }
        }.padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 26))
    }

    private func stop() { task?.cancel(); task = nil; busy = false }
    private func edited() { stop(); activeBrief = nil; page = 1; picks = []; error = nil }

    private func load() {
        guard !busy, page <= 500 else { return }
        let snapshot = library.entries, account = library.activeAccountID, locale = model.answerLocaleIdentifier
        let language = model.catalogLanguage, query = request, currentPage = page, savedOnly = watchlistOnly
        let manual = RecommendationBrief(kind: selectedKind, maximumMinutes: minutes == 0 ? nil : minutes, request: query)
        let prior = activeBrief
        let excluded = seen.union(snapshot.filter { !savedOnly || $0.recommendationHidden == true || $0.progress.finished || !$0.progress.watchedEpisodeIDs.isEmpty }.map(\.id))
        busy = true; error = nil; stage = L10n.text("Уточняю запрос…")
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let brief: RecommendationBrief
                if let prior { brief = prior }
                else { brief = try await model.assistant.interpretBrief(manual) }
                try Task.checkCancellation()
                stage = L10n.text("Проверяю каталог и длительность…")
                let seeds = snapshot.filter { $0.progress.finished && (Reflection.latest(in: $0.reflections)?.rating ?? 0) >= 8 }.map(\.title)
                let loaded: [RecommendationCandidate]
                if savedOnly {
                    let titles = snapshot.filter { $0.recommendationHidden != true && !$0.progress.finished && $0.progress.watchedEpisodeIDs.isEmpty }.map(\.title)
                    loaded = try await model.catalog.savedCandidates(titles: titles, language: language, page: currentPage)
                } else { loaded = try await model.catalog.recommendationCandidates(language: language, seeds: seeds, page: currentPage, brief: brief) }
                let candidates = RecommendationPool.ranked(loaded, excluding: excluded).filter(brief.accepts)
                var packet = TastePortrait(samples: snapshot.filter { $0.recommendationHidden != true }.map { TasteSample(title: $0.title, progress: $0.progress, reviews: $0.reflections) }).context
                let requestFact = StoryFact(id: "viewing-request", text: query.isEmpty ? "No specific request. Choose by supported personal ratings if present, otherwise general catalog quality. Do not claim known preferences without evidence." : "Current viewing request: " + query, kind: "viewer-request")
                packet.evidence.insert(requestFact, at: 0)
                stage = L10n.text("Выбираю и объясняю…")
                let aliases = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0.nameAliases ?? []) })
                let result = candidates.isEmpty ? [] : try await model.assistant.recommend(context: packet, candidates: candidates, localeIdentifier: locale, aliasesByTitle: aliases)
                try Task.checkCancellation()
                guard account == library.activeAccountID, snapshot == library.entries, locale == model.answerLocaleIdentifier else { return }
                activeBrief = brief; picks = result; seen.formUnion(result.map(\.id)); page += 1
                if result.isEmpty { error = L10n.text("В этой порции подходящего не нашлось. Попробуй ещё или измени условия — сами мы их не ослабляем.") }
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
