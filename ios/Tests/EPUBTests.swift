import XCTest
import SwiftSoup
@testable import BiliNovel

final class EPUBTests: XCTestCase {
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
