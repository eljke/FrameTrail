import SwiftUI
import FrameTrailCore

struct DiscussionView: View {
    let title: MediaTitle
    var initialEpisodes: [Episode] = []
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var question = ""
    @State private var strict = false
    @State private var busy = false
    @State private var error: String?
    @State private var sourceSearch = ""
    @State private var task: Task<Void, Never>?
    @State private var activeRequestID: UUID?
    @State private var confirmClear = false
    @State private var showReflection = false
    @State private var reflectionDraft = ""
    @State private var selectedCitation: AnswerCitation?

    private var entry: LibraryEntry { library.entry(for: title.id) ?? LibraryEntry(title: title) }
    private var context: GroundedContext {
        SpoilerContextBuilder.build(title: title, episodes: entry.episodes, progress: entry.progress,
                                    facts: entry.facts, question: strict ? sourceSearch : question, maxCharacters: 9_000)
    }
    private var availability: AssistantAvailability { model.assistant.availability(localeIdentifier: model.localeIdentifier) }

    var body: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InfoCard(symbol: entry.progress.finished ? "checkmark.seal" : "eye.slash", title: entry.progress.finished ? L10n.text("Обсуждение после просмотра") : L10n.text("В пределах просмотренного"), text: context.hasEvidence ? L10n.text("Источников для ответа: %@", String(context.evidence.count)) : L10n.text("Нет материалов для ответа. Отметь просмотренное или добавь текст."))
                    Picker(L10n.text("Режим"), selection: $strict) {
                        Text(L10n.text("Обсуждение")).tag(false)
                        Text(L10n.text("Источники")).tag(true)
                    }.pickerStyle(.segmented)
                    if strict {
                        TextField(L10n.text("Найти в материалах"), text: $sourceSearch).textFieldStyle(.roundedBorder)
                            .onChange(of: sourceSearch) { _, value in if value.count > 1_000 { sourceSearch = String(value.prefix(1_000)) } }
                        evidenceList
                    } else {
                        if !availability.isAvailable {
                            ErrorNotice(message: availability.message)
                            Button(L10n.text("Открыть настройки помощника")) { model.selectedTab = 3 }
                                .font(.footnote).foregroundStyle(Theme.accent)
                        }
                        Text(L10n.text("Язык ответа: %@. Модель может ошибиться или вспомнить сведения вне источников. Для строгого режима открой «Источники».", String(describing: model.localeIdentifier == "ru_RU" ? L10n.text("русский") : "English")))
                            .font(.caption).foregroundStyle(Theme.muted)
                        if entry.chat.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.text("С чего начнём?")).font(.headline)
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button { question = suggestion } label: {
                                        HStack { Text(suggestion).font(.subheadline).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.down.left") }
                                            .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(entry.chat) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(turn.role == .user ? L10n.text("Ты") : L10n.text("FrameTrail · локально"), systemImage: turn.role == .user ? "person.crop.circle" : "sparkles")
                                    .font(.caption.bold()).foregroundStyle(turn.role == .user ? Theme.muted : Theme.accent)
                                Text(SourceAnswer.visibleText(turn.text)).font(.body).textSelection(.enabled)
                                if let citations = turn.citations, !citations.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(citations) { citation in
                                                Button { selectedCitation = citation } label: {
                                                    Label("[\(citation.number)] \(citation.label.isEmpty ? L10n.text("Источник") : citation.label)", systemImage: "doc.text")
                                                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                                                        .background(Theme.accent.opacity(0.12), in: Capsule())
                                                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                                            }
                                        }
                                    }
                                } else if turn.role == .assistant {
                                    Text(L10n.text("В старом ответе ссылки не сохранены. Для проверяемых источников задай вопрос ещё раз."))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                if turn.role == .assistant {
                                    HStack {
                                        ShareLink(item: title.title + "\n\n" + turn.text) { Label(L10n.text("Поделиться"), systemImage: "square.and.arrow.up") }
                                        if entry.progress.finished {
                                            Button(L10n.text("Написать отзыв")) { reflectionDraft = turn.text; showReflection = true }
                                        }
                                    }.font(.caption)
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(turn.role == .user ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Color.clear.frame(height: 1).id("lastMessage")
                        if busy { HStack { ProgressView(); Text(L10n.text("Готовлю ответ…")).font(.footnote).foregroundStyle(Theme.muted) } }
                        if let error { ErrorNotice(message: error) }
                        DisclosureGroup(L10n.text("На каких материалах основан ответ")) { evidenceList.padding(.top, 10) }
                            .font(.footnote).tint(Theme.accent)
                    }
                }.padding(20)
            }
            if !strict {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField(L10n.text("Вопрос о фильме или сериале…"), text: $question, axis: .vertical)
                        .lineLimit(1...5).padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        .onChange(of: question) { _, value in if value.count > 1_000 { question = String(value.prefix(1_000)) } }
                        .accessibilityIdentifier("assistantQuestion")
                    if busy {
                        Button { stopResponse() } label: { Image(systemName: "stop.circle.fill").font(.title) }.accessibilityLabel(L10n.text("Остановить ответ"))
                    } else {
                        Button { startResponse() } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }
                            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !availability.isAvailable || !context.hasEvidence)
                            .accessibilityLabel(L10n.text("Отправить вопрос"))
                    }
                }.padding(16).background(Theme.background)
            }
        }
        .onChange(of: entry.chat.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("lastMessage", anchor: .bottom) } }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(L10n.text("Обсуждение")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                if entry.progress.finished { Button(L10n.text("Отзыв"), systemImage: "square.and.pencil") { reflectionDraft = ""; showReflection = true } }
                Button(L10n.text("Очистить обсуждение"), role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .task { _ = prepareEntry(); await model.assistant.refreshAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.assistant.refreshAvailability() } }
        }
        .onChange(of: library.activeAccountID) { _, _ in stopResponse() }
        .onChange(of: entry.progress) { _, _ in stopResponse() }
        .onChange(of: entry.nameAliases) { _, _ in stopResponse() }
        .onChange(of: model.localeIdentifier) { _, _ in stopResponse() }
        .onDisappear { stopResponse() }
        .sheet(isPresented: $showReflection) { ReflectionEditorView(title: title, initialSummary: reflectionDraft) }
        .sheet(item: $selectedCitation) { CitationDetailView(citation: $0, aliases: entry.nameAliases ?? []) }
        .confirmationDialog(L10n.text("Удалить весь диалог этой истории с устройства?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.text("Очистить обсуждение"), role: .destructive) { stopResponse(); library.clearChat(for: title.id) }
        }
    }

    private var suggestions: [String] {
        if model.localeIdentifier == "ru_RU" {
            return entry.progress.finished ? [L10n.text("Кратко резюмируй историю"), L10n.text("Объясни концовку, отделяя факты от интерпретаций"), L10n.text("Какие вопросы стоит обсудить после просмотра?")] : [L10n.text("Напомни важные события просмотренных серий"), L10n.text("Что известно о мотивах героев на этом этапе?")]
        }
        return entry.progress.finished ? ["Summarize the story briefly", "Explain the ending; separate facts from interpretation", "What questions are worth discussing after watching?"] : ["Remind me of the important events so far", "What do we know about the characters' motives so far?"]
    }

    @ViewBuilder private var evidenceList: some View {
        if context.evidence.isEmpty {
            Text(L10n.text("Пока нет материалов в разрешённых границах. Отметь просмотренные серии или добавь собственный текст в карточке произведения."))
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        ForEach(context.evidence) { fact in
            VStack(alignment: .leading, spacing: 8) {
                Text(fact.id).font(.caption2.monospaced()).foregroundStyle(Theme.accent)
                LocalizedSourceText(text: fact.text, aliases: entry.nameAliases ?? []).font(.footnote)
                if let url = fact.sourceURL { Link(L10n.text("Открыть источник"), destination: url).font(.caption) }
                else { Text(L10n.text("Материал пользователя")).font(.caption2).foregroundStyle(Theme.muted) }
            }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func startResponse() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        let requestID = UUID()
        activeRequestID = requestID
        busy = true
        error = nil
        task = Task { await respond(to: text, requestID: requestID) }
    }

    private func stopResponse() {
        activeRequestID = nil
        task?.cancel()
        task = nil
        busy = false
    }

    private func prepareEntry() -> LibraryEntry? {
        let existing = library.entry(for: title.id)
        var saved = existing ?? LibraryEntry(title: title)
        if existing == nil {
            saved.episodes = initialEpisodes
            library.update(saved)
            if let failure = library.lastError { error = failure; return nil }
        }
        return library.entry(for: title.id)
    }

    private func respond(to text: String, requestID: UUID) async {
        guard activeRequestID == requestID else { return }
        defer {
            if activeRequestID == requestID {
                busy = false
                activeRequestID = nil
                task = nil
            }
        }
        guard let snapshot = prepareEntry() else { return }
        let accountID = library.activeAccountID
        let localeIdentifier = model.localeIdentifier
        do {
            let prepared = try await model.assistant.prepareQuestion(question: text, localeIdentifier: localeIdentifier, aliases: snapshot.nameAliases ?? [])
            try Task.checkCancellation()
            guard activeRequestID == requestID, accountID == library.activeAccountID,
                  localeIdentifier == model.localeIdentifier, let afterTranslation = library.entry(for: title.id),
                  afterTranslation.progress == snapshot.progress, afterTranslation.chat == snapshot.chat,
                  afterTranslation.facts == snapshot.facts, afterTranslation.episodes == snapshot.episodes else { return }
            let packet = SpoilerContextBuilder.build(title: title, episodes: snapshot.episodes, progress: snapshot.progress, facts: snapshot.facts, question: prepared, maxCharacters: 9_000)
            guard packet.hasEvidence else { error = L10n.text("Для ответа нужны материалы в пределах просмотренного."); return }
            let response = try await model.assistant.respond(question: text, context: packet, history: snapshot.chat, localeIdentifier: localeIdentifier, preparedQuestion: prepared, aliases: snapshot.nameAliases ?? [])
            try Task.checkCancellation()
            guard activeRequestID == requestID, accountID == library.activeAccountID,
                  localeIdentifier == model.localeIdentifier, let current = library.entry(for: title.id),
                  current.progress == snapshot.progress, current.chat == snapshot.chat,
                  current.facts == snapshot.facts, current.episodes == snapshot.episodes else { return }
            var changed = current
            changed.chat.append(ChatTurn(role: .user, text: text))
            changed.chat.append(ChatTurn(role: .assistant, text: response.text, citations: response.citations))
            changed.chat = Array(changed.chat.suffix(80))
            changed.updatedAt = Date()
            library.update(changed)
            if let failure = library.lastError { error = failure }
            else if question.trimmingCharacters(in: .whitespacesAndNewlines) == text { question = "" }
        } catch is CancellationError {} catch {
            if activeRequestID == requestID { self.error = error.localizedDescription }
        }
    }
}
