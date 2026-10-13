import XCTest
@testable import BiliNovel

final class EPUBTests: XCTestCase {
    func testXMLIsEscaped() { XCTAssertEqual("a < b & c".xml, "a &lt; b &amp; c") }
    func testImageSignature() { XCTAssertEqual( NovelService.imageExtension(Data([0xFF,0xD8,0xFF])), "jpg") }
}
