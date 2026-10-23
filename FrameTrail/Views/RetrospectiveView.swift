import SwiftUI
import FrameTrailCore

struct RetrospectiveView: View {
    let title: MediaTitle
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var result = ""
    @State private var error: String?
    @State private var busy = false
    @State private var completed = 0
    @State private var total = 1
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var resultEpisodeCount = 0

    private var entry: LibraryEntry? { library.entry(for: title.id) }
    private var compilation: ReflectionCompilation {
        ReflectionCompilation(records: entry?.reflections ?? [], watchedEpisodeIDs: entry?.progress.watchedEpisodeIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.title).font(.title3.bold())
                    Label("Впечатления о сериях: \(compilation.episodeCount)", systemImage: "square.stack.3d.up")
                    Text("Помощник соберёт общую картину по твоим оценкам и заметкам: что работало, что мешало и как менялось впечатление. Это воспоминание о твоём опыте, а не пересказ неподтверждённых событий.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if compilation.shortened {
                        Text("Длинные записи сокращаются для обработки: до 180 символов каждого поля на серию. Полные оригиналы остаются в дневнике.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(result.isEmpty ? "Собрать общую картину" : "Собрать заново") { start() }
                        .disabled(busy || compilation.episodeCount == 0 || !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable)
                    if busy {
                        ProgressView(value: Double(completed), total: Double(total))
                        Text("Локальная обработка: \(completed) из \(total) этапов. Для длинного сериала потребуется больше времени.").font(.caption)
                        Button("Остановить", role: .cancel) { stop() }
                    }
                    if !model.assistant.availability(localeIdentifier: model.localeIdentifier).isAvailable {
                        Text(model.assistant.availability(localeIdentifier: model.localeIdentifier).message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if compilation.episodeCount == 0 {
                        Text("Сначала оцени просмотренные серии или сохрани о них впечатления через меню серии. Ответы на вопросы необязательны.").font(.footnote)
                    }
                } header: { Text("Apple Intelligence · на iPhone") }
                if !result.isEmpty {
                    Section("Сводка — можно отредактировать") {
                        TextEditor(text: $result).frame(minHeight: 240)
                            .disabled(busy)
                            .onChange(of: result) { _, text in if text.count > 10_000 { result = String(text.prefix(10_000)) } }
                        ShareLink(item: title.title + "\n\n" + result) { Label("Поделиться сводкой", systemImage: "square.and.arrow.up") }
                        Text("Сохрани сводку в дневник, чтобы вернуться к ней позже. При входе в аккаунт она синхронизируется как личный итог.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle("Общая картина")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(busy || result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await model.assistant.refreshAvailability() }
            .onChange(of: entry?.progress) { _, _ in stop(); result = "" }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onChange(of: model.localeIdentifier) { _, _ in stop() }
            .onDisappear { stop() }
        }
    }

    private func start() {
        guard !busy, let snapshot = entry else { return }
        let accountID = library.activeAccountID
        let locale = model.localeIdentifier
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
                let text = try await model.assistant.compileReflections(title: title.title, compilation: plan, localeIdentifier: locale) { done, count in
                    if generationID == id { completed = done; total = count }
                }
                try Task.checkCancellation()
                guard generationID == id, library.activeAccountID == accountID,
                      entry?.progress == snapshot.progress, model.localeIdentifier == locale else { return }
                guard entry?.reflections == snapshot.reflections else {
                    error = "За время обработки записи изменились. Запусти сборку сводки ещё раз."
                    return
                }
                result = text
                resultEpisodeCount = plan.episodeCount
            } catch is CancellationError {} catch {
                if generationID == id { self.error = error.localizedDescription }
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
        let header = "Сводка впечатлений · серий: \(resultEpisodeCount)"
        let rating = Reflection.latest(in: entry.reflections)?.rating
        entry.reflections.append(Reflection(titleID: title.id, summary: header + "\n\n" + result, rating: rating))
        library.update(entry)
        if let failure = library.lastError { error = failure }
        else { dismiss() }
    }
}
