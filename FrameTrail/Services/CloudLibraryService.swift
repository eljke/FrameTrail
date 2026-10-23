import Foundation
import FrameTrailCore

enum CloudLibraryError: LocalizedError {
    case invalidRecord
    case limitExceeded
    case changedDuringSync

    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "Сервер вернул некорректную запись библиотеки. Локальные данные сохранены."
        case .limitExceeded: return "Превышен лимит облачной библиотеки: 10 000 записей или 512 КБ на историю."
        case .changedDuringSync: return "Облачная запись изменилась во время синхронизации. Повтори синхронизацию для сравнения версий."
        }
    }
}

actor CloudLibraryService {
    private let config: SupabaseConfiguration
    private let http: HTTPClient

    init(config: SupabaseConfiguration, http: HTTPClient = .shared) {
        self.config = config
        self.http = http
    }

    func fetchAll(accessToken: String) async throws -> [CloudLibraryRecord] {
        var records: [CloudLibraryRecord] = []
        var cursor: String?
        for _ in 0..<3_334 {
            var query: [URLQueryItem] = [
                .init(name: "select", value: "media_id,payload,revision,deleted"),
                .init(name: "order", value: "media_id.asc"), .init(name: "limit", value: "3")
            ]
            if let cursor { query.append(.init(name: "media_id", value: "gt.\(cursor)")) }
            let url = try HTTPClient.url(config.projectURL.appendingPathComponent("rest/v1/library_items").absoluteString, query: query)
            let data = try await http.data(for: request(url: url, accessToken: accessToken))
            let page = try JSONDecoder().decode([RecordDTO].self, from: data).map { try $0.record() }
            guard page.count <= 3, page.allSatisfy({ cursor == nil || $0.mediaID > cursor! }),
                  Set(page.map(\.mediaID)).count == page.count else { throw CloudLibraryError.invalidRecord }
            records.append(contentsOf: page)
            guard records.count <= 10_000 else { throw CloudLibraryError.limitExceeded }
            if page.count < 3 { return records }
            cursor = page.last!.mediaID
        }
        throw CloudLibraryError.limitExceeded
    }

    func put(mediaID: String, item: CloudLibraryItem?, expectedRevision: Int64, accessToken: String) async throws -> CloudLibraryRecord? {
        let body = try JSONEncoder().encode(WriteBody(p_media_id: mediaID, p_payload: item, p_expected_revision: expectedRevision, p_deleted: item == nil))
        if let item, try JSONEncoder().encode(item).count > 512 * 1_024 { throw CloudLibraryError.limitExceeded }
        let url = config.projectURL.appendingPathComponent("rest/v1/rpc/put_library_item")
        let data = try await http.data(for: request(url: url, accessToken: accessToken, method: "POST", body: body))
        let rows = try JSONDecoder().decode([RecordDTO].self, from: data)
        guard rows.count <= 1 else { throw CloudLibraryError.invalidRecord }
        guard let row = rows.first else { return nil }
        let record = try row.record()
        guard record.mediaID == mediaID, record.payload == item, record.revision == expectedRevision + 1 else {
            throw CloudLibraryError.invalidRecord
        }
        return record
    }

    func deleteAccount(accessToken: String) async throws {
        let url = config.projectURL.appendingPathComponent("functions/v1/delete-account")
        _ = try await http.data(for: request(url: url, accessToken: accessToken, method: "DELETE"))
    }

    private func request(url: URL, accessToken: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = HTTPClient.request(url: url, bearer: accessToken, method: method, body: body)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        return request
    }

    private struct WriteBody: Encodable {
        let p_media_id: String
        let p_payload: CloudLibraryItem?
        let p_expected_revision: Int64
        let p_deleted: Bool

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(p_media_id, forKey: .p_media_id)
            try values.encode(p_payload, forKey: .p_payload)
            try values.encode(p_expected_revision, forKey: .p_expected_revision)
            try values.encode(p_deleted, forKey: .p_deleted)
        }
        enum CodingKeys: String, CodingKey { case p_media_id, p_payload, p_expected_revision, p_deleted }
    }

    private struct RecordDTO: Decodable {
        let media_id: String
        let payload: CloudLibraryItem?
        let revision: Int64
        let deleted: Bool

        func record() throws -> CloudLibraryRecord {
            let record = CloudLibraryRecord(mediaID: media_id, payload: payload, revision: revision, deleted: deleted)
            guard record.isValid else { throw CloudLibraryError.invalidRecord }
            return record
        }
    }
}
