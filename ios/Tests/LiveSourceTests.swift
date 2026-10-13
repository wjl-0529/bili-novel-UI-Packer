import XCTest
@testable import BiliNovel

final class LiveSourceTests: XCTestCase {
    func testReadActual5428() async throws {
        guard ProcessInfo.processInfo.environment["LIVE_SOURCE_TEST"] == "1" else { throw XCTSkip("Live source test is opt-in") }
        let service = NovelService()
        let novel = try await service.load("https://www.linovelib.com/novel/5428.html")
        XCTAssertFalse(novel.title.isEmpty)
        XCTAssertFalse(novel.chapters.isEmpty)
        print("LIVE_SOURCE_RESULT title=\(novel.title) chapters=\(novel.chapters.count) hidden=\(novel.hiddenChapterCount)")
    }
}
