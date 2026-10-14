import XCTest
import SwiftSoup
import ZIPFoundation
@testable import BiliNovel

final class FixtureProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var pages: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let path = request.url!.path
        let status = Self.pages[path] == nil ? 404 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"text/html; charset=utf-8"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.pages[path] ?? "not found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ParityTests: XCTestCase {
    func testLiteralEntitiesAreRestoredAndSafelyEscaped() throws {
        let doc = try SwiftSoup.parse("<p>＆quot;故事＆quot; ＆lt;正文＆gt; ＆amp; ＆middot;</p>")
        let html = try NovelService.xhtml(try XCTUnwrap(doc.select("p").first()))
        XCTAssertEqual(try SwiftSoup.parse(html).text(), "\"故事\" <正文> & ·")
        XCTAssertTrue(html.contains("&lt;正文&gt;"))
    }
    @MainActor func testManualBatchPausesForEachBook() async throws {
        FixtureProtocol.pages = ["/novel/1.html": "<h1 class='book-title'>手动</h1>", "/novel/1/catalog": "<ul class='volume-chapters'><li class='jsChapter'><a href='/novel/1/1.html'>一</a></li></ul>"]
        let model = AppModel(service: service())
        model.batchManual = true
        model.batchInput = "https://www.linovelib.com/novel/1.html https://www.linovelib.com/novel/1.html"
        model.startBatch()
        for _ in 0..<100 { if model.novel != nil && !model.isBatchRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.novel); XCTAssertEqual(model.batchRemaining.count, 1)
        XCTAssertTrue(model.outputURLs.isEmpty)
        model.continueBatch()
        for _ in 0..<100 { if model.batchRemaining.isEmpty && !model.isBatchRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(model.failure); XCTAssertTrue(model.batchRemaining.isEmpty)
    }
    @MainActor func testMergedArchiveIncludesCoverAndHierarchicalNavigation() async throws {
        FixtureProtocol.pages = ["/novel/1/1.html": page("一", previous: "/novel/1/catalog", next: "/novel/1/2.html"), "/novel/1/2.html": page("二", previous: "/novel/1/1.html", next: "/novel/1/catalog")]
        let chapters = [Chapter(title: "一", volume: "第一卷", url: URL(string: "https://www.linovelib.com/novel/1/1.html")!), Chapter(title: "二", volume: "第二卷", url: URL(string: "https://www.linovelib.com/novel/1/2.html")!)]
        let model = AppModel(service: service())
        model.novel = Novel(title: "合并测试", author: "作者", summary: "简介", cover: nil, url: URL(string: "https://www.linovelib.com/novel/1.html")!, chapters: chapters)
        model.selected = Set(chapters.map(\.id)); model.combineVolumes = true; model.addChapterTitles = true
        await model.export(includeImages: false)
        XCTAssertNil(model.failure); XCTAssertEqual(model.outputURLs.count, 1)
        let archive = try Archive(url: XCTUnwrap(model.outputURLs.first), accessMode: .read)
        XCTAssertNotNil(archive["OEBPS/chapter-1.xhtml"])
        func content(_ path: String) throws -> String { var data = Data(); _ = try archive.extract(XCTUnwrap(archive[path])) { data.append($0) }; return String(decoding: data, as: UTF8.self) }
        XCTAssertTrue(try content("OEBPS/chapter-0.xhtml").contains("<h1>一</h1>"))
        let nav = try content("OEBPS/nav.xhtml")
        XCTAssertTrue(nav.contains("第一卷")); XCTAssertTrue(nav.contains("第二卷"))
        XCTAssertEqual(try SwiftSoup.parse(nav).select("ol > li > ol").count, 2)
        XCTAssertFalse(model.exportEvents.isEmpty); XCTAssertNotNil(model.exportEnded)
        // Verify cover packaging independently from source image availability.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = root.appendingPathComponent("OEBPS/images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xFF,0xD8,0xFF]).write(to: images.appendingPathComponent("cover.jpg"))
        try Data(EPUBBuilder.page(title: "一", body: "<p>正文</p>").utf8).write(to: root.appendingPathComponent("OEBPS/chapter-0.xhtml"))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: out) }
        try EPUBBuilder.build(novel: XCTUnwrap(model.novel), chapters: [chapters[0]], folder: root, destination: out)
        let covered = try Archive(url: out, accessMode: .read)
        XCTAssertNotNil(covered["OEBPS/cover.xhtml"]); XCTAssertNotNil(covered["OEBPS/images/cover.jpg"])
    }
    func testSearchUsesSourceFormMethodAndFiltersDetailLinks() async throws {
        FixtureProtocol.pages = ["/": "<form method='post' action='/search'><input name='searchkey'/><input type='hidden' name='type' value='title'/></form>", "/search": "<a href='/novel/5428.html'>书</a><a href='/novel/5428/1.html'>正文</a><a href='/novel/5428.html'>重复</a>"]
        let results = try await service().search("故事+名称")
        XCTAssertEqual(results.map(\.path), ["/novel/5428.html"])
        XCTAssertEqual(FixtureProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.path, "/search")
        // URLProtocol receives body streams on some Foundation versions; method/route prove POST dispatch.
    }
    func service() -> NovelService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return NovelService(session: URLSession(configuration: config), requestInterval: 0)
    }
    func page(_ title: String, previous: String, next: String, nextLabel: String = "下一章", body: String = "正文") -> String {
        "<h1 id='atitle'>\(title)</h1><script>var ReadParams={url_previous:'\(previous)',url_next:'\(next)'}</script><div id='acontent'><p>\(body)</p></div><div id='footlink'><a class='prevlink'>上一章</a><a class='nextlink'>\(nextLabel)</a></div>"
    }
    @MainActor func testContinuousBatchExportsTwoBooks() async throws {
        let catalog = "<ul class='volume-chapters'><li class='chapter-bar'>第一卷</li><li class='jsChapter'><a href='/novel/1/1.html'>一</a></li></ul>"
        let detail = "<h1 class='book-title'>批量测试</h1><div class='book-rand-a'><span>作者</span></div>"
        FixtureProtocol.pages = ["/novel/1.html": detail, "/novel/2.html": detail, "/novel/1/catalog": catalog, "/novel/2/catalog": catalog, "/novel/1/1.html": page("一", previous: "/novel/1/catalog", next: "/novel/1/catalog")]
        let model = AppModel(service: service())
        let before = model.books.count
        model.batchInput = "https://www.linovelib.com/novel/1.html https://www.linovelib.com/novel/2.html"
        model.startBatch()
        for _ in 0..<100 {
            if model.books.count >= before + 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.books.count, before + 2)
        XCTAssertTrue(model.batchRemaining.isEmpty)
    }
    func testWenkuMetadataAndChapterParagraphs() async throws {
        FixtureProtocol.pages = [
            "/book/1.htm": "<div id='content'><table><tr><td><span><b>文库测试</b></span></td></tr><tr><td>小说作者：作者</td><td>文章状态：完结</td></tr></table><table></table><table><tr><td></td><td><span>作品Tags：校园 奇幻</span><span>简介</span></td></tr></table><legend>目录</legend><div><a href='/novel/0/1/index.htm'>目录</a></div></div>",
            "/novel/0/1/index.htm": "<table><tr><td class='vcss'>第一卷</td><td class='ccss'><a href='1.htm'>第一章</a></td></tr></table>",
            "/novel/0/1/1.htm": "<div id='content'>第一段<br/>第二段<br/><div id='contentdp'>广告</div></div>"]
        let service = service()
        let novel = try await service.load("https://www.wenku8.net/book/1.htm")
        XCTAssertEqual(novel.title, "文库测试"); XCTAssertEqual(novel.author, "作者")
        XCTAssertEqual(novel.summary, "简介"); XCTAssertEqual(novel.tags, ["校园", "奇幻"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var images: [String:String] = [:]
        let html = try await service.chapter(XCTUnwrap(novel.chapters.first), folder: root, images: &images, includeImages: false)
        let doc = try SwiftSoup.parse(html)
        XCTAssertEqual(try doc.select("p").count, 2)
        XCTAssertFalse(try doc.text().contains("广告"))
    }
    func testRecoversConsecutiveHiddenLinksInCatalogOrder() async throws {
        FixtureProtocol.pages = [
            "/novel/1/4.html": page("四", previous: "/novel/1/3.html", next: "/novel/1/catalog"),
            "/novel/1/3.html": page("三", previous: "/novel/1/2.html", next: "/novel/1/4.html"),
            "/novel/1/2.html": page("二", previous: "/novel/1/1.html", next: "/novel/1/3.html"),
            "/novel/1/1.html": page("一", previous: "/novel/1/catalog", next: "/novel/1/2.html")]
        let base = URL(string: "https://www.linovelib.com/novel/1/catalog")!
        let doc = try SwiftSoup.parse("<ul class='volume-chapters'><li class='chapter-bar'>卷</li><li class='jsChapter'><a href='/novel/1/1.html'>一</a></li><li class='jsChapter'><a href='javascript:void(0)'>二</a></li><li class='jsChapter'><a>三</a></li><li class='jsChapter'><a href='/novel/1/4.html'>四</a></li></ul>", base.absoluteString)
        let result = try await service().recoverCatalog(doc, base: base)
        XCTAssertEqual(result.0.map(\.title), ["一","二","三","四"])
        XCTAssertEqual(result.1, 0)
    }
    func testPaginationDoesNotConsumeNextChapter() async throws {
        FixtureProtocol.pages = [
            "/novel/1/1.html": page("一", previous: "/novel/1/catalog", next: "/novel/1/1_2.html", nextLabel: "下一頁", body: "第一页面"),
            "/novel/1/1_2.html": page("一", previous: "/novel/1/1.html", next: "/novel/1/2.html", body: "第二页面")]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var images: [String:String] = [:]
        let chapter = Chapter(title: "一", volume: "卷", url: URL(string: "https://www.linovelib.com/novel/1/1.html")!)
        let html = try await service().chapter(chapter, folder: root, images: &images, includeImages: false)
        XCTAssertEqual(try SwiftSoup.parse(html).text(), "第一页面 第二页面")
    }
    @MainActor func testSplitVolumesProducesSeparateEPUBsWithMetadata() async throws {
        FixtureProtocol.pages = [
            "/novel/1/1.html": page("一", previous: "/novel/1/catalog", next: "/novel/1/2.html"),
            "/novel/1/2.html": page("二", previous: "/novel/1/1.html", next: "/novel/1/catalog")]
        let chapters = [Chapter(title: "一", volume: "第一卷", url: URL(string: "https://www.linovelib.com/novel/1/1.html")!), Chapter(title: "二", volume: "第二卷", url: URL(string: "https://www.linovelib.com/novel/1/2.html")!)]
        let model = AppModel(service: service())
        model.novel = Novel(title: "测试书", author: "作者", summary: "简介", cover: nil, url: URL(string: "https://www.linovelib.com/novel/1.html")!, chapters: chapters, publisher: "出版社", tags: ["校园"])
        model.selected = Set(chapters.map(\.id)); model.combineVolumes = false
        await model.export(includeImages: false)
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.outputURLs.count, 2)
        for url in model.outputURLs {
            let archive = try Archive(url: url, accessMode: .read)
            XCTAssertNotNil(archive["OEBPS/chapter-0.xhtml"])
            XCTAssertNil(archive["OEBPS/chapter-1.xhtml"])
            XCTAssertNotNil(archive["OEBPS/toc.ncx"])
            var bytes = Data()
            _ = try archive.extract(XCTUnwrap(archive["OEBPS/content.opf"])) { bytes.append($0) }
            let opf = String(decoding: bytes, as: UTF8.self)
            XCTAssertTrue(opf.contains("出版社")); XCTAssertTrue(opf.contains("校园")); XCTAssertTrue(opf.contains("calibre:series_index"))
        }
    }
}

