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
        XCTAssertEqual(novel.hiddenChapterCount, 0, "5428 hidden chapter must be recovered")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var imageMap: [String:String] = [:]
        let chapter = try XCTUnwrap(novel.chapters.first)
        var totalBytes = 0
        for (index,item) in novel.chapters.prefix(ProcessInfo.processInfo.environment["FULL_EPUB_TEST"] == "1" ? novel.chapters.count : 1).enumerated() {
            let body = try await service.chapter(item, folder: images, images: &imageMap, includeImages: true)
            let text = try SwiftSoup.parse(body).text()
            XCTAssertGreaterThan(text.count, 100, item.title)
            XCTAssertFalse(text.contains("请登录"), item.title)
            XCTAssertFalse(text.contains("无法完美使用"), item.title)
            XCTAssertFalse(text.contains("內容加載失敗"), item.title)
            XCTAssertFalse(text.contains("驗證碼"), item.title)
            print("LIVE_CHAPTER title=\(item.title) characters=\(text.count) sample=\(text.prefix(100))")
            totalBytes += body.utf8.count
            try Data(EPUBBuilder.page(title: item.title, body: body).utf8).write(to: root.appendingPathComponent("OEBPS/chapter-\(index).xhtml"))
        }
        // Archive must be outside the source folder being enumerated.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: output) }
        try EPUBBuilder.build(novel: novel, chapters: Array(novel.chapters.prefix(ProcessInfo.processInfo.environment["FULL_EPUB_TEST"] == "1" ? novel.chapters.count : 1)), folder: root, destination: output)
        let archive = try Archive(url: output,accessMode: .read)
        XCTAssertNotNil(archive["OEBPS/chapter-0.xhtml"])
        XCTAssertNotNil(archive["OEBPS/content.opf"])
        print("LIVE_EPUB_RESULT chapter=\(chapter.title) bodyBytes=\(totalBytes) ipaVersion=1.3.1")
        print("LIVE_SOURCE_RESULT title=\(novel.title) chapters=\(novel.chapters.count) hidden=\(novel.hiddenChapterCount)")
    }
}

