import SwiftUI
import FrameTrailCore

struct ReflectionEditorView: View {
    let title: MediaTitle
    var reflection: Reflection? = nil
    var initialSummary: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var summary = ""
    @State private var liked = ""
    @State private var questions = ""
    @State private var rating = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.title).font(.headline)
                    Picker("Оценка", selection: $rating) {
                        Text("Без оценки").tag(0)
                        ForEach(1...10, id: \.self) { Text("\($0)/10").tag($0) }
                    }
                }
                Section("Что осталось после просмотра?") {
                    TextEditor(text: $summary).frame(minHeight: 140).accessibilityIdentifier("reflectionSummary")
                        .onChange(of: summary) { _, value in if value.count > 10_000 { summary = String(value.prefix(10_000)) } }
                    if let last = library.entry(for: title.id)?.chat.last(where: { $0.role == .assistant }) {
                        Button("Взять последний ответ за основу") { summary = String(last.text.prefix(10_000)) }
                    }
                }
                Section("Что понравилось — по пункту на строку") {
                    TextEditor(text: $liked).frame(minHeight: 70)
                        .accessibilityIdentifier("reflectionLiked")
                        .onChange(of: liked) { _, value in if value.count > 30_000 { liked = String(value.prefix(30_000)) } }
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
                    Button("Сохранить") { save() }.disabled([summary, liked, questions].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && rating == 0)
                        .accessibilityIdentifier("saveReflection")
                }
            }
            .onAppear {
                if let reflection {
                    summary = reflection.summary
                    liked = reflection.liked.joined(separator: "\n")
                    questions = reflection.questions.joined(separator: "\n")
                    rating = reflection.rating ?? 0
                } else {
                    summary = String(initialSummary.prefix(10_000))
                }
            }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
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
            createdAt: reflection?.createdAt ?? Date()
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
