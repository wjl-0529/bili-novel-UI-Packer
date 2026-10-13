import XCTest
import ZIPFoundation
import SwiftSoup
@testable import BiliNovel

final class LiveSourceTests: XCTestCase {
    func testReadActual5428() async throws {
        guard ProcessInfo.processInfo.environment["LIVE_SOURCE_TEST"] == "1" else { throw XCTSkip("Live source test is opt-in") }
        let service = NovelService()
        let novel = try await service.load("https://www.linovelib.com/novel/5428.html")
        XCTAssertFalse(novel.title.isEmpty)
        XCTAssertFalse(novel.chapters.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var imageMap: [String:String] = [:]
        let chapter = try XCTUnwrap(novel.chapters.first)
        let body = try await service.chapter(chapter, folder: images, images: &imageMap, includeImages: true)
        XCTAssertGreaterThan(try SwiftSoup.parse(body).text().count, 100)
        try Data(EPUBBuilder.page(title: chapter.title, body: body).utf8).write(to: root.appendingPathComponent("OEBPS/chapter-0.xhtml"))
        // Archive must be outside the source folder being enumerated.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: output) }
        try EPUBBuilder.build(novel: novel, chapters: [chapter], folder: root, destination: output)
        let archive = try Archive(url: output,accessMode: .read)
        XCTAssertNotNil(archive["OEBPS/chapter-0.xhtml"])
        XCTAssertNotNil(archive["OEBPS/content.opf"])
        print("LIVE_EPUB_RESULT chapter=\(chapter.title) bodyBytes=\(body.utf8.count) ipaVersion=1.2.0")
        print("LIVE_SOURCE_RESULT title=\(novel.title) chapters=\(novel.chapters.count) hidden=\(novel.hiddenChapterCount)")
    }
}
