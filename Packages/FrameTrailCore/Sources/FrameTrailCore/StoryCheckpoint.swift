import Foundation

public struct StoryCheckpoint: Sendable {
    public let episodes: [Episode]
    public let reviews: [Reflection]
    public let context: GroundedContext

    public init(title: MediaTitle, episodes: [Episode], progress: WatchProgress, facts: [StoryFact], records: [Reflection], through episodeID: String) {
        let selected = episodes.first { $0.id == episodeID && progress.watchedEpisodeIDs.contains($0.id) }
        let allowed = episodes.filter { episode in
            guard title.kind == .series, let selected, progress.watchedEpisodeIDs.contains(episode.id) else { return false }
            return episode.season < selected.season || (episode.season == selected.season && episode.number <= selected.number)
        }.sorted { ($0.season, $0.number, $0.id) < ($1.season, $1.number, $1.id) }
        self.episodes = allowed
        let ownRecords = records.filter { $0.titleID == title.id }
        self.reviews = allowed.compactMap { episode in
            Reflection.latest(in: ownRecords, episodeID: episode.id)
        }.filter(\.hasContent)
        self.context = SpoilerContextBuilder.build(title: title, episodes: allowed,
            progress: WatchProgress(watchedEpisodeIDs: Set(allowed.map(\.id))), facts: facts,
            question: "", maxCharacters: 9_000)
    }
}
