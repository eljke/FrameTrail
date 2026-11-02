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

    @State private var context = GroundedContext(text: "", evidence: [], coverage: "", allowedEpisodeIDs: [])
    @State private var searching = false
    @State private var retrieval: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text("Что осталось в памяти")).font(.title2.bold())
                Text(L10n.text("Найди свои слова о финале, героях или темпе. Поиск сопоставляет слова в записях; помощник может разобрать найденное.")).font(.subheadline).foregroundStyle(Theme.muted)
                if searching { ProgressView(L10n.text("Поиск…")) }
                if busy { HStack { ProgressView(); Button(L10n.text("Остановить")) { stop() } } }
                else {
                    Button(L10n.text("Обсудить найденное"), systemImage: "sparkles") { discuss() }.buttonStyle(.glassProminent)
                        .disabled(searching || !context.hasEvidence || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable)
                }
                if let answer {
                    LocalizedSourceText(text: answer.text, autoTranslate: false)
                    ForEach(answer.citations) { item in Button("[\(item.number)] " + L10n.text("Моя запись")) { citation = item } }
                }
                if let error { ErrorNotice(message: error) }
                if !searching && context.evidence.isEmpty {
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
        .onChange(of: query) { _, text in if text.count > 500 { query = String(text.prefix(500)) }; refreshSearch() }
        .onChange(of: library.entries) { _, _ in refreshSearch() }
        .onChange(of: library.activeAccountID) { _, _ in refreshSearch() }
        .onChange(of: model.answerLocaleIdentifier) { _, _ in stop(); answer = nil; citation = nil }
        .task { refreshSearch(invalidate: false); await model.assistant.refreshAvailability() }
        .onDisappear { stop(); retrieval?.cancel(); retrieval = nil; searching = false }
        .sheet(item: $citation) { CitationDetailView(citation: $0) }
    }

    private func stop() { task?.cancel(); task = nil; busy = false }

    private func refreshSearch(invalidate: Bool = true) {
        stop(); retrieval?.cancel(); error = nil
        if invalidate { answer = nil; citation = nil }
        let snapshot = library.entries, account = library.activeAccountID, search = query
        let samples = library.visibleEntries.map { TasteSample(title: $0.title, progress: $0.progress, reviews: $0.reflections) }
        searching = true
        retrieval = Task {
            do {
                if !search.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
                let result = await Task.detached(priority: .userInitiated) { ViewingMemory.context(samples: samples, query: search) }.value
                try Task.checkCancellation()
                guard snapshot == library.entries, account == library.activeAccountID, search == query else { return }
                context = result; searching = false; retrieval = nil
            } catch is CancellationError {} catch { if !Task.isCancelled { searching = false } }
        }
    }

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
