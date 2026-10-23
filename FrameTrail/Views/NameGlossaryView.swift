import SwiftUI
import FrameTrailCore
import NaturalLanguage

struct NameGlossaryView: View {
    let title: MediaTitle
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var rows: [Row] = []
    @State private var error: String?
    @State private var suggesting = false
    @State private var suggestionTask: Task<Void, Never>?
    @State private var notice: String?

    private var russianSources: String {
        guard let entry = library.entry(for: title.id) else { return "" }
        var sources = entry.episodes.filter { entry.progress.watchedEpisodeIDs.contains($0.id) }.map(\.summary)
        if title.kind == .movie && entry.progress.finished { sources.append(model.displayTitle(title).overview) }
        return sources.filter { NLLanguageRecognizer.dominantLanguage(for: $0) == .russian }.joined(separator: "\n")
    }

    private struct Row: Identifiable {
        let id = UUID()
        var original = ""
        var russian = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text("Укажи привычное написание имён. Без него перевод сохранит оригинал. Словарь действует только для этого произведения и синхронизируется с аккаунтом."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.text("Найти имена в просмотренном")) { suggestNames() }
                    if !russianSources.isEmpty && model.assistant.availability(localeIdentifier: "en_US").isAvailable {
                        Button(L10n.text("Предложить русское написание")) { suggestSpellings() }.disabled(suggesting)
                    }
                    if suggesting { ProgressView() }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(L10n.text("Оригинальное имя"), text: $row.original)
                            TextField(L10n.text("Русское написание"), text: $row.russian)
                        }.autocorrectionDisabled()
                    }.onDelete { rows.remove(atOffsets: $0) }
                    Button(L10n.text("Добавить имя")) { rows.append(Row()) }.disabled(rows.count >= 100)
                } footer: { Text(L10n.text("Оставь русское написание пустым, чтобы использовать оригинал. Нажми на строку и смахни влево, чтобы удалить её.")) }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Имена и названия"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Сохранить")) { save() } }
            }
            .onAppear { rows = (library.entry(for: title.id)?.nameAliases ?? []).map { Row(original: $0.original, russian: $0.russian) } }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onDisappear { suggestionTask?.cancel() }
        }
    }

    private func suggestNames() {
        guard let entry = library.entry(for: title.id) else { return }
        let context = SpoilerContextBuilder.build(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, question: "")
        let names = LocalTranslationService.detectedNames(in: context.evidence.map(\.text).joined(separator: "\n"))
        for name in names where rows.count < 100 && !rows.contains(where: { $0.original == name }) { rows.append(Row(original: name)) }
    }

    private func suggestSpellings() {
        guard !suggesting, let entry = library.entry(for: title.id) else { return }
        let account = library.activeAccountID
        let context = SpoilerContextBuilder.build(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, question: "")
        let english = context.evidence.map(\.text).joined(separator: "\n")
        let russian = russianSources
        suggesting = true
        error = nil
        suggestionTask = Task {
            defer { suggesting = false; suggestionTask = nil }
            do {
                let proposals = try await model.assistant.suggestNameSpellings(english: english, russian: russian)
                try Task.checkCancellation()
                guard account == library.activeAccountID, library.entry(for: title.id)?.progress == entry.progress else { return }
                for proposal in proposals {
                    if let index = rows.firstIndex(where: { $0.original == proposal.original }) {
                        if rows[index].russian.isEmpty { rows[index].russian = proposal.russian }
                    } else if rows.count < 100 { rows.append(Row(original: proposal.original, russian: proposal.russian)) }
                }
                notice = proposals.isEmpty ? L10n.text("Надёжных совпадений нет. Можно указать написание вручную.") : L10n.text("Проверь предложенные соответствия перед сохранением. Они ещё не применены.")
            } catch is CancellationError {} catch { self.error = L10n.error(error) }
        }
    }

    private func save() {
        guard var entry = library.entry(for: title.id) else { return }
        let aliases = rows.compactMap { row -> NameAlias? in
            let original = row.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let russian = row.russian.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !russian.isEmpty else { return nil }
            return NameAlias(original: original, russian: russian)
        }
        entry.nameAliases = aliases.isEmpty ? nil : aliases
        library.update(entry)
        if let failure = library.lastError { error = failure }
        else { model.assistant.translation.clearCache(); InteractionFeedback.success(); dismiss() }
    }
}
