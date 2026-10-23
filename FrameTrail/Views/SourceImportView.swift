import SwiftUI
import UniformTypeIdentifiers
import FrameTrailCore

struct SourceImportView: View {
    let title: MediaTitle
    let episodes: [Episode]
    var initialEpisodeID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var text = ""
    @State private var episodeID = ""
    @State private var customSeason = 1
    @State private var customEpisode = 1
    @State private var showFilePicker = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Область материала")) {
                    Text(title.title)
                    if title.kind == .series {
                        Picker(L10n.text("Серия"), selection: $episodeID) {
                            Text(L10n.text("Своя серия")).tag("")
                            ForEach(episodes) { episode in Text("S\(episode.season) E\(episode.number)").tag(episode.id) }
                        }
                        if episodeID.isEmpty {
                            Stepper(L10n.text("Сезон %@", String(describing: customSeason)), value: $customSeason, in: 0...200)
                            Stepper(L10n.text("Серия %@", String(describing: customEpisode)), value: $customEpisode, in: 1...2_000)
                        }
                    }
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 220).font(.body)
                        .accessibilityIdentifier("sourceText")
                        .accessibilityLabel(L10n.text("Текст материала"))
                        .onChange(of: text) { _, value in if value.count > 40_000 { text = String(value.prefix(40_000)) } }
                    Button { showFilePicker = true } label: { Label(L10n.text("Открыть TXT, SRT или VTT"), systemImage: "doc") }
                    Text(L10n.text("До 40 000 символов. Субтитры преобразуются в текст. Материал станет доступен помощнику только после отметки о просмотре соответствующего фильма или серии."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(L10n.text("Твой источник")) }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Материалы"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Сохранить")) { save() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveSource") }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.plainText, .text, .data]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (attributes.fileSize ?? 0) <= 512 * 1024 else { throw SourceImportError.tooLarge }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= 512 * 1024, let imported = String(data: data, encoding: .utf8) else { throw SourceImportError.invalidText }
                    if ["srt", "vtt"].contains(url.pathExtension.lowercased()) {
                        let cues = SubtitleParser.parse(imported)
                        guard !cues.isEmpty else { throw SourceImportError.invalidSubtitles }
                        text = String(cues.map(\.text).joined(separator: "\n").prefix(40_000))
                    } else { text = String(imported.prefix(40_000)) }
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            .onChange(of: library.activeAccountID) { _, _ in dismiss() }
            .onAppear {
                if let initialEpisodeID, episodes.contains(where: { $0.id == initialEpisodeID }) { episodeID = initialEpisodeID }
            }
        }
    }

    private func save() {
        var entry = library.entry(for: title.id) ?? LibraryEntry(title: title)
        for episode in episodes where !entry.episodes.contains(where: { $0.id == episode.id }) {
            entry.episodes.append(episode)
        }
        var scope: String?
        if title.kind == .series {
            if episodeID.isEmpty {
                let matching = entry.episodes.filter { $0.season == customSeason && $0.number == customEpisode }
                if let existing = matching.first(where: { !$0.id.hasPrefix("local:") }) ?? matching.first {
                    scope = existing.id
                } else {
                    let id = "local:\(title.id):\(customSeason):\(customEpisode)"
                    entry.episodes.append(Episode(id: id, season: customSeason, number: customEpisode, name: L10n.text("Серия %@", String(describing: customEpisode))))
                    scope = id
                }
            } else {
                guard entry.episodes.contains(where: { $0.id == episodeID }) else {
                    error = L10n.text("Выбранная серия больше недоступна. Выбери её заново.")
                    return
                }
                scope = episodeID
            }
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = stride(from: 0, to: body.count, by: 1_500).map { offset in String(body.dropFirst(offset).prefix(1_500)) }
        let sourceID = UUID().uuidString
        for (index, chunk) in chunks.enumerated() {
            entry.facts.append(StoryFact(id: "user:\(sourceID):\(index)", text: chunk, episodeID: scope, kind: "user-source", titleID: title.id))
        }
        entry.updatedAt = Date()
        library.update(entry)
        if library.lastError == nil { dismiss() }
        else { error = library.lastError }
    }
}

private enum SourceImportError: LocalizedError {
    case tooLarge, invalidText, invalidSubtitles
    var errorDescription: String? {
        switch self {
        case .tooLarge: return L10n.text("Файл больше 512 КБ. Выбери текст одной серии или сократи материал.")
        case .invalidText: return L10n.text("Нужен текстовый файл в UTF-8.")
        case .invalidSubtitles: return L10n.text("Не удалось прочитать временные метки субтитров.")
        }
    }
}
