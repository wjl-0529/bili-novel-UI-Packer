import Foundation

struct Chapter: Identifiable, Codable, Hashable {
    var id: String { url.absoluteString }
    let title: String
    let volume: String
    let url: URL
}

struct Novel: Codable {
    let title: String
    let author: String
    let summary: String
    let cover: URL?
    let url: URL
    let chapters: [Chapter]
}

struct LibraryBook: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let filename: String
    let date: Date
    let chapterCount: Int
    var url: URL { LibraryBook.directory.appendingPathComponent(filename) }
    static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
}

enum NovelError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

extension String {
    var xml: String {
        replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    func capture(_ pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              group < match.numberOfRanges, let range = Range(match.range(at: group), in: self) else { return nil }
        return String(self[range])
    }
}
