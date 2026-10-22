import SwiftUI
import FrameTrailCore

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

    private var entry: LibraryEntry { library.entry(for: title.id) ?? LibraryEntry(title: title) }
    private var isSaved: Bool { library.entry(for: title.id) != nil }
    private var availableEpisodes: [Episode] { mergeEpisodes(episodes + entry.episodes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    PosterView(title: title, width: 108)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title.kind == .movie ? "ФИЛЬМ" : "СЕРИАЛ").font(.caption2.bold()).tracking(2).foregroundStyle(Theme.accent)
                        Text(title.title).font(.title2.bold()).textSelection(.enabled)
                        if let year = title.year { Text(String(year)).font(.subheadline).foregroundStyle(Theme.muted) }
                        Button { save(entry) } label: { Label(isSaved ? "В библиотеке" : "В библиотеку", systemImage: isSaved ? "checkmark" : "plus") }
                            .buttonStyle(.bordered).disabled(isSaved)
                    }
                    Spacer(minLength: 0)
                }
                if let error { ErrorNotice(message: error) }
                if !title.overview.isEmpty {
                    DisclosureGroup("Описание от источника") {
                        Text(title.overview).font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 8)
                    }.font(.subheadline).tint(Theme.muted)
                }
                if title.kind == .movie {
                    Toggle("Я досмотрел фильм", isOn: Binding(get: { entry.progress.finished }, set: { value in
                        var changed = entry
                        changed.progress.finished = value
                        changed.chat = []
                        save(changed)
                    }))
                    .tint(Theme.accent).accessibilityIdentifier("finishedToggle")
                    if entry.progress.finished {
                        Button { Task { await loadPlot() } } label: {
                            HStack { if loadingPlot { ProgressView() }; Label("Загрузить сюжет из Wikipedia", systemImage: "text.magnifyingglass") }
                        }.buttonStyle(.bordered).disabled(loadingPlot)
                        Text("Перед обсуждением проверь, что источник соответствует фильму: у одноимённых произведений возможны совпадения.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    episodeSection
                }
                if let plotInfo { Text(plotInfo).font(.footnote).foregroundStyle(Theme.muted) }
                NavigationLink {
                    DiscussionView(title: title, initialEpisodes: availableEpisodes)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.text.bubble.right").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.progress.finished ? "Обсудить после финала" : "Вспомнить просмотренное").font(.headline)
                            Text("С источниками · Локально на iPhone").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("openDiscussion")
                VStack(alignment: .leading, spacing: 12) {
                    SectionCaption(eyebrow: "Добавь контекст", title: "Материалы истории")
                    Text("Сохранено материалов: \(entry.facts.count). Аннотации серий используются только после отметки о просмотре.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Button { sourceImport = true } label: { Label("Добавить текст или субтитры", systemImage: "doc.badge.plus") }
                    if let source = title.sourceURL { Link("Карточка у источника", destination: source).font(.footnote) }
                }
                if entry.progress.finished {
                    Button { editingReflection = nil; reflectionEditor = true } label: { Label("Сохранить личный итог", systemImage: "square.and.pencil") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("writeReflection")
                    ForEach(entry.reflections.sorted { $0.createdAt > $1.createdAt }) { reflection in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Мой итог").font(.headline)
                                Spacer()
                                if let rating = reflection.rating { Text("★ \(rating)/10").foregroundStyle(Theme.accent) }
                                Button {
                                    editingReflection = reflection
                                    reflectionEditor = true
                                } label: { Image(systemName: "pencil") }
                                    .accessibilityLabel("Изменить личный итог")
                            }
                            Text(reflection.summary).font(.subheadline).textSelection(.enabled)
                            ForEach(Array(reflection.liked.enumerated()), id: \.offset) { item in Text("+ " + item.element).font(.caption).foregroundStyle(Theme.muted) }
                            ForEach(Array(reflection.questions.enumerated()), id: \.offset) { item in Text("? " + item.element).font(.caption).foregroundStyle(Theme.muted) }
                            Text(reflection.createdAt, style: .date).font(.caption2).foregroundStyle(Theme.muted)
                        }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(title.title).navigationBarTitleDisplayMode(.inline)
        .task(id: library.activeAccountID) { await loadEpisodes() }
        .onChange(of: library.entry(for: title.id)?.episodes) { _, stored in episodes = stored ?? [] }
        .sheet(isPresented: $sourceImport) { SourceImportView(title: title, episodes: availableEpisodes) }
        .sheet(isPresented: $reflectionEditor) { ReflectionEditorView(title: title, reflection: editingReflection) }
    }

    @ViewBuilder private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption(eyebrow: "Граница просмотра", title: "Серии")
            if loading { ProgressView("Загружаем серии…") }
            if availableEpisodes.isEmpty && !loading {
                InfoCard(symbol: "rectangle.stack", title: "Список серий пока недоступен", text: "Можно добавить своё описание серии вместе с материалами. Поиск по оригинальному названию и подключение TMDB расширяют покрытие.")
            }
            ForEach(availableEpisodes) { episode in
                let watched = entry.progress.watchedEpisodeIDs.contains(episode.id)
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        var changed = entry
                        if watched { changed.progress.watchedEpisodeIDs.remove(episode.id); changed.progress.finished = false; changed.chat = [] }
                        else { changed.progress.watchedEpisodeIDs.insert(episode.id) }
                        save(changed)
                    } label: { Image(systemName: watched ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(watched ? Theme.accent : Theme.muted) }
                    .accessibilityLabel("\(watched ? "Снять просмотр" : "Просмотрено"): сезон \(episode.season), серия \(episode.number)")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("S\(episode.season) · E\(episode.number)").font(.caption.bold()).foregroundStyle(Theme.accent)
                        Text(watched ? episode.name : "Серия \(episode.number)").font(.subheadline)
                        if watched && !episode.summary.isEmpty {
                            DisclosureGroup("Напомнить события") { Text(episode.summary).font(.footnote).foregroundStyle(Theme.muted).padding(.vertical, 6) }
                                .font(.caption).tint(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Просмотрено всё до этой серии") { markThrough(episode) }
                    } label: { Image(systemName: "ellipsis").padding(6).foregroundStyle(Theme.muted) }.accessibilityLabel("Действия с серией")
                }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            Toggle("Я досмотрел сериал", isOn: Binding(get: { entry.progress.finished }, set: { value in
                var changed = entry
                changed.progress.finished = value
                if value { changed.progress.watchedEpisodeIDs.formUnion(availableEpisodes.map(\.id)) }
                changed.chat = []
                save(changed)
            })).tint(Theme.accent)
        }
    }

    private func save(_ value: LibraryEntry) {
        var changed = value
        changed.episodes = mergeEpisodes(episodes + entry.episodes + value.episodes)
        changed.updatedAt = Date()
        library.update(changed)
        if library.lastError == nil { episodes = changed.episodes }
    }

    private func loadEpisodes() async {
        episodes = entry.episodes
        guard title.kind == .series, episodes.isEmpty, title.provider != "local" else { return }
        let requestID = UUID()
        episodeLoadID = requestID
        loading = true
        defer { if episodeLoadID == requestID { loading = false } }
        let accountID = library.activeAccountID
        do {
            let loaded = try await model.catalog.fetchEpisodes(for: title)
            guard accountID == library.activeAccountID, episodeLoadID == requestID else { return }
            episodes = mergeEpisodes(loaded + entry.episodes)
            if isSaved { save(entry) }
        } catch is CancellationError {} catch {
            if accountID == library.activeAccountID, episodeLoadID == requestID { self.error = error.localizedDescription }
        }
    }

    private func markThrough(_ episode: Episode) {
        var changed = entry
        changed.progress.watchedEpisodeIDs.formUnion(availableEpisodes.filter { $0.season < episode.season || ($0.season == episode.season && $0.number <= episode.number) }.map(\.id))
        save(changed)
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
            plotInfo = "Сюжет загружен. Источники можно открыть в обсуждении."
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
}
