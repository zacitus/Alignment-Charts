import SwiftUI

struct DailyHomeSection: View {
    @ObservedObject var store: DailyStore
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Daily alignment", systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                Label("\(store.summary.current)", systemImage: "flame.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(store.summary.current) day streak")
            }
            if let template = store.template {
                Button(action: onStart) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(template.title).font(.title2.bold())
                        Text(template.prompt).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens today’s alignment chart")
            } else {
                Text("Today’s template isn’t available yet.").font(.headline)
                Text("Check back soon. You can still make a custom chart below.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(store.summary.claimedToday ? "Today claimed" : "Today not claimed",
                      systemImage: store.summary.claimedToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.summary.claimedToday ? .green : .secondary)
                Spacer()
                Text("Best: \(store.summary.best)")
            }.font(.caption.bold())
            HStack(spacing: 4) {
                Text("Resets in")
                Text(store.reset, style: .timer).monospacedDigit()
            }.font(.caption)
            if let message = store.status { Text(message).font(.caption).accessibilityAddTraits(.updatesFrequently) }
            if let message = store.templateStatus { Text(message).font(.caption).foregroundStyle(.secondary) }
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .font(.caption)
            .disabled(store.isRefreshing)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}

struct DailyEditorBanner: View {
    @ObservedObject var store: DailyStore
    let daily: DailyIdentity
    let canClaim: Bool
    let retry: () -> Void

    private var expired: Bool { !DailyCalendar.includes(store.now, in: daily.day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Daily · \(daily.day)", systemImage: "sun.max.fill").font(.caption.bold())
                Spacer()
                if store.days.contains(daily.day) {
                    Label("Claimed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else if store.isClaiming {
                    ProgressView().controlSize(.small)
                } else if canClaim && !expired {
                    Button("Claim credit", action: retry).font(.caption.bold())
                }
            }
            Text(expired ? "This day has ended. You can keep editing, but new claims are closed."
                 : "Fill every cell and send. Everyone can tap the completed message to claim before midnight UTC.")
                .font(.caption).foregroundStyle(.secondary)
            if let status = store.status { Text(status).font(.caption) }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
