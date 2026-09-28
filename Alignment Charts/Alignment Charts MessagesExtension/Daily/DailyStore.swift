import CloudKit
import Combine
import Foundation

@MainActor
final class DailyStore: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var template: DailyTemplate?
    @Published private(set) var days = Set<String>()
    @Published private(set) var status: String?
    @Published private(set) var templateStatus: String?
    @Published private(set) var isClaiming = false
    @Published private(set) var isRefreshing = false
    private var account: String?
    private var generation = UUID()
    private let catalog = DailyTemplate.bundled()
    private var templates: [String: DailyTemplate] = [:]
    private var observers = Set<AnyCancellable>()
    private let service = DailyCloudService.shared

    var summary: StreakSummary { StreakSummary(days: days, now: now) }
    var reset: Date { DailyCalendar.nextReset(after: now) }

    init() {
        for template in catalog { templates[template.day] = template }
        if let data = UserDefaults.standard.data(forKey: "daily.templates"),
           let cached = try? JSONDecoder().decode([DailyTemplate].self, from: data) {
            for template in cached where template.isValid { templates[template.day] = template }
        }
        updateClock()
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let previous = DailyCalendar.day(for: self.now)
                self.updateClock()
                if previous != DailyCalendar.day(for: self.now) {
                    self.status = nil
                    Task { await self.refresh() }
                }
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.generation = UUID()
                    self.account = nil
                    self.days = []
                    self.status = nil
                    await self.refresh()
                }
            }.store(in: &observers)
    }

    func updateClock() {
        now = .now
        let day = DailyCalendar.day(for: now)
        template = templates[day] ?? DailyTemplate.fallback(for: day, from: catalog)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let token = generation
        defer {
            isRefreshing = false
            if token != generation { Task { await self.refresh() } }
        }
        updateClock()
        do {
            let remote = try await service.templates(starting: now)
            for template in remote { templates[template.day] = template }
            if let data = try? JSONEncoder().encode(Array(templates.values)) {
                UserDefaults.standard.set(data, forKey: "daily.templates")
            }
            templateStatus = nil
            updateClock()
        } catch {
            templateStatus = "Using saved templates. Connect to refresh the schedule."
        }
        do {
            let currentAccount = try await service.accountID()
            guard token == generation else { return }
            if account != currentAccount {
                account = currentAccount
                days = Set(UserDefaults.standard.stringArray(forKey: "daily.claims.\(currentAccount)") ?? [])
            }
            let remote = try await service.claimedDays()
            guard token == generation, try await service.accountID() == currentAccount else { return }
            // Claims are append-only. Union also tolerates CloudKit query indexing delay.
            days.formUnion(remote)
            saveCache()
            if !isClaiming && status?.hasPrefix("Daily credit claimed") != true { status = nil }
        } catch {
            guard token == generation else { return }
            if !isClaiming && !summary.claimedToday {
                status = "Streak couldn’t sync. Check iCloud and your connection, then retry."
            }
        }
    }

    func claim(_ chart: ChartState) async {
        guard let daily = chart.daily, !isClaiming else { return }
        updateClock()
        guard DailyCalendar.includes(now, in: daily.day) else {
            status = DailyError.expired.localizedDescription
            return
        }
        isClaiming = true
        defer { isClaiming = false }
        let token = generation
        do {
            let currentAccount = try await service.accountID()
            guard token == generation else { return }
            if account != currentAccount {
                account = currentAccount
                days = Set(UserDefaults.standard.stringArray(forKey: "daily.claims.\(currentAccount)") ?? [])
            }
            let day = try await service.claim(chartID: chart.id.uuidString, daily: daily, account: currentAccount)
            guard token == generation else { return }
            days.insert(day)
            saveCache()
            updateClock()
            status = "Daily credit claimed! Everyone else can tap the shared chart before reset to claim theirs."
        } catch {
            guard token == generation else { return }
            status = "Credit not claimed. \(error.localizedDescription)"
        }
    }

    private func saveCache() {
        guard let account else { return }
        UserDefaults.standard.set(Array(days), forKey: "daily.claims.\(account)")
    }
}
