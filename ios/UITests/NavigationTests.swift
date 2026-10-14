import XCTest

final class NavigationTests: XCTestCase {
    func testNumberImportAndIndependentTaskPage() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["bookID"].waitForExistence(timeout: 15))
        let load = app.buttons["loadNovel"]
        XCTAssertFalse(load.isEnabled)
        app.textFields["bookID"].tap()
        app.textFields["bookID"].typeText("5428")
        XCTAssertTrue(load.isEnabled)
        app.swipeUp()
        app.tabBars.buttons["打包"].tap()
        XCTAssertTrue(app.staticTexts["emptyExport"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.otherElements["appVersion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["导入"].tap()
        XCTAssertEqual(app.textFields["bookID"].value as? String, "5428")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "number-import-light"
        attachment.lifetime = .keepAlways
        add(attachment)
        load.tap()
        XCTAssertTrue(app.navigationBars["书籍详情"].waitForExistence(timeout: 180))
        print("BOOK_UI_TREE " + app.debugDescription)
        app.swipeUp()
        app.buttons["chapterPicker"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        let chapters = XCTAttachment(screenshot: app.screenshot())
        chapters.name = "chapter-picker"
        chapters.lifetime = .keepAlways
        add(chapters)
    }
}

