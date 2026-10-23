import Foundation

public struct ReflectionCompilation: Sendable {
    public let batches: [String]
    public let episodeCount: Int
    public let shortened: Bool

    public init(records: [Reflection], watchedEpisodeIDs: Set<String>) {
        let eligible: [Reflection] = records.filter { record in record.episodeID.map(watchedEpisodeIDs.contains) == true }
        let groups = Dictionary(grouping: eligible, by: { $0.episodeID! })
        var latest: [Reflection] = groups.values.compactMap {
            Reflection.latest(in: $0, episodeID: $0[0].episodeID)
        }
        latest.sort {
            if $0.episodeSeason != $1.episodeSeason { return ($0.episodeSeason ?? 0) < ($1.episodeSeason ?? 0) }
            if $0.episodeNumber != $1.episodeNumber { return ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
            return $0.id.uuidString < $1.id.uuidString
        }
        episodeCount = latest.count
        var packets: [String] = []
        var packet = ""
        var didShorten = false
        for record in latest {
            let parts = [record.summary, record.allLiked.joined(separator: "; "), record.allDisliked.joined(separator: "; "), record.questions.joined(separator: "; ")]
            if parts.contains(where: { $0.count > 180 }) { didShorten = true }
            let headings = ["Summary", "Liked", "Disliked", "Open questions"]
            let note = zip(headings, parts).map { "\($0): \(String($1.prefix(180)))" }.joined(separator: "\n")
            let label = "S\(record.episodeSeason ?? 0) E\(record.episodeNumber ?? 0), rating \(record.rating.map(String.init) ?? "not rated")/10"
            let item = label + "\n" + String(note.prefix(800)) + "\n\n"
            if !packet.isEmpty && packet.count + item.count > 5_000 { packets.append(packet); packet = "" }
            packet += item
        }
        if !packet.isEmpty { packets.append(packet) }
        batches = packets
        shortened = didShorten
    }
}
