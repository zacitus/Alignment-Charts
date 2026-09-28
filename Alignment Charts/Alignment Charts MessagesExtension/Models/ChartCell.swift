import Foundation

struct ChartCell: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var caption: String = ""
    var hasImage: Bool = false
    /// Nil on charts created before versioned images; their asset uses the cell ID.
    var imageID: UUID?
    /// The search result associated with the current photo, if chosen from suggestions.
    var imageSearchResultID: String?

    var imageStorageID: UUID { imageID ?? id }
    var imageReference: UUID? { hasImage ? imageStorageID : nil }

    mutating func setImageReference(_ reference: UUID?) {
        hasImage = reference != nil
        imageID = reference
        imageSearchResultID = nil
    }
}
