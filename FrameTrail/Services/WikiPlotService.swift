import Foundation
import FrameTrailCore

actor WikiPlotService {
    private let http: HTTPClient

    init(http: HTTPClient = .shared) { self.http = http }

    func plot(for title: MediaTitle, finished: Bool) async throws -> [StoryFact] {
        guard title.kind == .movie, finished else { throw ServiceError.unfinishedTitle }
        let name = title.originalTitle ?? title.title
        let search = "\"\(String(name.prefix(150)))\" \(title.year.map(String.init) ?? "") film"
        let url = try HTTPClient.url("https://en.wikipedia.org/w/api.php", query: [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"),
            .init(name: "srsearch", value: search), .init(name: "srlimit", value: "5"),
            .init(name: "srnamespace", value: "0"), .init(name: "format", value: "json")
        ])
        let result = try await http.decode(WikiSearch.self, request: HTTPClient.request(url: url))
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { throw ServiceError.noPlot }
        let candidates = result.query.search.filter {
            let candidate = normalized($0.title)
            return candidate == normalizedName || candidate == "\(normalizedName) film"
                || title.year.map { candidate.hasPrefix("\(normalizedName) \($0) ") } == true
        }
        guard let match = candidates.max(by: { score($0.title, year: title.year) < score($1.title, year: title.year) }) else { throw ServiceError.noPlot }
        let sectionsURL = try parseURL(pageID: match.pageid, properties: "sections")
        let sections = try await http.decode(WikiSections.self, request: HTTPClient.request(url: sectionsURL))
        guard let plotSection = sections.parse.sections.first(where: { ["plot", "synopsis", "plot summary"].contains(normalized($0.line)) }) else {
            throw ServiceError.noPlot
        }
        let textURL = try parseURL(pageID: match.pageid, properties: "text|revid", section: plotSection.index)
        let page = try await http.decode(WikiText.self, request: HTTPClient.request(url: textURL))
        let text = String(SourceText.plain(page.parse.text.html).prefix(24_000))
        guard !text.isEmpty else { throw ServiceError.noPlot }
        let source = try HTTPClient.url("https://en.wikipedia.org/w/index.php", query: [.init(name: "oldid", value: String(page.parse.revid))])
        return chunks(text, limit: 2_000).enumerated().map { index, paragraph in
            StoryFact(id: "wikipedia:\(match.pageid):\(page.parse.revid):\(index)", text: paragraph,
                      sourceURL: source, kind: "plot", titleID: title.id)
        }
    }

    private func parseURL(pageID: Int, properties: String, section: String? = nil) throws -> URL {
        var query: [URLQueryItem] = [
            .init(name: "action", value: "parse"), .init(name: "pageid", value: String(pageID)),
            .init(name: "prop", value: properties), .init(name: "format", value: "json"),
            .init(name: "disableeditsection", value: "1"), .init(name: "disabletoc", value: "1")
        ]
        if let section { query.append(.init(name: "section", value: section)) }
        return try HTTPClient.url("https://en.wikipedia.org/w/api.php", query: query)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func score(_ name: String, year: Int?) -> Int {
        (name.contains("film") ? 1 : 0) + ((year.map { name.contains(String($0)) }) == true ? 3 : 0)
    }

    private func chunks(_ text: String, limit: Int) -> [String] {
        var remaining = text[...]
        var result: [String] = []
        while !remaining.isEmpty {
            let prefix = remaining.prefix(limit)
            let boundary = prefix.lastIndex(of: "\n") ?? prefix.lastIndex(of: " ") ?? prefix.endIndex
            let end = boundary == prefix.startIndex ? prefix.endIndex : boundary
            result.append(String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            remaining = remaining[end...].drop(while: { $0.isWhitespace })
        }
        return result.filter { !$0.isEmpty }
    }
}

private struct WikiSearch: Decodable, Sendable {
    let query: Query
    struct Query: Decodable, Sendable { let search: [Hit] }
    struct Hit: Decodable, Sendable { let pageid: Int; let title: String }
}
private struct WikiSections: Decodable, Sendable {
    let parse: Page
    struct Page: Decodable, Sendable { let sections: [Section] }
    struct Section: Decodable, Sendable { let line: String; let index: String }
}
private struct WikiText: Decodable, Sendable {
    let parse: Page
    struct Page: Decodable, Sendable { let text: Content; let revid: Int }
    struct Content: Decodable, Sendable {
        let html: String
        enum CodingKeys: String, CodingKey { case html = "*" }
    }
}
