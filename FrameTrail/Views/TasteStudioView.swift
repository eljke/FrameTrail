import SwiftUI
import FrameTrailCore

struct TasteStudioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var answer: SourceAnswer?
    @State private var citation: AnswerCitation?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var portrait: TastePortrait {
        TastePortrait(samples: library.visibleEntries.map { TasteSample(title: $0.title, progress: $0.progress, reviews: $0.reflections) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sparkles.rectangle.stack").font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(L10n.text("Что объединяет любимые истории?")).font(.title2.bold())
                Text(L10n.text("Разбор по твоим оценкам и заметкам. Только на устройстве, с цитатами из записей. Это гипотезы о вкусе, а не выводы о личности.")).font(.subheadline).foregroundStyle(Theme.muted)
                NavigationLink { EveningPicksView() } label: {
                    Label(L10n.text("Подобрать на вечер"), systemImage: "moon.stars").frame(maxWidth: .infinity)
                }.buttonStyle(.glass)
                Picker(L10n.text("Режим"), selection: $mode) {
                    Text(L10n.text("Мой вкус")).tag(0); Text(L10n.text("Связи")).tag(1)
                }.pickerStyle(.segmented)
                if portrait.context.evidence.count < 2 {
                    ContentUnavailableView(L10n.text("Нужно немного впечатлений"), systemImage: "text.bubble", description: Text(L10n.text("Оставь хотя бы два отзыва о просмотренном. Чем конкретнее заметки, тем интереснее разбор.")))
                }
                if busy { HStack { ProgressView(); Button(L10n.text("Остановить")) { stop() } } }
                else {
                    Button(L10n.text("Разобрать мои впечатления"), systemImage: "sparkles") { generate() }
                        .buttonStyle(.glassProminent).tint(Theme.accent)
                        .disabled(portrait.context.evidence.count < 2 || !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable)
                }
                let status = model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier)
                if !status.isAvailable { Text(status.message).font(.caption).foregroundStyle(Theme.muted) }
                if let error { ErrorNotice(message: error) }
                if let answer {
                    LocalizedSourceText(text: answer.text, autoTranslate: false)
                    ForEach(answer.citations) { item in
                        Button { citation = item } label: { Label("[\(item.number)] " + L10n.text("Моя запись"), systemImage: "quote.bubble") }.buttonStyle(.glass)
                    }
                    ShareLink(item: answer.text) { Label(L10n.text("Поделиться"), systemImage: "square.and.arrow.up") }
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(L10n.text("Кинопочерк")).navigationBarTitleDisplayMode(.inline)
        .task { await model.assistant.refreshAvailability() }
        .onChange(of: mode) { _, _ in invalidate() }
        .onChange(of: library.entries) { _, _ in invalidate() }
        .onChange(of: library.activeAccountID) { _, _ in invalidate() }
        .onChange(of: model.answerLocaleIdentifier) { _, _ in invalidate() }
        .onDisappear { stop() }
        .sheet(item: $citation) { CitationDetailView(citation: $0) }
    }

    private func stop() { task?.cancel(); task = nil; busy = false }
    private func invalidate() { stop(); answer = nil; error = nil }

    private func generate() {
        let packet = portrait.context
        let prompt = mode == 0
            ? "Read these personal viewing notes. Propose two or three tentative patterns in what the viewer enjoys or dislikes. Explain with concrete examples from supplied reviews. Avoid personality judgments, plot details and claims about films absent from these notes. Say when notes are too sparse."
            : "Find a surprising thematic connection or tension between the viewer's opinions about different titles. Compare specific notes or a score with its review text. Present it as a question or hypothesis, not a fact about personality. Do not invent preferences or story events. If no meaningful connection is supported, say so."
        let locale = model.answerLocaleIdentifier, snapshot = library.entries, account = library.activeAccountID
        stop(); busy = true; answer = nil; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let result = try await model.assistant.respond(question: prompt, context: packet, history: [], localeIdentifier: locale, preparedQuestion: prompt)
                try Task.checkCancellation()
                guard account == library.activeAccountID, snapshot == library.entries, locale == model.answerLocaleIdentifier else { return }
                answer = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
