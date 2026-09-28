import SwiftUI

@MainActor
enum ChartImageRenderer {
    /// Renders the chart to a flat image for the message bubble.
    static func render(_ chart: ChartState) -> UIImage? {
        let renderer = ImageRenderer(content:
            ChartGridView(chart: chart)
                .frame(width: 620)
                .padding(20)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        return renderer.uiImage
    }
}
