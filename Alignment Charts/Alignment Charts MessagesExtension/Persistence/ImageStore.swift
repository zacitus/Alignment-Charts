import UIKit

/// Stores cell images as JPEGs in the extension's sandbox, keyed by immutable image ID (cell ID for legacy images).
enum ImageStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CellImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".jpg")
    }

    @discardableResult
    static func save(_ image: UIImage, for id: UUID) -> Bool {
        let resized = downscale(image, maxDimension: 1024)
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try data.write(to: url(for: id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func image(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: id).path)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Copies a downloaded asset file (e.g. from CloudKit) into the store.
    static func importFile(_ source: URL, for id: UUID) throws {
        try Data(contentsOf: source).write(to: url(for: id), options: .atomic)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
