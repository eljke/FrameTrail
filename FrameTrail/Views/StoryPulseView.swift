import SwiftUI
import Charts
import FrameTrailCore

struct StoryPulseView: View {
    let title: MediaTitle
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = ""
    @State private var mode = 0
    @State private var response: SourceAnswer?
    @State private var error: String?
    @State private var generating = false
    @State private var generation: Task<Void, Never>?
    @State private var citation: AnswerCitation?
    @State private var reviewing: Episode?
    @State private var retrospective = false

    private var entry: LibraryEntry { library.entry(for: title.id) ?? LibraryEntry(title: title) }
    private var watched: [Episode] {
        entry.episodes.filter { entry.progress.watchedEpisodeIDs.contains($0.id) }
            .sorted { ($0.season, $0.number, $0.id) < ($1.season, $1.number, $1.id) }
    }
    private var checkpoint: StoryCheckpoint {
        StoryCheckpoint(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, records: entry.reflections, through: selectedID)
    }
    private var selected: Episode? { watched.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(model.displayTitle(title).title).font(.title2.bold())
                    if watched.isEmpty {
                        EmptyState(symbol: "waveform.path", title: L10n.text("Здесь появится твой сезон"), text: L10n.text("Отметь просмотренные серии. Оценки и заметки соберутся на одной шкале."))
                    } else {
                        chart
                        Picker(L10n.text("До какой серии вспомнить"), selection: $selectedID) {
                            ForEach(watched) { episode in Text("S\(episode.season) E\(episode.number) · \(episode.name)").tag(episode.id) }
                        }.accessibilityIdentifier("checkpointPicker")
                        if let selected {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("S\(selected.season) E\(selected.number)").font(.caption.bold()).foregroundStyle(Theme.accent)
                                Text(selected.name).font(.title3.bold())
                                if let review = Reflection.latest(in: entry.reflections, episodeID: selected.id), review.hasContent {
                                    if let rating = review.rating { Label("\(rating)/10", systemImage: "star.fill").foregroundStyle(Theme.accent) }
                                    if !review.summary.isEmpty { Text(review.summary).textSelection(.enabled) }
                                    ForEach(review.allLiked, id: \.self) { Text("+ " + $0).font(.subheadline) }
                                    ForEach(review.allDisliked, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Theme.muted) }
                                }
                                Button { reviewing = selected } label: { Label(L10n.text("Оценка и впечатления"), systemImage: "star.bubble") }.buttonStyle(.glass)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
                        }
                        NavigationLink { StoryAtlasView(title: title, throughEpisodeID: selectedID) } label: {
                            Label(L10n.text("Персонажи до этой серии"), systemImage: "person.2").frame(maxWidth: .infinity)
                        }.buttonStyle(.glass)
                        assistantSection
                        Button { retrospective = true } label: { Label(L10n.text("Собрать мои впечатления"), systemImage: "square.stack.3d.up") }
                            .buttonStyle(.glass).disabled(checkpoint.reviews.isEmpty)
                    }
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(L10n.text("Пульс сериала")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Готово")) { dismiss() }.accessibilityIdentifier("closeStoryPulse") } }
            .task {
                if !watched.contains(where: { $0.id == selectedID }) { selectedID = watched.last?.id ?? "" }
                await model.assistant.refreshAvailability()
            }
            .onChange(of: selectedID) { _, _ in stop() }
            .onChange(of: mode) { _, _ in stop() }
            .onChange(of: library.activeAccountID) { _, _ in stop(); dismiss() }
            .onChange(of: entry.progress) { _, _ in stop() }
            .onChange(of: entry.facts) { _, _ in stop() }
            .onChange(of: entry.episodes) { _, _ in stop() }
            .onChange(of: entry.nameAliases) { _, _ in stop() }
            .onChange(of: model.answerLocaleIdentifier) { _, _ in stop() }
            .onDisappear { generation?.cancel(); generation = nil; generating = false }
            .sheet(item: $citation) { CitationDetailView(citation: $0, aliases: entry.nameAliases ?? []) }
            .sheet(item: $reviewing) { episode in ReflectionEditorView(title: title, reflection: Reflection.latest(in: entry.reflections, episodeID: episode.id), episode: episode) }
            .sheet(isPresented: $retrospective) { RetrospectiveView(title: title, throughEpisodeID: selectedID) }
        }
    }

    private var chart: some View {
        let groups = Dictionary(grouping: entry.reflections.filter { $0.episodeID != nil }, by: { $0.episodeID! })
        let reviews = groups.compactMapValues { Reflection.latest(in: $0, episodeID: $0[0].episodeID) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Как менялось впечатление")).font(.headline)
            Chart {
                ForEach(Array(watched.enumerated()), id: \.element.id) { index, episode in
                    if let rating = reviews[episode.id]?.rating {
                        BarMark(x: .value(L10n.text("Серия"), index), y: .value(L10n.text("Оценка"), rating))
                            .foregroundStyle(episode.id == selectedID ? Theme.accent : Theme.muted.opacity(0.5)).cornerRadius(4)
                            .accessibilityLabel("S\(episode.season) E\(episode.number)").accessibilityValue("\(rating)/10")
                    }
                }
                if let index = watched.firstIndex(where: { $0.id == selectedID }) { RuleMark(x: .value(L10n.text("Серия"), index)).foregroundStyle(Theme.accent.opacity(0.5)) }
            }
            .chartYScale(domain: 0...10).chartXScale(domain: -1...max(1, watched.count))
            .chartXAxis(.hidden).chartYAxis { AxisMarks(values: [1, 5, 10]) }
            .chartXSelection(value: Binding<Int?>(get: { watched.firstIndex { $0.id == selectedID } }, set: { if let index = $0, watched.indices.contains(index) { selectedID = watched[index].id } }))
            .frame(height: 160)
            Text(L10n.text("Коснись графика или выбери серию ниже. Пропуски означают, что оценки ещё нет.")).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var assistantSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Вернуться в сюжет")).font(.title3.bold())
            Text(L10n.text("Только просмотренное до выбранной серии. Более поздние события в материалы ответа не входят.")).font(.footnote).foregroundStyle(Theme.muted)
            Picker(L10n.text("Что вспомнить"), selection: $mode) {
                Text(L10n.text("События")).tag(0)
                Text(L10n.text("Сюжетные нити")).tag(1)
                Text(L10n.text("Детали")).tag(2)
            }.pickerStyle(.segmented)
            if generating {
                HStack { ProgressView(); Button(L10n.text("Остановить")) { stop() } }
            } else {
                Button { generate() } label: { Label(L10n.text("Подготовить напоминание"), systemImage: "sparkles") }
                    .buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(Theme.background)
                    .disabled(!checkpoint.context.hasEvidence || !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable)
            }
            if !checkpoint.context.hasEvidence { Text(L10n.text("Добавь материалы просмотренных серий в карточке сериала.")).font(.footnote) }
            if !model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).isAvailable { Text(model.assistant.availability(localeIdentifier: model.answerLocaleIdentifier).message).font(.caption).foregroundStyle(Theme.muted) }
            if let error { ErrorNotice(message: error) }
            if let response {
                LocalizedSourceText(text: response.text, aliases: entry.nameAliases ?? [], autoTranslate: false)
                ForEach(response.citations) { item in
                    Button { citation = item } label: { Label("[\(item.number)] " + (item.label.isEmpty ? L10n.text("Источник") : item.label), systemImage: "doc.text") }.buttonStyle(.glass)
                }
                ShareLink(item: response.text) { Label(L10n.text("Поделиться"), systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func stop() { generation?.cancel(); generation = nil; generating = false; response = nil; citation = nil; error = nil }

    private func generate() {
        guard !generating else { return }
        let packet = checkpoint.context
        let prompts = ["Give a concise catch-up before resuming this series: pivotal events and character motivations at this checkpoint. No later developments.", "Identify unresolved conflicts and character goals at this checkpoint. Do not predict resolutions or hint at future twists.", "Recall significant details explicitly present in the supplied material. Explain their meaning at this checkpoint, never their future significance."]
        let prompt = prompts[mode]
        let locale = model.answerLocaleIdentifier
        let account = library.activeAccountID
        let snapshot = entry
        let checkpointID = selectedID
        let aliases = entry.nameAliases ?? []
        generating = true
        response = nil
        error = nil
        generation = Task {
            defer { if !Task.isCancelled { generating = false; generation = nil } }
            do {
                let result = try await model.assistant.respond(question: prompt, context: packet, history: [], localeIdentifier: locale, preparedQuestion: prompt, aliases: aliases)
                try Task.checkCancellation()
                guard account == library.activeAccountID, snapshot == entry, checkpointID == selectedID, locale == model.answerLocaleIdentifier else { return }
                response = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
