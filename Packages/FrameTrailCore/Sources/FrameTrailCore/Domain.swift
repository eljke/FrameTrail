import Foundation

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case movie
    case series
}

public struct MediaTitle: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var originalTitle: String?
    public var kind: MediaKind
    public var year: Int?
    public var overview: String
    public var posterURL: URL?
    public var sourceURL: URL?
    public var provider: String
    public var providerID: String

    public init(
        id: String,
        title: String,
        originalTitle: String? = nil,
        kind: MediaKind,
        year: Int? = nil,
        overview: String = "",
        posterURL: URL? = nil,
        sourceURL: URL? = nil,
        provider: String,
        providerID: String
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.kind = kind
        self.year = year
        self.overview = overview
        self.posterURL = posterURL
        self.sourceURL = sourceURL
        self.provider = provider
        self.providerID = providerID
    }
}

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var season: Int
    public var number: Int
    public var name: String
    public var summary: String
    public var sourceURL: URL?

    public init(
        id: String,
        season: Int,
        number: Int,
        name: String,
        summary: String = "",
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.season = season
        self.number = number
        self.name = name
        self.summary = summary
        self.sourceURL = sourceURL
    }
}

public struct WatchProgress: Codable, Sendable, Hashable {
    public var finished: Bool
    public var watchedEpisodeIDs: Set<String>
    public var currentSeason: Int?
    public var currentEpisode: Int?

    public init(
        finished: Bool = false,
        watchedEpisodeIDs: Set<String> = [],
        currentSeason: Int? = nil,
        currentEpisode: Int? = nil
    ) {
        self.finished = finished
        self.watchedEpisodeIDs = watchedEpisodeIDs
        self.currentSeason = currentSeason
        self.currentEpisode = currentEpisode
    }
}

public struct StoryFact: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var text: String
    public var episodeID: String?
    public var sourceURL: URL?
    public var kind: String
    public var titleID: String?

    public init(
        id: String,
        text: String,
        episodeID: String? = nil,
        sourceURL: URL? = nil,
        kind: String = "event",
        titleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.episodeID = episodeID
        self.sourceURL = sourceURL
        self.kind = kind
        self.titleID = titleID
    }
}

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct ChatTurn: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct Reflection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var titleID: String
    public var summary: String
    public var liked: [String]
    public var questions: [String]
    public var rating: Int?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        titleID: String,
        summary: String = "",
        liked: [String] = [],
        questions: [String] = [],
        rating: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.titleID = titleID
        self.summary = summary
        self.liked = liked
        self.questions = questions
        self.rating = rating
        self.createdAt = createdAt
    }
}
