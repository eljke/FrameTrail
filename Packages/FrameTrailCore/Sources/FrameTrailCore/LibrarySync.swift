import Foundation

public struct CloudLibraryItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String { title.id }
    public var title: MediaTitle
    public var progress: WatchProgress
    public var reflections: [Reflection]

    public init(title: MediaTitle, progress: WatchProgress, reflections: [Reflection]) {
        self.title = title
        self.progress = progress
        self.reflections = reflections
    }
}

public struct CloudLibraryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { mediaID }
    public var mediaID: String
    public var payload: CloudLibraryItem?
    public var revision: Int64
    public var deleted: Bool

    public init(mediaID: String, payload: CloudLibraryItem?, revision: Int64, deleted: Bool) {
        self.mediaID = mediaID
        self.payload = payload
        self.revision = revision
        self.deleted = deleted
    }

    public var isValid: Bool {
        !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mediaID.count <= 256 && mediaID.rangeOfCharacter(from: .controlCharacters) == nil
            && revision > 0 && (deleted ? payload == nil : payload?.id == mediaID)
    }
}

public struct LibrarySyncBaseline: Codable, Hashable, Sendable {
    public var records: [String: CloudLibraryRecord]

    public init(records: [String: CloudLibraryRecord] = [:]) {
        self.records = records
    }
}

public struct CloudLibraryUpload: Identifiable, Hashable, Sendable {
    public var id: String { mediaID }
    public var mediaID: String
    public var payload: CloudLibraryItem?
    public var expectedRevision: Int64
    public var deleted: Bool { payload == nil }

    public init(mediaID: String, payload: CloudLibraryItem?, expectedRevision: Int64) {
        self.mediaID = mediaID
        self.payload = payload
        self.expectedRevision = expectedRevision
    }
}

public struct LibrarySyncConflict: Identifiable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case concurrentChanges
        case initialDivergence
        case remoteMissing
        case invalidRecord
        case duplicateLocal
        case duplicateRemote
    }

    public var id: String { mediaID }
    public var mediaID: String
    public var local: CloudLibraryItem?
    public var remote: CloudLibraryRecord?
    public var baseline: CloudLibraryRecord?
    public var reason: Reason
}

public struct LibrarySyncPlan: Sendable {
    public var uploads: [CloudLibraryUpload]
    public var applies: [CloudLibraryRecord]
    public var conflicts: [LibrarySyncConflict]
    public var nextBaseline: LibrarySyncBaseline
}

public enum LibrarySyncPlanner {
    public static func plan(
        local: [CloudLibraryItem],
        remote: [CloudLibraryRecord],
        baseline: LibrarySyncBaseline
    ) -> LibrarySyncPlan {
        let localGroups = Dictionary(grouping: local, by: \.id)
        let remoteGroups = Dictionary(grouping: remote, by: \.mediaID)
        let ids = Set(localGroups.keys).union(remoteGroups.keys).union(baseline.records.keys)
        var result = LibrarySyncPlan(uploads: [], applies: [], conflicts: [], nextBaseline: baseline)

        for id in ids.sorted() {
            let localItem = localGroups[id]?.first
            let remoteRecord = remoteGroups[id]?.first
            let previous = baseline.records[id]
            let conflict: LibrarySyncConflict.Reason?
            if (localGroups[id]?.count ?? 0) > 1 {
                conflict = .duplicateLocal
            } else if (remoteGroups[id]?.count ?? 0) > 1 {
                conflict = .duplicateRemote
            } else if remoteRecord.map({ !$0.isValid }) == true
                || previous.map({ !$0.isValid || $0.mediaID != id }) == true {
                conflict = .invalidRecord
            } else if let previous, let remoteRecord,
                      remoteRecord.revision < previous.revision
                        || (remoteRecord.revision == previous.revision && remoteRecord != previous) {
                conflict = .invalidRecord
            } else if previous != nil && remoteRecord == nil {
                conflict = .remoteMissing
            } else {
                conflict = nil
            }
            if let conflict {
                result.conflicts.append(LibrarySyncConflict(
                    mediaID: id, local: localItem, remote: remoteRecord, baseline: previous, reason: conflict
                ))
                continue
            }

            guard let remoteRecord else {
                if let localItem {
                    result.uploads.append(CloudLibraryUpload(mediaID: id, payload: localItem, expectedRevision: 0))
                }
                continue
            }
            let remoteItem = remoteRecord.payload
            if localItem == remoteItem {
                result.nextBaseline.records[id] = remoteRecord
                continue
            }
            guard let previous else {
                if localItem == nil {
                    result.applies.append(remoteRecord)
                    result.nextBaseline.records[id] = remoteRecord
                } else {
                    result.conflicts.append(LibrarySyncConflict(
                        mediaID: id, local: localItem, remote: remoteRecord, baseline: nil, reason: .initialDivergence
                    ))
                }
                continue
            }

            let localChanged = localItem != previous.payload
            let remoteChanged = remoteItem != previous.payload
            if localChanged && remoteChanged {
                result.conflicts.append(LibrarySyncConflict(
                    mediaID: id, local: localItem, remote: remoteRecord, baseline: previous, reason: .concurrentChanges
                ))
            } else if localChanged {
                result.uploads.append(CloudLibraryUpload(
                    mediaID: id, payload: localItem, expectedRevision: remoteRecord.revision
                ))
            } else if remoteChanged {
                result.applies.append(remoteRecord)
                result.nextBaseline.records[id] = remoteRecord
            }
        }
        return result
    }
}
