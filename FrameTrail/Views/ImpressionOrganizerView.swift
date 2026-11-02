import SwiftUI
import FrameTrailCore

struct ImpressionOrganizerView: View {
    let text: String
    let aliases: [NameAlias]
    let onApply: (OrganizedImpression) -> Void
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var result: OrganizedImpression?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(L10n.text("Помощник распределит твои фразы по разделам. Формулировки останутся твоими; исходная заметка сохранится целиком.")).font(.footnote) }
                if busy { Section { ProgressView(L10n.text("Разбираю заметку…")) } }
                if let result {
                    Section(L10n.text("Что понравилось")) { ForEach(result.liked, id: \.self) { Text($0) } }
                    Section(L10n.text("Что не понравилось")) { ForEach(result.disliked, id: \.self) { Text($0) } }
                    Section(L10n.text("Вопросы на потом")) { ForEach(result.questions, id: \.self) { Text($0) } }
                    if result.liked.isEmpty && result.disliked.isEmpty && result.questions.isEmpty {
                        Text(L10n.text("Явных впечатлений или вопросов не нашлось. Исходная заметка уже на месте."))
                    } else { Button(L10n.text("Добавить к впечатлениям")) { onApply(result); dismiss() } }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Разобрать заметку"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Закрыть")) { dismiss() } } }
            .task {
                guard result == nil, !busy else { return }
                busy = true
                task = Task {
                    defer { if !Task.isCancelled { busy = false; task = nil } }
                    do { result = try await model.assistant.organizeImpression(text, aliases: aliases) }
                    catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
                }
            }
            .onChange(of: library.activeAccountID) { _, _ in task?.cancel(); dismiss() }
            .onDisappear { task?.cancel(); task = nil; busy = false }
        }
    }
}
