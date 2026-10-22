import Foundation

public struct GroundedContext: Codable, Sendable {
    public var text: String
    public var evidence: [StoryFact]
    public var coverage: String
    public var allowedEpisodeIDs: Set<String>
    public var titleName: String
    public var scopeDescription: String

    public var hasEvidence: Bool { !evidence.isEmpty }

    public init(
        text: String,
        evidence: [StoryFact],
        coverage: String,
        allowedEpisodeIDs: Set<String>,
        titleName: String = "",
        scopeDescription: String = ""
    ) {
        self.text = text
        self.evidence = evidence
        self.coverage = coverage
        self.allowedEpisodeIDs = allowedEpisodeIDs
        self.titleName = titleName
        self.scopeDescription = scopeDescription
    }
}

/// Filters source material before retrieval. A model's own knowledge still needs
/// independent handling; this filter only guarantees the scope of supplied evidence.
/// A fact without titleID is assumed to be scoped to the supplied title by its caller.
/// Importers should assign that scope before combining records from different titles.
public enum SpoilerContextBuilder {
    public static func build(
        title: MediaTitle,
        episodes: [Episode],
        progress: WatchProgress,
        facts: [StoryFact],
        question: String,
        maxCharacters: Int = 12_000
    ) -> GroundedContext {
        let budget = max(0, maxCharacters)
        let allowedIDs = title.kind == .series
            ? progress.watchedEpisodeIDs.intersection(Set(episodes.map(\.id)))
            : Set<String>()
        var candidates = facts.filter { fact in
            guard fact.titleID == nil || fact.titleID == title.id,
                  !fact.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            switch title.kind {
            case .movie:
                return progress.finished && fact.episodeID == nil
            case .series:
                return fact.episodeID.map(allowedIDs.contains) == true
            }
        }

        switch title.kind {
        case .movie where progress.finished:
            if !title.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                candidates.append(StoryFact(
                    id: "movie:\(title.id):overview",
                    text: title.overview,
                    sourceURL: title.sourceURL,
                    kind: "overview",
                    titleID: title.id
                ))
            }
        case .series:
            for episode in episodes.sorted(by: episodeOrder) where allowedIDs.contains(episode.id) {
                guard !episode.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                candidates.append(StoryFact(
                    id: "episode:\(episode.id):summary",
                    text: "S\(episode.season)E\(episode.number): \(episode.summary)",
                    episodeID: episode.id,
                    sourceURL: episode.sourceURL,
                    kind: "summary",
                    titleID: title.id
                ))
            }
        default:
            break
        }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        let queryTerms = terms(in: question)
        var scored: [(offset: Int, fact: StoryFact, score: Int)] = []
        for (offset, fact) in candidates.enumerated() {
            scored.append((offset: offset, fact: fact, score: relevance(fact.text, queryTerms: queryTerms)))
        }
        scored.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.offset < rhs.offset }
            return lhs.score > rhs.score
        }
        let ranked: [StoryFact] = scored.map { $0.fact }

        let scope = title.kind == .movie
            ? (progress.finished ? "Фильм просмотрен. Продолжения не входят в контекст." : "Фильм ещё не просмотрен.")
            : "Только отмеченные просмотренными серии. Остальные серии и продолжения исключены."
        let header = "Название: \(title.title)\nГраница: \(scope)"
        var text = String(header.prefix(budget))
        var selected: [StoryFact] = []

        for fact in ranked {
            let label = "\n\n[\(fact.id)] "
            let available = budget - text.count - label.count
            guard available > 0 else { continue }
            let clippedText = String(fact.text.prefix(available))
            guard !clippedText.isEmpty else { continue }
            var selectedFact = fact
            selectedFact.text = clippedText
            selected.append(selectedFact)
            text += label + clippedText
        }

        let coverage: String
        if selected.isEmpty {
            coverage = "Нет доступных материалов в выбранных границах просмотра."
        } else if selected.count < ranked.count || selected.contains(where: { selectedFact in
            candidates.contains { $0.id == selectedFact.id && $0.text.count > selectedFact.text.count }
        }) {
            coverage = "Частичный контекст: \(selected.count) источников; часть материалов не вошла в лимит."
        } else {
            coverage = "Доступно источников: \(selected.count). Полнота зависит от исходных материалов."
        }
        let scopeDescription: String
        if title.kind == .movie {
            scopeDescription = progress.finished ? "Completed movie. Sequels are excluded." : "Unfinished movie. Plot evidence is unavailable."
        } else {
            scopeDescription = "Only \(allowedIDs.count) explicitly completed episodes are allowed. Evidence is already filtered by episode ID. "
                + "Unwatched episodes, sequels and the global series plot are excluded."
        }
        return GroundedContext(
            text: text,
            evidence: selected,
            coverage: coverage,
            allowedEpisodeIDs: allowedIDs,
            titleName: title.title,
            scopeDescription: scopeDescription
        )
    }

    private static func episodeOrder(_ lhs: Episode, _ rhs: Episode) -> Bool {
        if lhs.season != rhs.season { return lhs.season < rhs.season }
        if lhs.number != rhs.number { return lhs.number < rhs.number }
        return lhs.id < rhs.id
    }

    private static func terms(in question: String) -> Set<String> {
        let stopWords: Set<String> = [
            "как", "что", "кто", "это", "почему", "зачем", "когда", "где", "мне", "про", "его", "она", "они",
            "the", "and", "what", "who", "why", "how", "does", "did", "was", "this", "that", "with", "about"
        ]
        return Set(normalized(question).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    private static func relevance(_ text: String, queryTerms: Set<String>) -> Int {
        let haystack = normalized(text)
        return queryTerms.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
