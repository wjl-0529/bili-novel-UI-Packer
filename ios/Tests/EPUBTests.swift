import XCTest
import SwiftSoup
@testable import BiliNovel

final class EPUBTests: XCTestCase {
    func testTitleAndSeriesOptions() {
        XCTAssertFalse(EPUBBuilder.page(title: "标题", body: "<p>正文</p>", addTitle: false).contains("<h1>"))
        XCTAssertTrue(EPUBBuilder.page(title: "标题", body: "<p>正文</p>", addTitle: true).contains("<h1>标题</h1>"))
        XCTAssertEqual(EPUBBuilder.seriesIndex("第二十一卷"), 21)
        XCTAssertEqual(EPUBBuilder.seriesIndex("Book 2.5"), 2.5)
        XCTAssertNil(EPUBBuilder.seriesIndex("短篇集"))
    }
    func testWenkuIllustrationsComeFirst() throws {
        let doc = try SwiftSoup.parse("<table><tr><td class='vcss'>第一卷</td></tr><tr><td class='ccss'><a href='1.htm'>第一章</a></td><td class='ccss'><a href='2.htm'>插图</a></td></tr></table>", "https://www.wenku8.net/novel/1/1/index.htm")
        XCTAssertEqual(try NovelService.parseCatalog(doc, wenku: true).first?.title, "插图")
    }

    func testBookNumberResolvesSelectedSource() {
        XCTAssertEqual(BookSource.linovelib.bookURL("1")?.absoluteString, "https://www.linovelib.com/novel/1.html")
        XCTAssertEqual(BookSource.wenku.bookURL("5428")?.absoluteString, "https://www.wenku8.net/book/5428.htm")
        for invalid in ["", "0", "-1", "1.html", "https://example.com", "１"] { XCTAssertNil(BookSource.linovelib.bookURL(invalid)) }
    }

    func testRejectsTruncatedSourceBeforeExport() throws {
        let doc = try SwiftSoup.parse("<div><p>这是一段真实正文。</p><p>（內容加載失敗！請刷新或更換瀏覽器）</p></div>")
        XCTAssertThrowsError(try NovelService.validateChapter(XCTUnwrap(doc.select("div").first())))
        let valid = try SwiftSoup.parse("<div><p>完整正文。</p></div>")
        XCTAssertNoThrow(try NovelService.validateChapter(XCTUnwrap(valid.select("div").first())))
    }

    func testCatalogHiddenLinkDoesNotDiscardReadableChapters() throws {
        let doc = try SwiftSoup.parse("<ul class='volume-chapters'><li class='chapter-bar'>第一卷</li><li class='jsChapter'><a href='javascript:void(0)'>隐藏章</a></li><li class='jsChapter'><a href='/novel/5428/123.html'>第一章</a></li></ul>", "https://www.linovelib.com")
        let chapters = try NovelService.parseCatalog(doc, wenku: false)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].url.absoluteString, "https://www.linovelib.com/novel/5428/123.html")
    }
    func testRestorePreservesParagraphSlots() throws {
        let doc = try SwiftSoup.parse("<div id='body'><p>zero</p><img src='x'/><p>one</p><p>two</p><p>three</p></div>")
        let content = try XCTUnwrap(doc.getElementById("body"))
        let template = ChapterRestore(fixed: 1, seedMultiplier: 1, seedOffset: 0, a: 5, c: 1, mod: 97)
        let order = try template.order(count: 4,chapterID: 7)
        XCTAssertEqual(Set(order), Set(0..<4))
        try template.restore(content,chapterID: 7)
        XCTAssertEqual(content.getChildNodes()[1] is Element, true)
        XCTAssertEqual((content.getChildNodes()[1] as? Element)?.tagName(), "img")
        XCTAssertEqual(try content.select("p").first()?.text(), "zero")
    }
    func testXMLIsEscaped() { XCTAssertEqual("a < b & c".xml, "a &lt; b &amp; c") }
    func testImageSignature() { XCTAssertEqual( NovelService.imageExtension(Data([0xFF,0xD8,0xFF])), "jpg") }
}

