import Foundation

struct ChartSnapshot<Version> {
    let chart: ChartState
    let version: Version
}

enum ChartSyncError: LocalizedError {
    case recordChanged
    case busy
    case missingChart
    case invalidChart

    var errorDescription: String? {
        switch self {
        case .recordChanged, .busy: return "The chart is still being updated. Your draft is safe; try sharing again."
        case .missingChart: return "The shared chart is no longer available. Your draft is still saved on this device."
        case .invalidChart: return "The chart data could not be read safely. Your draft has been kept."
        }
    }
}

/// Keeps retries testable without CloudKit. Every attempt merges against the SAME
/// editing baseline, but commits using the freshly fetched server version.
enum ChartSync {
    static func save<Version>(
        local: ChartState,
        base: ChartState?,
        load: () async throws -> ChartSnapshot<Version>?,
        commit: (ChartState, Version?) async throws -> Void
    ) async throws -> ChartState {
        guard local.isValid, base?.isValid != false, base == nil || base?.id == local.id else {
            throw ChartSyncError.invalidChart
        }
        for _ in 0..<5 {
            try Task.checkCancellation()
            let snapshot = try await load()
            var result = local
            if let snapshot {
                guard snapshot.chart.isValid, snapshot.chart.id == local.id else { throw ChartSyncError.invalidChart }
                let review = ChartMergeReview(base: base, local: local, remote: snapshot.chart)
                let merge = review.merged()
                guard merge.conflicts.isEmpty else { throw review }
                result = merge.chart
            } else if base != nil {
                throw ChartSyncError.missingChart
            }
            result.updatedAt = .now
            do {
                try Task.checkCancellation()
                try await commit(result, snapshot?.version)
                return result
            } catch ChartSyncError.recordChanged {
                continue
            }
        }
        throw ChartSyncError.busy
    }
}
