import SwiftUI
import FrameTrailCore

struct ReflectionEditorView: View {
    let title: MediaTitle
    var reflection: Reflection? = nil
    var initialSummary: String = ""
    var episode: Episode? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var summary = ""
    @State private var liked = ""
    @State private var disliked = ""
    @State private var questions = ""
    @State private var rating = 0
    @State private var error: String?
    @State private var interview: ReviewQuestions?
    @State private var generating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var skippedInterview = false

    private var scopeID: String? { reflection?.episodeID ?? episode?.id }
    private var scopeSeason: Int? { reflection?.episodeSeason ?? episode?.season }
    private var scopeNumber: Int? { reflection?.episodeNumber ?? episode?.number }
    private var currentProgress: WatchProgress { library.entry(for: title.id)?.progress ?? WatchProgress() }
    private var canInterview: Bool {
        if let scopeID { return currentProgress.watchedEpisodeIDs.contains(scopeID) }
        return currentProgress.finished || (title.kind == .series && !currentProgress.watchedEpisodeIDs.isEmpty)
    }
    private var targetName: String {
        guard let scopeSeason, let scopeNumber else { return title.title + (title.kind == .movie ? " · whole film" : " · series overall") }
        return "\(title.title) · S\(scopeSeason) E\(scopeNumber) only"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.title).font(.headline)
                    if let scopeSeason, let scopeNumber {
                        Text("Сезон \(scopeSeason) · Серия \(scopeNumber)").font(.subheadline).foregroundStyle(Theme.accent)
                    } else {
                        Text(title.kind == .movie ? "Фильм целиком" : "Сериал в целом").font(.subheadline).foregroundStyle(Theme.accent)
                    }
                    RatingSelector(rating: $rating)
                }
                interviewSection
                Section("Что осталось после просмотра?") {
                    TextEditor(text: $summary).frame(minHeight: 140).accessibilityIdentifier("reflectionSummary")
                        .onChange(of: summary) { _, value in if value.count > 10_000 { summary = String(value.prefix(10_000)) } }
                    if scopeID == nil, let last = library.entry(for: title.id)?.chat.last(where: { $0.role == .assistant }) {
                        Button("Взять последний ответ за основу") { summary = String(last.text.prefix(10_000)) }
                    }
                }
                Section("Что понравилось — по пункту на строку") {
                    if let interview { Text(interview.liked).font(.subheadline).foregroundStyle(Theme.accent).textSelection(.enabled) }
                    TextEditor(text: $liked).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionLiked")
                        .onChange(of: liked) { _, value in if value.count > 30_000 { liked = String(value.prefix(30_000)) } }
                }
                Section("Что не понравилось или могло быть лучше?") {
                    if let interview { Text(interview.disliked).font(.subheadline).foregroundStyle(Theme.accent).textSelection(.enabled) }
                    TextEditor(text: $disliked).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionDisliked")
                        .onChange(of: disliked) { _, value in if value.count > 30_000 { disliked = String(value.prefix(30_000)) } }
                }
                Section("О чём ещё хочется подумать?") {
                    TextEditor(text: $questions).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionQuestions")
                        .onChange(of: questions) { _, value in if value.count > 30_000 { questions = String(value.prefix(30_000)) } }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle("Личный итог")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled([summary, liked, disliked, questions].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && rating == 0)
                        .accessibilityIdentifier("saveReflection")
                }
            }
            .onAppear {
                if let reflection {
                    summary = reflection.summary
                    liked = reflection.liked.joined(separator: "\n")
                    disliked = reflection.disliked.joined(separator: "\n")
                    questions = reflection.questions.joined(separator: "\n")
                    rating = reflection.rating ?? 0
                } else {
                    summary = String(initialSummary.prefix(10_000))
                    rating = Reflection.latest(in: library.entry(for: title.id)?.reflections ?? [], episodeID: scopeID)?.rating ?? 0
                }
            }
            .task {
                await model.assistant.refreshAvailability()
                if !model.isUITesting && !skippedInterview && canInterview && model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable { startInterview() }
            }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onChange(of: currentProgress) { _, _ in stopInterview(); interview = nil }
            .onChange(of: model.localeIdentifier) { _, _ in stopInterview(); interview = nil }
            .onDisappear { stopInterview() }
        }
    }

    private var interviewSection: some View {
        Section {
            Button {
                skippedInterview = false
                startInterview()
            } label: { Label(interview == nil ? "Вопросы о впечатлениях" : "Уточнить вопросы с учётом ответов", systemImage: "sparkles") }
                .disabled(generating || !canInterview || !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable)
            if generating {
                HStack { ProgressView(); Text("Готовлю вопросы на iPhone…").font(.footnote) }
                Button("Остановить") { stopInterview() }
            }
            Button(skippedInterview ? "Вопросы пропущены" : "Пропустить вопросы") {
                stopInterview()
                interview = nil
                skippedInterview = true
            }.disabled(skippedInterview)
            Text("Можно сохранить только оценку. Впечатления и ответы необязательны; заполненные поля сохранятся в дневнике.")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable
                 ? "Apple Intelligence предложит вопросы про выбранную историю или серию с учётом оценки и твоих ответов. Сохраняются твои впечатления; вопросы можно пропустить."
                 : "Оценки и заметки доступны вручную. Для вопросов помощника подготовь локальную модель и язык в настройках.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Разобраться в послевкусии") }
    }

    private func stopInterview() {
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        generating = false
    }

    private func startInterview() {
        guard !generating, canInterview, let entry = library.entry(for: title.id) else { return }
        let id = UUID()
        generationID = id
        generating = true
        error = nil
        let accountID = library.activeAccountID
        let locale = model.localeIdentifier
        let packet = SpoilerContextBuilder.forReview(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, episodeID: scopeID)
        generationTask = Task {
            defer { if generationID == id { generating = false; generationTask = nil; generationID = nil } }
            do {
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
            episodeNumber: scopeNumber
        )
        if let index = entry.reflections.firstIndex(where: { $0.id == saved.id }) {
            entry.reflections[index] = saved
        } else {
            entry.reflections.append(saved)
        }
        entry.updatedAt = Date()
        library.update(entry)
        if library.lastError == nil { dismiss() } else { error = library.lastError }
    }

    private func lines(_ text: String) -> [String] {
        Array(text.components(separatedBy: .newlines).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000)) }.filter { !$0.isEmpty }.prefix(30))
    }
}
