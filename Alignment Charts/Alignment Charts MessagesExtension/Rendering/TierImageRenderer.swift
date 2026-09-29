import SwiftUI

@MainActor
enum TierImageRenderer {
    /// Renders the tier chart to a flat image for the message bubble.
    static func render(_ tier: TierState) -> UIImage? {
        let renderer = ImageRenderer(content:
            TierChartView(tier: tier)
                .frame(width: 620)
                .padding(20)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        // iMessage bubbles and Photos both choke on extremely tall images, and a
        // runaway render (hundreds of ranked items) would balloon memory at 2x.
        // Refuse anything taller than ~1200pt instead of sending a broken bubble;
        // the coordinator surfaces a "too large" error so the user can trim the chart.
        guard image.size.height * image.scale <= 2400 else { return nil }
        return image
    }
}
