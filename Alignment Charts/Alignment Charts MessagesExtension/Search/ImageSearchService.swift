import Foundation
import ImageIO
import UIKit

struct ImageSearchResult: Identifiable, Sendable {
    let id: String
    let title: String
    let imageURL: URL
    let sourceURL: URL
    let provider: String
}

enum ImageSearchService {
    static func search(_ text: String) async throws -> [ImageSearchResult] {
        async let wikipedia = try? results(text, commons: false)
        async let commons = try? results(text, commons: true)
        let (first, second) = await (wikipedia, commons)
        try Task.checkCancellation()
        guard first != nil || second != nil else { throw URLError(.cannotLoadFromNetwork) }
        var seen = Set<URL>()
        return ((first ?? []) + (second ?? [])).filter { seen.insert($0.imageURL).inserted }
    }

    private static func results(_ text: String, commons: Bool) async throws -> [ImageSearchResult] {
        let host = commons ? "commons.wikimedia.org" : "en.wikipedia.org"
        var components = URLComponents(string: "https://\(host)/w/api.php")!
        var parameters = [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "search", "gsrsearch": text, "gsrlimit": "12",
            "gsrnamespace": commons ? "6" : "0"
        ]
        if commons {
            // Wikimedia Commons hosts only freely-licensed media by policy, so no license filter is needed here.
            parameters.merge([
                "prop": "imageinfo", "iiprop": "url|mime",
                "iiurlwidth": "600", "iiurlheight": "600"
            ]) { _, new in new }
            parameters["gsrsearch"] = "\(text) filetype:bitmap"
        } else {
            parameters.merge([
                "prop": "pageimages|info", "piprop": "thumbnail",
                "pithumbsize": "600", "pilicense": "free", "inprop": "url"
            ]) { _, new in new }
        }
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await download(components.url!, maxBytes: 2_000_000)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard response.error == nil else { throw URLError(.badServerResponse) }
        return (response.query?.pages ?? []).sorted { ($0.index ?? 0) < ($1.index ?? 0) }.compactMap { page in
            let info = page.imageinfo?.first
            guard let imageURL = commons ? info?.thumburl : page.thumbnail?.source,
                  imageURL.scheme == "https",
                  let sourceURL = commons ? info?.descriptionurl : page.fullurl else { return nil }
            return ImageSearchResult(
                id: "\(host)/\(page.pageid)",
                title: page.title.replacingOccurrences(of: "File:", with: ""),
                imageURL: imageURL, sourceURL: sourceURL,
                provider: commons ? "Wikimedia Commons" : "Wikipedia"
            )
        }
    }

    static func image(for result: ImageSearchResult) async throws -> UIImage {
        let data = try await download(result.imageURL, maxBytes: 8_000_000)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return UIImage(cgImage: image)
    }

    // Dedicated session with a real wall-clock deadline. URLSession.shared
    // leaves timeoutIntervalForResource at 7 days, so a stalled thumbnail
    // stream hangs the attach task forever: imageSelection never clears, and
    // every result button plus the whole Edit Cell form stays disabled with
    // no error shown. A 30s resource cap guarantees the task ends, the catch
    // sets imageError, and the UI unlocks.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private static func download(_ url: URL, maxBytes: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("AlignmentCharts/1.0 (iOS image picker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.expectedContentLength <= maxBytes,
              data.count <= maxBytes else { throw URLError(.badServerResponse) }
        return data
    }

    private struct SearchResponse: Decodable {
        let query: Query?
        let error: APIError?
        struct APIError: Decodable { let code: String }
        struct Query: Decodable { let pages: [Page] }
        struct Page: Decodable {
            let pageid: Int
            let title: String
            let index: Int?
            let fullurl: URL?
            let thumbnail: Thumbnail?
            let imageinfo: [ImageInfo]?
        }
        struct Thumbnail: Decodable { let source: URL }
        struct ImageInfo: Decodable {
            let thumburl: URL?
            let descriptionurl: URL?
        }
    }
}
