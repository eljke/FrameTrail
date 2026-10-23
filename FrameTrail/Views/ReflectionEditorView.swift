import SwiftUI
import FrameTrailCore

struct ReflectionEditorView: View {
    let title: MediaTitle
    var reflection: Reflection? = nil
    var initialSummary: String = ""
    var episode: Episode? = nil
    var season: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var summary = ""
    @State private var liked = ""
    @State private var disliked = ""
    @State private var likedChoices: [ReviewChoice] = []
    @State private var dislikedChoices: [ReviewChoice] = []
    @State private var questions = ""
    @State private var rating = 0
    @State private var error: String?
    @State private var interview: ReviewQuestions?
    @State private var generating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var skippedInterview = false
    @State private var importingSource = false
    @State private var sourceNotice: String?
    @State private var applyRatingToEpisodes = false
    @State private var overwriteEpisodeRatings = false
    @State private var confirmOverwrite = false
    @State private var showImpressions = false

    private var scopeID: String? { reflection?.episodeID ?? episode?.id }
    private var scopeSeason: Int? { reflection?.episodeSeason ?? episode?.season }
    private var scopeNumber: Int? { reflection?.episodeNumber ?? episode?.number }
    private var seasonScope: Int? { reflection?.seasonNumber ?? season }
    private var currentProgress: WatchProgress { library.entry(for: title.id)?.progress ?? WatchProgress() }
    private var canInterview: Bool {
        if let scopeID { return currentProgress.watchedEpisodeIDs.contains(scopeID) }
        if let seasonScope {
            return library.entry(for: title.id)?.episodes.contains { $0.season == seasonScope && currentProgress.watchedEpisodeIDs.contains($0.id) } == true
        }
        return currentProgress.finished || (title.kind == .series && !currentProgress.watchedEpisodeIDs.isEmpty)
    }
    private var canSave: Bool {
        reflection != nil || rating > 0 || !likedChoices.isEmpty || !dislikedChoices.isEmpty
            || [summary, liked, disliked, questions].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var targetName: String {
        if let seasonScope { return "\(title.title) · season \(seasonScope), watched episodes only" }
        guard let scopeSeason, let scopeNumber else { return title.title + (title.kind == .movie ? " · whole film" : " · series overall") }
        return "\(title.title) · S\(scopeSeason) E\(scopeNumber) only"
    }
    private var reviewContext: GroundedContext {
        let entry = library.entry(for: title.id) ?? LibraryEntry(title: title)
        return SpoilerContextBuilder.forReview(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, episodeID: scopeID, seasonNumber: seasonScope)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.title).font(.headline)
                    if let scopeSeason, let scopeNumber {
                        Text(L10n.text("Сезон %@ · Серия %@", String(describing: scopeSeason), String(describing: scopeNumber))).font(.subheadline).foregroundStyle(Theme.accent)
                    } else if let seasonScope {
                        Text(L10n.text("Сезон %@", String(describing: seasonScope))).font(.subheadline).foregroundStyle(Theme.accent)
                    } else {
                        Text(title.kind == .movie ? L10n.text("Фильм целиком") : L10n.text("Сериал в целом")).font(.subheadline).foregroundStyle(Theme.accent)
                    }
                    RatingSelector(rating: $rating)
                }
                if title.kind == .series && scopeID == nil && rating > 0 {
                    Section {
                        Toggle(L10n.text("Применить к просмотренным сериям"), isOn: $applyRatingToEpisodes)
                            .accessibilityIdentifier("applyRatingToEpisodes")
                        if applyRatingToEpisodes {
                            Toggle(L10n.text("Заменить уже выставленные оценки"), isOn: $overwriteEpisodeRatings)
                            let entry = library.entry(for: title.id) ?? LibraryEntry(title: title)
                            let plan = EpisodeRatingPlan(titleID: title.id, episodes: entry.episodes, watchedEpisodeIDs: entry.progress.watchedEpisodeIDs,
                                                         records: entry.reflections, rating: rating, season: seasonScope, overwrite: overwriteEpisodeRatings)
                            Text(L10n.text("Изменится оценок: %@. Заметки сохранятся.", String(describing: plan.changedCount))).font(.caption).foregroundStyle(.secondary)
                        }
                    } footer: { Text(L10n.text("Только просмотренные серии выбранного сезона или сериала. Действие можно отменить в карточке.")) }
                }
                Section(L10n.text("Заметки")) {
                    TextEditor(text: $summary).frame(minHeight: 90).accessibilityIdentifier("reflectionSummary")
                        .onChange(of: summary) { _, value in if value.count > 10_000 { summary = String(value.prefix(10_000)) } }
                    if scopeID == nil && seasonScope == nil, let last = library.entry(for: title.id)?.chat.last(where: { $0.role == .assistant }) {
                        Button(L10n.text("Взять последний ответ за основу")) { summary = String(last.text.prefix(10_000)) }
                    }
                }
                Button(showImpressions ? L10n.text("Скрыть подробности") : L10n.text("Добавить впечатления и вопросы")) {
                    showImpressions.toggle()
                }.accessibilityIdentifier("toggleReviewDetails")
                if showImpressions {
                    interviewSection
                Section(L10n.text("Что понравилось")) {
                    if let interview { Text(interview.liked).font(.subheadline).foregroundStyle(Theme.accent).textSelection(.enabled) }
                    ReviewChoiceList(choices: choiceOptions(positive: true), selected: $likedChoices)
                    Text(L10n.text("Свой вариант · необязательно")).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $liked).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionLiked")
                        .onChange(of: liked) { _, value in if value.count > 30_000 { liked = String(value.prefix(30_000)) } }
                }
                Section(L10n.text("Что не понравилось")) {
                    if let interview { Text(interview.disliked).font(.subheadline).foregroundStyle(Theme.accent).textSelection(.enabled) }
                    ReviewChoiceList(choices: choiceOptions(positive: false), selected: $dislikedChoices)
                    Text(L10n.text("Свой вариант · необязательно")).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $disliked).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionDisliked")
                        .onChange(of: disliked) { _, value in if value.count > 30_000 { disliked = String(value.prefix(30_000)) } }
                }
                Section(L10n.text("Вопросы на потом")) {
                    TextEditor(text: $questions).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionQuestions")
                        .onChange(of: questions) { _, value in if value.count > 30_000 { questions = String(value.prefix(30_000)) } }
                }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Отзыв"))
            .scrollContentBackground(.hidden).background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Сохранить")) {
                        if applyRatingToEpisodes && overwriteEpisodeRatings && rating > 0 { confirmOverwrite = true }
                        else { save() }
                    }.disabled(!canSave)
                        .accessibilityIdentifier("saveReflection")
                }
            }
            .onAppear {
                if let reflection {
                    summary = reflection.summary
                    liked = reflection.liked.joined(separator: "\n")
                    disliked = reflection.disliked.joined(separator: "\n")
                    likedChoices = reflection.likedChoices
                    dislikedChoices = reflection.dislikedChoices
                    questions = reflection.questions.joined(separator: "\n")
                    rating = reflection.rating ?? 0
                    showImpressions = !reflection.allLiked.isEmpty || !reflection.allDisliked.isEmpty || !reflection.questions.isEmpty
                } else {
                    summary = String(initialSummary.prefix(10_000))
                    rating = Reflection.latest(in: library.entry(for: title.id)?.reflections ?? [], episodeID: scopeID, seasonNumber: seasonScope)?.rating ?? 0
                }
            }
            .task { await model.assistant.refreshAvailability() }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onChange(of: currentProgress) { _, _ in stopInterview(); interview = nil }
            .onChange(of: model.localeIdentifier) { _, _ in stopInterview(); interview = nil }
            .onDisappear { stopInterview() }
            .confirmationDialog(L10n.text("Заменить оценки просмотренных серий? Заметки сохранятся."), isPresented: $confirmOverwrite, titleVisibility: .visible) {
                Button(L10n.text("Заменить оценки")) { save() }
            }
            .sheet(isPresented: $importingSource) {
                SourceImportView(title: title, episodes: library.entry(for: title.id)?.episodes ?? [], initialEpisodeID: scopeID)
            }
        }
    }

    private var interviewSection: some View {
        Section {
            Button {
                skippedInterview = false
                startInterview()
            } label: { Label(interview == nil ? L10n.text("Подобрать вопросы") : L10n.text("Обновить варианты"), systemImage: "sparkles") }
                .disabled(generating || !canInterview || !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable)
            if generating {
                HStack { ProgressView(); Text(L10n.text("Проверяю материалы и готовлю варианты…")).font(.footnote) }
                Button(L10n.text("Остановить")) { stopInterview() }
            }
            Button(skippedInterview ? L10n.text("Вопросы пропущены") : L10n.text("Пропустить вопросы")) {
                stopInterview()
                interview = nil
                skippedInterview = true
            }.disabled(skippedInterview)
            DisclosureGroup(L10n.text("Материалы для разбора")) {
                let context = reviewContext
                Text(context.hasEvidence ? L10n.text("Есть материалы выбранного фильма или серии.") : L10n.text("Сохранённых материалов пока нет."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("Перед разбором попробую найти подробный сюжет Wikipedia. Варианты затронут только доступные источники выбранного просмотренного эпизода или фильма, включая его финал. Другие серии исключены."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Добавить текст или субтитры")) { stopInterview(); importingSource = true }
            }.font(.subheadline)
            if let sourceNotice { Text(sourceNotice).font(.caption).foregroundStyle(.secondary) }
            if !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable {
                Text(L10n.text("Оценки и заметки доступны вручную. Для вариантов помощника подготовь модель и язык в настройках."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text(L10n.text("Вопросы о просмотренном")) } footer: {
            Text(L10n.text("Необязательно: выбери несколько вариантов, добавь свой ответ или сохрани только оценку."))
        }
    }

    private func stopInterview() {
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        generating = false
    }

    private func choiceOptions(positive: Bool) -> [ReviewChoice] {
        let options = positive ? interview?.likedChoices ?? [] : interview?.dislikedChoices ?? []
        let saved = positive ? likedChoices : dislikedChoices
        return options + saved.filter { existing in !options.contains(where: { $0.id == existing.id }) }
    }

    private func startInterview() {
        guard !generating, canInterview, let entry = library.entry(for: title.id) else { return }
        let id = UUID()
        generationID = id
        generating = true
        error = nil
        let accountID = library.activeAccountID
        let locale = model.localeIdentifier
        generationTask = Task {
            defer { if generationID == id { generating = false; generationTask = nil; generationID = nil } }
            do {
                let hasPlot = entry.facts.contains { $0.kind == "plot" && $0.episodeID == scopeID }
                if !hasPlot && (title.kind == .movie || scopeID != nil) {
                    do {
                        let facts: [StoryFact]
                        if let scopeID, let episode = entry.episodes.first(where: { $0.id == scopeID }) {
                            facts = try await model.plots.plot(for: title, episode: episode, progress: entry.progress)
                        } else {
                            facts = try await model.plots.plot(for: title, finished: entry.progress.finished)
                        }
                        try Task.checkCancellation()
                        guard generationID == id, library.activeAccountID == accountID, currentProgress == entry.progress else { return }
                        var changed = library.entry(for: title.id) ?? entry
                        changed.facts.append(contentsOf: facts.filter { fact in !changed.facts.contains(where: { $0.id == fact.id }) })
                        changed.updatedAt = Date()
                        library.update(changed)
                        sourceNotice = library.lastError ?? L10n.text("Загружен подробный сюжет Wikipedia. Варианты могут затрагивать развязку просмотренного.")
                    } catch is CancellationError { throw CancellationError() }
                    catch { sourceNotice = L10n.text("Подробный пересказ не загружен. Использую доступные материалы; развязки в краткой аннотации может не быть. Можно добавить свой текст или субтитры.") }
                }
                try Task.checkCancellation()
                let packet = reviewContext
                let result = try await model.assistant.reviewQuestions(target: targetName, context: packet, rating: rating == 0 ? nil : rating, liked: liked, disliked: disliked, localeIdentifier: locale)
                try Task.checkCancellation()
                guard generationID == id, library.activeAccountID == accountID,
                      currentProgress == entry.progress, model.localeIdentifier == locale else { return }
                interview = result
            } catch is CancellationError {} catch {
                if generationID == id { self.error = error.localizedDescription }
            }
        }
    }

    private func save() {
        var entry = library.entry(for: title.id) ?? LibraryEntry(title: title)
        let saved = Reflection(
            id: reflection?.id ?? UUID(),
            titleID: title.id,
            summary: String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10_000)),
            liked: lines(liked),
            questions: lines(questions),
            rating: rating == 0 ? nil : rating,
            createdAt: reflection?.createdAt ?? Date(),
            disliked: lines(disliked),
            episodeID: scopeID,
            episodeSeason: scopeSeason,
            episodeNumber: scopeNumber,
            likedChoices: likedChoices,
            dislikedChoices: dislikedChoices,
            seasonNumber: seasonScope
        )
        if let index = entry.reflections.firstIndex(where: { $0.id == saved.id }) {
            entry.reflections[index] = saved
        } else {
            entry.reflections.append(saved)
        }
        entry.updatedAt = Date()
        if applyRatingToEpisodes && rating > 0 && scopeID == nil {
            library.updateWithEpisodeRatings(entry, rating: rating, season: seasonScope, overwrite: overwriteEpisodeRatings)
        } else {
            library.update(entry)
        }
        if library.lastError == nil { InteractionFeedback.success(); dismiss() } else { error = library.lastError }
    }

    private func lines(_ text: String) -> [String] {
        Array(text.components(separatedBy: .newlines).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000)) }.filter { !$0.isEmpty }.prefix(30))
    }
}
