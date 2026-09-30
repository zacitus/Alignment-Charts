import Foundation
import CloudKit

enum ChartServiceError: LocalizedError {
    case malformedRecord
    case missingImage

    var errorDescription: String? {
        switch self {
        case .malformedRecord: return "The chart record is missing its data."
        case .missingImage: return "A chart photo could not be loaded. Your draft is safe; please try again."
        }
    }
}

/// Syncs charts through the CloudKit public database. Records are addressed
/// directly by the chart's UUID, so no queryable indexes are required.
/// Moderation controls and known gaps are documented in Alignment Charts/MODERATION.md.
final class CloudKitChartService {
    static let shared = CloudKitChartService()

    static let containerID = "iCloud.name.zachsmith.Alignment-Charts"
    private static let chartRecordType = "Chart"
    private static let imageRecordType = "ChartImage"
    private static let payloadKey = "payload"
    private static let imageAssetKey = "asset"

    private let database = CKContainer(identifier: CloudKitChartService.containerID).publicCloudDatabase

    #if DEBUG
    /// Creates the fixed development schema without leaving test records behind.
    /// Release builds never execute or include this bootstrap path.
    func initializeDevelopmentSchema() async throws {
        let chartID = CKRecord.ID(recordName: "alignment-chart-schema-chart")
        let imageID = CKRecord.ID(recordName: "alignment-chart-schema-image")
        let chartRecord = CKRecord(recordType: Self.chartRecordType, recordID: chartID)
        let payload = try JSONEncoder().encode(ChartState())
        chartRecord[Self.payloadKey] = String(decoding: payload, as: UTF8.self)

        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alignment-chart-schema-asset.txt")
        try Data("schema".utf8).write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        let imageRecord = CKRecord(recordType: Self.imageRecordType, recordID: imageID)
        imageRecord[Self.imageAssetKey] = CKAsset(fileURL: assetURL)

        let (saveResults, _) = try await database.modifyRecords(
            saving: [chartRecord, imageRecord],
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
        for (_, result) in saveResults { _ = try result.get() }

        _ = try await database.modifyRecords(
            saving: [],
            deleting: [chartID, imageID],
            savePolicy: .allKeys,
            atomically: false
        )
    }
    #endif

    func upload(_ chart: ChartState, base: ChartState?) async throws -> ChartState {
        let recordID = CKRecord.ID(recordName: chart.id.uuidString)
        do {
            return try await ChartSync.save(local: chart, base: base) { () -> ChartSnapshot<CKRecord>? in
                guard let record = try await self.recordIfPresent(recordID) else { return nil }
                return ChartSnapshot(chart: try self.decode(record), version: record)
            } commit: { merged, version in
                // Public database writes aren't a multi-record transaction. Finish
                // immutable assets FIRST, then publish their references in one CAS save.
                try await self.prepareImages(cells: merged.cells, chartID: merged.id)
                try Task.checkCancellation()
                let record = version ?? CKRecord(recordType: Self.chartRecordType, recordID: recordID)
                var merged = merged
                // The published identity is immutable, including when an older client
                // re-encodes the payload without knowing about daily templates.
                if let version { merged.daily = try self.decode(version).daily }
                let payload = try JSONEncoder().encode(merged)
                record[Self.payloadKey] = String(decoding: payload, as: UTF8.self)
                if let daily = merged.daily {
                    record["dailyDay"] = daily.day
                    record["dailyTemplateID"] = daily.templateID
                }
                do {
                    try await self.save(record)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    throw ChartSyncError.recordChanged
                }
            }
        } catch let review as ChartMergeReview {
            // Download both alternatives for the conflict comparison without
            // changing any references or overwriting a locally replaced photo.
            try await downloadImages(cells: review.remote.cells, chartID: review.remote.id)
            throw review
        }
    }

    func fetchChart(id: String) async throws -> ChartState {
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        let chart = try decode(record)
        try await downloadImages(cells: chart.cells, chartID: chart.id)
        return chart
    }

    /// Tier upload mirrors the grid's `ChartSync.save`: three-way merge against
    /// the editing base, CAS commit, and a `TierMergeReview` on conflicts.
    /// Last-writer-wins is gone: a local tier never silently overwrites a
    /// co-editor's tier. On `.serverRecordChanged` the loop refetches and
    /// re-merges, up to 5 attempts, then throws `ChartSyncError.busy`.
    func uploadTier(_ tier: TierState, base: TierState?) async throws -> TierState {
        guard tier.isValid, base?.isValid != false, base == nil || base?.id == tier.id else {
            throw ChartSyncError.invalidChart
        }
        let recordID = CKRecord.ID(recordName: tier.id.uuidString)
        for _ in 0..<5 {
            try Task.checkCancellation()
            let version = try await self.recordIfPresent(recordID)
            var result = tier
            if let version {
                let remote = try decodeTier(version)
                let review = TierMergeReview(base: base, local: tier, remote: remote)
                let merge = review.merged()
                guard merge.conflicts.isEmpty else {
                    // Cache the remote images before the review UI shows them,
                    // mirroring the grid's upload(_:base:) conflict path. Best
                    // effort: a failed download must not mask the review
                    // itself; missing art renders as a placeholder.
                    try? await self.downloadImages(
                        cells: remote.tiers.flatMap { $0.items } + remote.unranked,
                        chartID: remote.id)
                    throw review
                }
                result = merge.tier
            } else if base != nil {
                // Someone deleted the record while this device was editing.
                throw ChartSyncError.missingChart
            }
            result.updatedAt = .now
            // Backstop only: the merge assembles a valid chart (duplicates are
            // impossible by construction, tier count goes to review, capacity
            // spills to unranked). Never let an invalid chart reach the server.
            guard result.isValid else { throw ChartSyncError.invalidChart }
            let tierCells = result.tiers.flatMap { $0.items } + result.unranked
            try await self.prepareImages(cells: tierCells, chartID: result.id)
            try Task.checkCancellation()
            let payload = try JSONEncoder().encode(ChartContent.tier(result))
            let record = version ?? CKRecord(recordType: Self.chartRecordType, recordID: recordID)
            record[Self.payloadKey] = String(decoding: payload, as: UTF8.self)
            do {
                try await self.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
            return result
        }
        throw ChartSyncError.busy
    }

    func fetchTierChart(id: String) async throws -> TierState {
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        let tier = try decodeTier(record)
        try await downloadImages(cells: tier.tiers.flatMap { $0.items } + tier.unranked, chartID: tier.id)
        return tier
    }

    private func decode(_ record: CKRecord) throws -> ChartState {
        guard let json = record[Self.payloadKey] as? String else { throw ChartServiceError.malformedRecord }
        var chart = try JSONDecoder().decode(ChartState.self, from: Data(json.utf8))
        if let day = record["dailyDay"] as? String, let templateID = record["dailyTemplateID"] as? String {
            chart.daily = DailyIdentity(day: day, templateID: templateID)
        }
        guard chart.isValid, chart.id.uuidString == record.recordID.recordName else {
            throw ChartSyncError.invalidChart
        }
        return chart
    }

    private func decodeTier(_ record: CKRecord) throws -> TierState {
        guard let json = record[Self.payloadKey] as? String else { throw ChartServiceError.malformedRecord }
        let content = try JSONDecoder().decode(ChartContent.self, from: Data(json.utf8))
        guard case .tier(let tier) = content else { throw ChartServiceError.malformedRecord }
        guard tier.isValid, tier.id.uuidString == record.recordID.recordName else {
            throw ChartSyncError.invalidChart
        }
        return tier
    }

    private func recordIfPresent(_ id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        // Network, account, and permission errors must never be treated as "new chart".
    }

    private func save(_ record: CKRecord) async throws {
        do {
            let (results, _) = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false
            )
            guard let result = results[record.recordID] else { throw ChartServiceError.malformedRecord }
            _ = try result.get()
        } catch let error as CKError where error.code == .partialFailure {
            throw error.partialErrorsByItemID?[record.recordID] ?? error
        }
    }

    private func fetchImageRecords(_ cells: [ChartCell], chartID: UUID) async throws -> [CKRecord.ID: CKRecord] {
        let ids = Set(cells.map { imageRecordID(chartID: chartID, imageID: $0.imageStorageID) })
        guard !ids.isEmpty else { return [:] }
        let results = try await database.records(for: Array(ids))
        var records: [CKRecord.ID: CKRecord] = [:]
        for id in ids {
            guard let result = results[id] else { throw ChartServiceError.missingImage }
            do {
                records[id] = try result.get()
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return records
    }

    private func prepareImages(cells allCells: [ChartCell], chartID: UUID) async throws {
        let cells = allCells.filter(\.hasImage)
        let existing = try await fetchImageRecords(cells, chartID: chartID)
        var uploads: [CKRecord.ID: CKRecord] = [:]
        for cell in cells {
            try Task.checkCancellation()
            let id = imageRecordID(chartID: chartID, imageID: cell.imageStorageID)
            if let record = existing[id] {
                try cacheImage(record, cell: cell)
                continue
            }
            let fileURL = ImageStore.url(for: cell.imageStorageID)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ChartServiceError.missingImage }
            let image = CKRecord(recordType: Self.imageRecordType, recordID: id)
            image[Self.imageAssetKey] = CKAsset(fileURL: fileURL)
            uploads[id] = image
        }
        if !uploads.isEmpty {
            let (results, _) = try await database.modifyRecords(
                saving: Array(uploads.values), deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false
            )
            for cell in cells {
                let id = imageRecordID(chartID: chartID, imageID: cell.imageStorageID)
                guard uploads[id] != nil else { continue }
                guard let result = results[id] else { throw ChartServiceError.missingImage }
                do {
                    _ = try result.get()
                } catch let error as CKError where error.code == .serverRecordChanged {
                    // A retry/device uploaded this immutable ID first. Never overwrite it.
                    guard let record = try await recordIfPresent(id) else { throw error }
                    try cacheImage(record, cell: cell)
                }
            }
        }
        // Keep old assets: another editor's baseline or unresolved conflict may need them.
    }

    private func downloadImages(cells allCells: [ChartCell], chartID: UUID) async throws {
        let cells = allCells.filter { cell in
            cell.hasImage && (cell.imageID == nil || !FileManager.default.fileExists(atPath: ImageStore.url(for: cell.imageStorageID).path))
        }
        let records = try await fetchImageRecords(cells, chartID: chartID)
        for cell in cells {
            guard let record = records[imageRecordID(chartID: chartID, imageID: cell.imageStorageID)] else {
                throw ChartServiceError.missingImage
            }
            try cacheImage(record, cell: cell)
        }
    }

    private func cacheImage(_ record: CKRecord, cell: ChartCell) throws {
        guard let asset = record[Self.imageAssetKey] as? CKAsset, let fileURL = asset.fileURL else {
            throw ChartServiceError.missingImage
        }
        if cell.imageID == nil || !FileManager.default.fileExists(atPath: ImageStore.url(for: cell.imageStorageID).path) {
            try ImageStore.importFile(fileURL, for: cell.imageStorageID)
        }
    }

    private func imageRecordID(chartID: UUID, imageID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(chartID.uuidString)_\(imageID.uuidString)")
    }
}
