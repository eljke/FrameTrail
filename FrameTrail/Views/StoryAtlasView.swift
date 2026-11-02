import SwiftUI
import FrameTrailCore

struct StoryAtlasView: View {
    let title: MediaTitle
    var throughEpisodeID: String?
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var atlas: StoryAtlas?
    @State private var selectedName: String?
    @State private var answer: SourceAnswer?
    @State private var citation: AnswerCitation?
    @State private var question = ""
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var entry: LibraryEntry { library.entry(for: title.id) ?? LibraryEntry(title: title) }
    private var context: GroundedContext {
        if let throughEpisodeID {
            return StoryCheckpoint(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, records: [], through: throughEpisodeID).context
        }
        return SpoilerContextBuilder.build(title: title, episodes: entry.episodes, progress: entry.progress, facts: entry.facts, question: "", maxCharacters: 9000)
    }
    private var person: StoryPerson? { atlas?.people.first { $0.name == selectedName } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(L10n.text("Только до твоей серии"), systemImage: "eye.slash").font(.caption).foregroundStyle(Theme.accent)
                Text(L10n.text("Кто есть кто")).font(.largeTitle.bold())
                Text(L10n.text("Вспомни героя и открой эпизоды, где он появлялся в доступных материалах. Краткая аннотация не заменяет полный сюжет.")).font(.subheadline).foregroundStyle(Theme.muted)
                if busy { HStack { ProgressView(); Button(L10n.text("Остановить")) { cancel() } } }
                else {
                    Button(L10n.text("Найти персонажей"), systemImage: "person.2") { build() }.buttonStyle(.glassProminent)
                        .disabled(!context.hasEvidence || !model.assistant.availability(localeIdentifier: "en_US").isAvailable)
                }
                if !context.hasEvidence { Text(L10n.text("Добавь материалы просмотренных серий в карточке сериала.")).foregroundStyle(Theme.muted) }
                if let atlas {
                    if atlas.people.isEmpty { Text(L10n.text("В этих материалах не удалось надёжно выделить персонажей.")) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                        ForEach(atlas.people) { item in
                            Button { selectedName = item.name; answer = nil; InteractionFeedback.selection() } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "person.crop.circle").font(.title2)
                                    Text(displayName(item.name)).font(.headline).lineLimit(2)
                                    Text(L10n.text("Фрагментов: %@", String(item.sources.count))).font(.caption)
                                }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding(16)
                                    .background(selectedName == item.name ? Theme.accent.opacity(0.15) : Theme.card, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let person { personDetails(person) }
                if let error { ErrorNotice(message: error) }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(L10n.text("Персонажи")).navigationBarTitleDisplayMode(.inline)
        .task { await model.assistant.refreshAvailability() }
        .onChange(of: entry) { _, _ in invalidate() }
        .onChange(of: library.activeAccountID) { _, _ in invalidate() }
        .onChange(of: model.answerLocaleIdentifier) { _, _ in invalidate() }
        .onDisappear { cancel() }
        .sheet(item: $citation) { CitationDetailView(citation: $0, aliases: entry.nameAliases ?? []) }
    }

    @ViewBuilder private func personDetails(_ person: StoryPerson) -> some View {
        Text(displayName(person.name)).font(.title2.bold())
        let companions = atlas?.companions(of: person.name) ?? []
        if !companions.isEmpty {
            Text(L10n.text("Встречаются в общих фрагментах")).font(.caption).foregroundStyle(Theme.muted)
            Text(companions.map(displayName).joined(separator: " · ")).font(.subheadline)
        }
        ForEach(person.sources) { fact in
            VStack(alignment: .leading, spacing: 10) {
                if let episode = entry.episodes.first(where: { $0.id == fact.episodeID }) {
                    Text("S\(episode.season) E\(episode.number) · \(episode.name)").font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                LocalizedSourceText(text: fact.text, aliases: entry.nameAliases ?? []).font(.subheadline)
                if let url = fact.sourceURL { Link(L10n.text("Открыть источник"), destination: url).font(.caption) }
            }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        }
        TextField(L10n.text("Спросить о герое или отношениях…"), text: $question, axis: .vertical).textFieldStyle(.roundedBorder)
            .onChange(of: question) { _, value in if value.count > 1000 { question = String(value.prefix(1000)) } }
        Button(L10n.text("Объяснить по источникам"), systemImage: "sparkles") { ask(person) }.buttonStyle(.glass)
            .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let answer {
            LocalizedSourceText(text: answer.text, aliases: entry.nameAliases ?? [], autoTranslate: false)
            ForEach(answer.citations) { item in Button("[\(item.number)] " + L10n.text("Источник")) { citation = item } }
        }
    }

    private func displayName(_ name: String) -> String {
        model.localeIdentifier == "ru_RU" ? entry.nameAliases?.first(where: { $0.original == name })?.russian ?? name : name
    }

    private func cancel() { task?.cancel(); task = nil; busy = false }
    private func invalidate() { cancel(); atlas = nil; answer = nil; selectedName = nil }

    private func build() {
        let snapshot = entry, account = library.activeAccountID, packet = context
        cancel(); busy = true; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let result = try await model.assistant.storyAtlas(context: packet, aliases: snapshot.nameAliases ?? [])
                try Task.checkCancellation()
                guard account == library.activeAccountID, snapshot == entry else { return }
                atlas = result; selectedName = result.people.first?.name
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }

    private func ask(_ person: StoryPerson) {
        let snapshot = entry, account = library.activeAccountID, locale = model.answerLocaleIdentifier
        let packet = context, text = person.name + ": " + question
        cancel(); busy = true; answer = nil; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do {
                let result = try await model.assistant.respond(question: text, context: packet, localeIdentifier: locale, aliases: snapshot.nameAliases ?? [])
                try Task.checkCancellation()
                guard snapshot == entry, account == library.activeAccountID, locale == model.answerLocaleIdentifier else { return }
                answer = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
