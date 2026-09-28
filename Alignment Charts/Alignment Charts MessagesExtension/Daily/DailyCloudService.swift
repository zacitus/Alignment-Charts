import CloudKit
import Foundation

enum DailyError: LocalizedError {
    case expired, incomplete, invalid, accountChanged

    var errorDescription: String? {
        switch self {
        case .expired: return "The daily reset has passed. This chart can’t earn streak credit now."
        case .incomplete: return "This daily chart hasn’t been shared as complete yet."
        case .invalid: return "The daily record could not be verified. Please try again."
        case .accountChanged: return "Your iCloud account changed. Reopen the chart to claim credit."
        }
    }
}

/// Templates and completion receipts are public. Each person's claims are private.
/// Deterministic claim IDs make repeat taps and simultaneous devices idempotent.
final class DailyCloudService {
    static let shared = DailyCloudService()
    private let container = CKContainer(identifier: CloudKitChartService.containerID)
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    func accountID() async throws -> String {
        try await container.userRecordID().recordName
    }

    func templates(starting now: Date) async throws -> [DailyTemplate] {
        let ids = (0..<14).map { offset in
            CKRecord.ID(recordName: "daily-\(DailyCalendar.day(for: now.addingTimeInterval(Double(offset) * 86400)))")
        }
        let results = try await publicDB.records(for: ids)
        var templates: [DailyTemplate] = []
        for id in ids {
            guard let result = results[id] else { throw DailyError.invalid }
            do {
                let record = try result.get()
                guard let payload = record["payload"] as? String,
                      let template = try? JSONDecoder().decode(DailyTemplate.self, from: Data(payload.utf8)),
                      template.isValid, template.id == id.recordName else { throw DailyError.invalid }
                templates.append(template)
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return templates
    }

    /// Called only after a complete chart upload. Never changes an existing receipt.
    /// The server creationDate is the completion time, so later edits cannot erase it.
    func recordCompletion(_ chart: ChartState) async throws {
        guard let daily = chart.daily, chart.isComplete,
              DailyCalendar.includes(.now, in: daily.day) else { return }
        let id = CKRecord.ID(recordName: "completion-\(chart.id.uuidString)")
        if try await record(id, in: publicDB) != nil { return }
        let receipt = CKRecord(recordType: "DailyCompletion", recordID: id)
        receipt["day"] = daily.day
        receipt["templateID"] = daily.templateID
        receipt["chartID"] = chart.id.uuidString
        _ = try await createOnce(receipt, in: publicDB)
    }

    func claim(chartID: String, daily: DailyIdentity, account: String) async throws -> String {
        guard DailyCalendar.includes(.now, in: daily.day) else { throw DailyError.expired }
        guard let receipt = try await record(CKRecord.ID(recordName: "completion-\(chartID)"), in: publicDB),
              receipt["chartID"] as? String == chartID,
              receipt["day"] as? String == daily.day,
              receipt["templateID"] as? String == daily.templateID,
              let completedAt = receipt.creationDate,
              DailyCalendar.includes(completedAt, in: daily.day) else { throw DailyError.incomplete }
        guard try await accountID() == account else { throw DailyError.accountChanged }
        guard DailyCalendar.includes(.now, in: daily.day) else { throw DailyError.expired }
        let claim = CKRecord(recordType: "DailyClaim", recordID: CKRecord.ID(recordName: "claim-\(daily.day)"))
        claim["day"] = daily.day
        claim["chartID"] = chartID
        let saved = try await createOnce(claim, in: privateDB)
        // A request crossing midnight is not credit for either day. Never backdate a retry.
        guard let claimedAt = saved.creationDate, saved["day"] as? String == daily.day,
              DailyCalendar.includes(claimedAt, in: daily.day) else { throw DailyError.expired }
        guard try await accountID() == account else { throw DailyError.accountChanged }
        return daily.day
    }

    func claimedDays() async throws -> Set<String> {
        let query = CKQuery(recordType: "DailyClaim", predicate: NSPredicate(value: true))
        var page = try await privateDB.records(matching: query)
        var days = Set<String>()
        while true {
            for (_, result) in page.matchResults {
                let record = try result.get()
                if let day = record["day"] as? String, let date = record.creationDate,
                   record.recordID.recordName == "claim-\(day)", DailyCalendar.includes(date, in: day) {
                    days.insert(day)
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await privateDB.records(continuingMatchFrom: cursor)
        }
        return days
    }

    private func record(_ id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    private func createOnce(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        do {
            let (results, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            guard let result = results[record.recordID] else { throw DailyError.invalid }
            return try result.get()
        } catch let error as CKError where error.code == .serverRecordChanged {
            return try await database.record(for: record.recordID)
        } catch let error as CKError where error.code == .partialFailure {
            if let itemError = error.partialErrorsByItemID?[record.recordID] as? CKError,
               itemError.code == .serverRecordChanged {
                return try await database.record(for: record.recordID)
            }
            throw error.partialErrorsByItemID?[record.recordID] ?? error
        }
    }
}
