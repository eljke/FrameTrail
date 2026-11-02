import SwiftUI
import FrameTrailCore

struct ViewingMemoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var answer: SourceAnswer?
    @State private var citation: AnswerCitation?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var context: GroundedContext {
        ViewingMemory.context(samples: library.visibleEntries.map { TasteSample(title: $0.title, progress: $0.progress, reviews: $0.reflections) }, query: query)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text("Что осталось в памяти")).font(.title2.bold())
                Text(L10n.text("Найди свои слова о финале, героях или темпе. Поиск сопоставляет слова в записях; помощник может разобрать найденное.")).font(.subheadline).foregroundStyle(Theme.muted)
                if busy { HStack { ProgressView(); Button(L10n.text("Остановить")) { stop() } } }
                else {
                    Button(L10n.text("Обсудить найденное"), systemImage: "sparkles") { discuss() }.buttonStyle(.glassProminent)
                        .disabled(!context.hasEvidence || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable)
                }
                if let answer {
                    LocalizedSourceText(text: answer.text, autoTranslate: false)
                    ForEach(answer.citations) { item in Button("[\(item.number)] " + L10n.text("Моя запись")) { citation = item } }
                }
                if let error { ErrorNotice(message: error) }
                if context.evidence.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(context.evidence) { fact in
                    if let entry = library.entry(for: fact.titleID ?? "") {
                        NavigationLink(value: entry.title) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.displayTitle(entry.title).title).font(.headline)
                                Text(fact.text).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(8)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(L10n.text("Мои воспоминания")).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.text("Финал, диалоги, любимый герой…"))
        .onChange(of: query) { _, text in if text.count > 500 { query = String(text.prefix(500)) }; stop(); answer = nil }
        .onChange(of: library.entries) { _, _ in stop(); answer = nil }
        .onChange(of: library.activeAccountID) { _, _ in stop(); answer = nil }
        .onChange(of: model.answerLocaleIdentifier) { _, _ in stop(); answer = nil }
        .task { await model.assistant.refreshAvailability() }
        .onDisappear { stop() }
        .sheet(item: $citation) { CitationDetailView(citation: $0) }
    }

    private func stop() { task?.cancel(); task = nil; busy = false }

    private func discuss() {
        let snapshot = library.entries, account = library.activeAccountID, locale = model.answerLocaleIdentifier
        let packet = context, search = query
        stop(); busy = true; answer = nil; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let prompt = "Discuss the viewer's own saved opinions related to this question. Cite specific records. Search is incomplete: never claim to cover the whole diary or invent a memory. Viewer question: " + search
                let result = try await model.assistant.respond(question: prompt, context: packet, localeIdentifier: locale)
                try Task.checkCancellation()
                guard snapshot == library.entries, account == library.activeAccountID, locale == model.answerLocaleIdentifier, search == query else { return }
                answer = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
