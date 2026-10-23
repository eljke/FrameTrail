import Foundation

public struct EpisodeRatingPlan: Sendable {
    public let records: [Reflection]
    public let changedCount: Int

    public init(titleID: String, episodes: [Episode], watchedEpisodeIDs: Set<String>, records: [Reflection], rating: Int, season: Int? = nil, overwrite: Bool = false) {
        precondition((1...10).contains(rating))
        var result = records
        var count = 0
        var seen: Set<String> = []
        for episode in episodes where watchedEpisodeIDs.contains(episode.id) && (season == nil || episode.season == season) && seen.insert(episode.id).inserted {
            if let current = Reflection.latest(in: result, episodeID: episode.id) {
                guard (overwrite || current.rating == nil), current.rating != rating else { continue }
                let index = result.firstIndex { $0.id == current.id }!
                result[index].rating = rating
            } else {
                result.append(Reflection(titleID: titleID, rating: rating, episodeID: episode.id, episodeSeason: episode.season, episodeNumber: episode.number))
            }
            count += 1
        }
        self.records = result
        changedCount = count
    }
}
