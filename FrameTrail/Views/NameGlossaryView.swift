import SwiftUI
import FrameTrailCore

struct NameGlossaryView: View {
    let title: MediaTitle
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var rows: [Row] = []
    @State private var error: String?

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
        }
    }

    private func suggestNames() {
        guard let entry = library.entry(for: title.id) else { return }
        let context = SpoilerContextBuilder.build(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, question: "")
        let names = LocalTranslationService.detectedNames(in: context.evidence.map(\.text).joined(separator: "\n"))
        for name in names where rows.count < 100 && !rows.contains(where: { $0.original == name }) { rows.append(Row(original: name)) }
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
