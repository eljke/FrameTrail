import SwiftUI
import FrameTrailCore
import TipKit

struct TitleDetailView: View {
    let title: MediaTitle
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var episodes: [Episode] = []
    @State private var loading = false
    @State private var episodeLoadID: UUID?
    @State private var loadingPlot = false
    @State private var error: String?
    @State private var sourceImport = false
    @State private var reflectionEditor = false
    @State private var editingReflection: Reflection?
    @State private var plotInfo: String?
    @State private var selectedSeason = 1
    @State private var pendingReflectionRemoval: Reflection?
    @State private var episodeToReview: Episode?
    @State private var showRetrospective = false
    @State private var reviewingSeason = false
    @State private var episodeDetails: Episode?

    private var entry: LibraryEntry { library.entry(for: title.id) ?? LibraryEntry(title: title) }
    private var isSaved: Bool { library.entry(for: title.id) != nil }
    private var availableEpisodes: [Episode] { mergeEpisodes(entry.episodes + episodes) }
    private var displayedTitle: MediaTitle { model.displayTitle(title) }
    private var seasons: [Int] { Set(availableEpisodes.map(\.season)).sorted() }
    private var overallReview: Reflection? { Reflection.latest(in: entry.reflections) }
    private var canReview: Bool { entry.progress.finished || (title.kind == .series && !entry.progress.watchedEpisodeIDs.isEmpty) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    PosterView(title: title, width: 82)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title.kind == .movie ? L10n.text("ФИЛЬМ") : L10n.text("СЕРИАЛ")).font(.caption2.weight(.medium)).foregroundStyle(Theme.accent)
                        Text(displayedTitle.title).font(.title2.bold()).textSelection(.enabled)
                        if let original = displayedTitle.originalTitle, original != displayedTitle.title {
                            Text(original).font(.caption).foregroundStyle(Theme.muted)
                        }
                        if let year = title.year { Text(String(year)).font(.subheadline).foregroundStyle(Theme.muted) }
                        if let rating = overallReview?.rating { Label(L10n.text("Моя оценка: %@/10", String(describing: rating)), systemImage: "star.fill").font(.caption).foregroundStyle(Theme.accent) }
                        if !isSaved {
                            Button { save(entry) } label: { Label(L10n.text("В библиотеку"), systemImage: "plus") }
                                .buttonStyle(.bordered)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let error { ErrorNotice(message: error) }
                if let undo = library.ratingUndo, undo.titleID == title.id && undo.accountID == library.activeAccountID {
                    HStack {
                        Text(L10n.text("Изменено оценок серий: %@", String(describing: undo.count))).font(.caption)
                        Spacer()
                        Button(L10n.text("Отменить")) { library.undoEpisodeRatings(for: title.id) }
                            .accessibilityIdentifier("undoEpisodeRatings")
                    }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                if !displayedTitle.overview.isEmpty {
                    DisclosureGroup(L10n.text("Описание от источника")) {
                        LocalizedSourceText(text: displayedTitle.overview).font(.subheadline).padding(.top, 8)
                    }.font(.subheadline).tint(Theme.muted)
                }
                if canReview {
                    if entry.reflections.isEmpty && !model.isUITesting { TipView(FirstReviewTip()) }
                    Button {
                        if !model.isUITesting { FirstReviewTip().invalidate(reason: .actionPerformed) }
                        editingReflection = overallReview
                        reflectionEditor = true
                    } label: {
                        Label(overallReview?.rating == nil ? L10n.text("Оценить и написать отзыв") : L10n.text("Моя оценка и отзыв"), systemImage: "star")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).accessibilityIdentifier("rateTitle")
                }
                if title.kind == .movie {
                    Toggle(L10n.text("Я досмотрел фильм"), isOn: Binding(get: { entry.progress.finished }, set: { value in
                        var changed = entry
                        changed.progress.finished = value
                        changed.chat = []
                        save(changed)
                        if library.lastError == nil { InteractionFeedback.selection() }
                    }))
                    .tint(Theme.accent).accessibilityIdentifier("finishedToggle")
                    if entry.progress.finished {
                        Button { Task { await loadPlot() } } label: {
                            HStack { if loadingPlot { ProgressView() }; Label(L10n.text("Загрузить сюжет из Wikipedia"), systemImage: "text.magnifyingglass") }
                        }.buttonStyle(.bordered).disabled(loadingPlot)
                        Text(L10n.text("Перед обсуждением проверь, что источник соответствует фильму: у одноимённых произведений возможны совпадения."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    episodeSection
                }
                if let plotInfo { Text(plotInfo).font(.footnote).foregroundStyle(Theme.muted) }
                if title.kind == .series && canReview {
                    if !model.isUITesting && Set(entry.reflections.compactMap(\.episodeID)).intersection(entry.progress.watchedEpisodeIDs).count >= 2 {
                        TipView(SeriesRetrospectiveTip())
                    }
                    Button {
                        if !model.isUITesting { SeriesRetrospectiveTip().invalidate(reason: .actionPerformed) }
                        showRetrospective = true
                    } label: {
                        Label(L10n.text("Итог по сериям"), systemImage: "sparkles.rectangle.stack")
                    }.buttonStyle(.bordered).accessibilityIdentifier("compileSeriesImpressions")
                    Text(L10n.text("Собрать заметки о сериях в один отзыв.")).font(.caption).foregroundStyle(Theme.muted)
                }
                NavigationLink {
                    DiscussionView(title: title, initialEpisodes: availableEpisodes)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.text.bubble.right").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.progress.finished ? L10n.text("Обсудить финал") : L10n.text("Обсудить просмотренное")).font(.headline)
                            Text(L10n.text("Задать вопрос о просмотренном")).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("openDiscussion")
                DisclosureGroup(L10n.text("Источники")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Добавлено материалов: %@", String(describing: entry.facts.count))).font(.caption).foregroundStyle(Theme.muted)
                        Button { sourceImport = true } label: { Label(L10n.text("Добавить текст или субтитры"), systemImage: "doc.badge.plus") }
                            .accessibilityIdentifier("importSource")
                        if let source = title.sourceURL { Link(L10n.text("Открыть страницу произведения"), destination: source).font(.footnote) }
                    }.padding(.top, 10)
                }.accessibilityIdentifier("sourcesDisclosure")
                if let recent = entry.reflections.filter({ !$0.summary.isEmpty || !$0.allLiked.isEmpty || !$0.allDisliked.isEmpty }).sorted(by: { $0.createdAt > $1.createdAt }).first {
                    reflectionCard(recent)
                }
                if !entry.reflections.isEmpty {
                    Button(L10n.text("Все отзывы в дневнике")) { model.selectedTab = 2 }.font(.subheadline)
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(displayedTitle.title).navigationBarTitleDisplayMode(.inline)
        .task(id: library.activeAccountID + model.catalogRevision.uuidString) {
            await model.localizeTitle(title)
            await loadEpisodes()
        }
        .onChange(of: library.entry(for: title.id)?.episodes) { _, stored in episodes = stored ?? [] }
        .onChange(of: seasons, initial: true) { _, values in
            if !values.contains(selectedSeason), let first = values.first { selectedSeason = first }
        }
        .sheet(isPresented: $sourceImport) { SourceImportView(title: title, episodes: availableEpisodes) }
        .sheet(isPresented: $reflectionEditor) { ReflectionEditorView(title: title, reflection: editingReflection) }
        .sheet(item: $episodeToReview) { episode in
            ReflectionEditorView(title: title, reflection: Reflection.latest(in: entry.reflections, episodeID: episode.id), episode: episode)
        }
        .sheet(item: $episodeDetails) { episode in
            NavigationStack {
                ScrollView { VStack(alignment: .leading, spacing: 16) {
                    Text(episode.name).font(.title2.bold())
                    LocalizedSourceText(text: episode.summary)
                }.padding(24) }.navigationTitle("S\(episode.season) E\(episode.number)")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Готово")) { episodeDetails = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRetrospective) { RetrospectiveView(title: title) }
        .sheet(isPresented: $reviewingSeason) {
            ReflectionEditorView(title: title, reflection: Reflection.latest(in: entry.reflections, seasonNumber: selectedSeason), season: selectedSeason)
        }
        .confirmationDialog(L10n.text("Удалить отзыв? После синхронизации он исчезнет и на других устройствах."), isPresented: Binding(get: { pendingReflectionRemoval != nil }, set: { if !$0 { pendingReflectionRemoval = nil } }), titleVisibility: .visible) {
            Button(L10n.text("Удалить отзыв"), role: .destructive) {
                if let reflection = pendingReflectionRemoval {
                    var changed = entry
                    changed.reflections.removeAll { $0.id == reflection.id }
                    save(changed)
                }
                pendingReflectionRemoval = nil
            }
        }
    }

    @ViewBuilder private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Серии")).font(.title3.bold())
            if loading { ProgressView(L10n.text("Загружаем серии…")) }
            if availableEpisodes.isEmpty && !loading {
                InfoCard(symbol: "rectangle.stack", title: L10n.text("Список серий пока недоступен"), text: L10n.text("Можно добавить своё описание серии вместе с материалами. Поиск по оригинальному названию и подключение TMDB расширяют покрытие."))
            }
            if seasons.count > 1 {
                Picker(L10n.text("Сезон"), selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { season in Text(season == 0 ? L10n.text("Спецвыпуски") : L10n.text("Сезон %@", String(describing: season))).tag(season) }
                }.pickerStyle(.menu)
            }
            let seasonEpisodes = availableEpisodes.filter { $0.season == selectedSeason }
            let seasonWatched = seasonEpisodes.filter { entry.progress.watchedEpisodeIDs.contains($0.id) }.count
            ProgressView(value: Double(seasonWatched), total: Double(max(1, seasonEpisodes.count))) {
                Text(L10n.text("Просмотрено %@ из %@", String(describing: seasonWatched), String(describing: seasonEpisodes.count))).font(.caption).foregroundStyle(Theme.muted)
            }.tint(Theme.accent)
            if let next = seasonEpisodes.first(where: { !entry.progress.watchedEpisodeIDs.contains($0.id) }) {
                Button {
                    var changed = entry
                    changed.progress.watchedEpisodeIDs.insert(next.id)
                    save(changed)
                    if library.lastError == nil { InteractionFeedback.selection() }
                } label: {
                    Label(L10n.text("Посмотрел S%@ E%@", String(describing: next.season), String(describing: next.number)), systemImage: "checkmark.circle")
                }.buttonStyle(.bordered).accessibilityIdentifier("watchNextEpisode")
            }
            HStack {
                Button { reviewingSeason = true } label: { Label(L10n.text("Оценить сезон"), systemImage: "star") }
                    .disabled(!availableEpisodes.contains { $0.season == selectedSeason && entry.progress.watchedEpisodeIDs.contains($0.id) })
                    .accessibilityIdentifier("rateSeason")
                Spacer()
                if let rating = Reflection.latest(in: entry.reflections, seasonNumber: selectedSeason)?.rating {
                    Text("★ \(rating)/10").foregroundStyle(Theme.accent)
                }
            }.font(.subheadline)
            ForEach(availableEpisodes.filter { $0.season == selectedSeason }) { episode in
                let watched = entry.progress.watchedEpisodeIDs.contains(episode.id)
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        var changed = entry
                        if watched { changed.progress.watchedEpisodeIDs.remove(episode.id); changed.progress.finished = false; changed.chat = [] }
                        else { changed.progress.watchedEpisodeIDs.insert(episode.id) }
                        save(changed)
                        if library.lastError == nil { InteractionFeedback.selection() }
                    } label: { Image(systemName: watched ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle()).foregroundStyle(watched ? Theme.accent : Theme.muted) }
                    .accessibilityLabel(L10n.text("%@: сезон %@, серия %@", String(describing: watched ? L10n.text("Снять просмотр") : L10n.text("Просмотрено")), String(describing: episode.season), String(describing: episode.number)))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("S\(episode.season) · E\(episode.number)").font(.caption.bold()).foregroundStyle(Theme.accent)
                        Text(watched ? episode.name : L10n.text("Серия %@", String(describing: episode.number))).font(.subheadline)
                        if watched, let rating = Reflection.latest(in: entry.reflections, episodeID: episode.id)?.rating {
                            Label("\(rating)/10", systemImage: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                        }
                        if watched && !episode.summary.isEmpty {
                            Button(L10n.text("Описание серии")) { episodeDetails = episode }.font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button(L10n.text("Просмотрено всё до этой серии")) { markThrough(episode) }
                        Button(L10n.text("Оценить серию и впечатления")) {
                            if !model.isUITesting { FirstReviewTip().invalidate(reason: .actionPerformed) }
                            episodeToReview = episode
                        }.disabled(!watched)
                        Button(L10n.text("Загрузить подробный сюжет серии")) { Task { await loadEpisodePlot(episode) } }.disabled(!watched || loadingPlot)
                    } label: { Image(systemName: "ellipsis").padding(6).foregroundStyle(Theme.muted) }.accessibilityLabel(L10n.text("Действия с серией"))
                }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            Toggle(L10n.text("Я досмотрел сериал"), isOn: Binding(get: { entry.progress.finished }, set: { value in
                var changed = entry
                changed.progress.finished = value
                if value { changed.progress.watchedEpisodeIDs.formUnion(availableEpisodes.map(\.id)) }
                changed.chat = []
                save(changed)
                if library.lastError == nil { InteractionFeedback.selection() }
            })).tint(Theme.accent)
        }
    }

    private func save(_ value: LibraryEntry) {
        var changed = value
        changed.episodes = mergeEpisodes(value.episodes + episodes)
        changed.updatedAt = Date()
        library.update(changed)
        if library.lastError == nil { episodes = changed.episodes }
    }

    private func loadEpisodes() async {
        episodes = entry.episodes
        guard title.kind == .series, title.provider != "local", !model.isUITesting else { return }
        guard episodes.isEmpty || entry.episodeLanguage != model.catalogLanguage else { return }
        let requestID = UUID()
        episodeLoadID = requestID
        loading = true
        defer { if episodeLoadID == requestID { loading = false } }
        let accountID = library.activeAccountID
        do {
            let loaded = try await model.catalog.fetchEpisodes(for: title, language: model.catalogLanguage)
            guard accountID == library.activeAccountID, episodeLoadID == requestID else { return }
            episodes = mergeEpisodes(entry.episodes + loaded)
            if isSaved {
                var changed = entry
                changed.episodeLanguage = model.catalogLanguage
                save(changed)
            }
        } catch is CancellationError {} catch {
            if accountID == library.activeAccountID, episodeLoadID == requestID { self.error = error.localizedDescription }
        }
    }

    private func markThrough(_ episode: Episode) {
        var changed = entry
        changed.progress.watchedEpisodeIDs.formUnion(availableEpisodes.filter { $0.season < episode.season || ($0.season == episode.season && $0.number <= episode.number) }.map(\.id))
        save(changed)
        if library.lastError == nil { InteractionFeedback.selection() }
    }

    private func loadEpisodePlot(_ episode: Episode) async {
        loadingPlot = true
        error = nil
        defer { loadingPlot = false }
        let accountID = library.activeAccountID
        do {
            let facts = try await model.plots.plot(for: title, episode: episode, progress: entry.progress)
            try Task.checkCancellation()
            guard accountID == library.activeAccountID, entry.progress.watchedEpisodeIDs.contains(episode.id) else { return }
            var changed = entry
            changed.facts.removeAll { $0.kind == "plot" && $0.episodeID == episode.id }
            changed.facts.append(contentsOf: facts)
            save(changed)
            plotInfo = L10n.text("Загружен сюжет S%@ E%@. Он доступен для обсуждения и вариантов впечатлений.", String(describing: episode.season), String(describing: episode.number))
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func loadPlot() async {
        loadingPlot = true
        error = nil
        defer { loadingPlot = false }
        let accountID = library.activeAccountID
        do {
            let facts = try await model.plots.plot(for: title, finished: entry.progress.finished)
            guard accountID == library.activeAccountID, entry.progress.finished else { return }
            var changed = entry
            changed.facts.removeAll { $0.id.hasPrefix("wikipedia:") }
            changed.facts.append(contentsOf: facts)
            save(changed)
            plotInfo = L10n.text("Сюжет загружен. Источники можно открыть в обсуждении.")
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func mergeEpisodes(_ values: [Episode]) -> [Episode] {
        var byID: [String: Episode] = [:]
        for episode in values { byID[episode.id] = episode }
        return byID.values.sorted {
            if $0.season != $1.season { return $0.season < $1.season }
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id < $1.id
        }
    }

    private func shareText(_ reflection: Reflection) -> String {
        var lines = [title.title, reflection.summary]
        if let season = reflection.episodeSeason, let number = reflection.episodeNumber { lines.insert("S\(season) E\(number)", at: 1) }
        if let rating = reflection.rating { lines.append("★ \(rating)/10") }
        lines.append(contentsOf: reflection.allLiked.map { "+ " + $0 })
        lines.append(contentsOf: reflection.allDisliked.map { "− " + $0 })
        lines.append(contentsOf: reflection.questions.map { "? " + $0 })
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func reflectionCard(_ reflection: Reflection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("Мой отзыв")).font(.headline)
                Spacer()
                if let rating = reflection.rating { Text("★ \(rating)/10").foregroundStyle(Theme.accent) }
                Button { editingReflection = reflection; reflectionEditor = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel(L10n.text("Изменить отзыв"))
                Menu {
                    ShareLink(item: shareText(reflection)) { Label(L10n.text("Поделиться отзывом"), systemImage: "square.and.arrow.up") }
                    Button(L10n.text("Удалить отзыв"), role: .destructive) { pendingReflectionRemoval = reflection }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel(L10n.text("Действия с итогом"))
            }
            if let season = reflection.episodeSeason, let number = reflection.episodeNumber {
                Text(L10n.text("Сезон %@ · Серия %@", String(describing: season), String(describing: number))).font(.caption).foregroundStyle(Theme.accent)
            } else if let season = reflection.seasonNumber {
                Text(L10n.text("Сезон %@", String(describing: season))).font(.caption).foregroundStyle(Theme.accent)
            }
            if !reflection.summary.isEmpty { Text(reflection.summary).font(.subheadline).lineLimit(4).textSelection(.enabled) }
            ForEach(Array(reflection.allLiked.enumerated()), id: \.offset) { item in Text("+ " + item.element).font(.caption).foregroundStyle(Theme.muted) }
            ForEach(Array(reflection.allDisliked.enumerated()), id: \.offset) { item in Text("− " + item.element).font(.caption).foregroundStyle(Theme.muted) }
            ForEach(Array(reflection.questions.enumerated()), id: \.offset) { item in Text("? " + item.element).font(.caption).foregroundStyle(Theme.muted) }
            Text(reflection.createdAt, style: .date).font(.caption2).foregroundStyle(Theme.muted)
        }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
