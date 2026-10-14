import Foundation
import CoreFoundation
import SwiftSoup

actor NovelService {
    private let session: URLSession
    private var lastRequest = Date.distantPast
    private var restoreCache: [URL: ChapterRestore] = [:]
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    static func supportedURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme ?? ""), let host = url.host?.lowercased(),
              ["linovelib.com", "bilinovel.com", "bilinovel.net", "wenku8.net"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            throw NovelError.message("请输入哔哩轻小说或轻小说文库的 HTTPS 小说链接。")
        }
        return url
    }

    func data(_ url: URL, referer: URL) async throws -> Data {
        try Task.checkCancellation()
        let delay = 6 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("night=0", forHTTPHeaderField: "Cookie")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        for attempt in 0..<3 {
            let (bytes, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NovelError.message("无效的服务器响应。") }
            if http.statusCode == 429 || http.statusCode >= 500 {
                if attempt < 2 { try await Task.sleep(for: .seconds(10 * (attempt + 1))); continue }
            }
            guard (200..<300).contains(http.statusCode) else { throw NovelError.message(http.statusCode == 403 ? "源站拒绝访问（HTTP 403），请先在浏览器确认该链接能打开。此应用无法绕过站点验证。" : "服务器返回 HTTP \(http.statusCode)，请稍后重试。") }
            return bytes
        }
        throw NovelError.message("请求重试失败。")
    }

    func document(_ url: URL) async throws -> Document {
        let bytes = try await data(url, referer: url)
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let html = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: gb) else { throw NovelError.message("无法识别网页编码。") }
        return try SwiftSoup.parse(html, url.absoluteString)
    }

    func search(_ query: String) async throws -> [URL] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let candidates = [URL(string: "https://www.bilinovel.com/search.html?keyword=\(q)"), URL(string: "https://www.linovelib.com/search.html?keyword=\(q)")].compactMap { $0 }
        var results: [URL] = []
        for url in candidates { let doc = try await document(url); for link in try doc.select("a[href*=novel], a[href*=book]") { if let absolute = URL(string: try link.attr("abs:href")), !results.contains(absolute) { results.append(absolute) } }; if !results.isEmpty { return Array(results.prefix(20)) } }
        return results
    }

    func load(_ input: String) async throws -> Novel {
        let original = try Self.supportedURL(input)
        if original.host?.contains("wenku8.net") == true { return try await loadSource(original.absoluteString) }
        guard let id = original.path.capture(#"/(?:novel|download)/(\d+)"#) else { throw NovelError.message("无法识别书籍编号。") }
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)!
        components.scheme = "https"
        components.path = "/novel/\(id).html"
        components.query = nil; components.fragment = nil
        var candidates = [components.url!]
        for host in ["www.linovelib.com", "www.bilinovel.com", "www.bilinovel.net"] {
            components.host = host
            if let url = components.url, !candidates.contains(url) { candidates.append(url) }
        }
        var failures: [String] = []
        for candidate in candidates {
            try Task.checkCancellation()
            do { return try await loadSource(candidate.absoluteString) }
            catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(candidate.host ?? "源站")：\(error.localizedDescription)") }
        }
        throw NovelError.message("所有来源读取失败：\n" + failures.joined(separator: "\n"))
    }

    private func loadSource(_ input: String) async throws -> Novel {
        let original = try Self.supportedURL(input)
        let host = original.host!.lowercased()
        let wenku = host.contains("wenku8.net")
        let biliHost = "https://" + host
        let id = original.path.capture(wenku ? #"/(?:book/|novel/\d+/)(\d+)"# : #"/(?:novel|download)/(\d+)"#)
        guard let id else { throw NovelError.message("无法识别书籍编号，请使用小说详情页或目录链接。") }
        let url = URL(string: wenku ? "https://www.wenku8.net/book/\(id).htm" : "\(biliHost)/novel/\(id).html")!
        let doc = try await document(url)
        let title = try doc.select(wenku ? "#content table span b" : ".book-title").first()?.text() ?? ""
        guard !title.isEmpty else { throw NovelError.message("未找到书籍信息：网站可能要求登录、验证码，或已更改页面结构。") }
        var author = try doc.select(".book-rand-a span").first()?.text() ?? "未知作者"
        if wenku {
            for td in try doc.select("#content table td") {
                let text = try td.text()
                if text.hasPrefix("小说作者：") { author = text.replacingOccurrences(of: "小说作者：", with: "") }
            }
        }
        let summary = try doc.select("#bookSummary content").first()?.text() ?? ""
        let cover = try doc.select(wenku ? "#content table img" : ".book-layout img").first()?.attr("abs:src")
        let catalogURL: URL
        if wenku {
            guard let href = try doc.select("legend + div > a").first()?.attr("abs:href"), let link = URL(string: href) else { throw NovelError.message("找不到文库目录；需要登录的书籍暂不支持。") }
            catalogURL = link
        } else { catalogURL = URL(string: "\(biliHost)/novel/\(id)/catalog")! }
        let catalog = try await document(catalogURL)
        let recovered = wenku ? (try Self.parseCatalog(catalog, wenku: true), 0) : try await recoverCatalog(catalog, base: catalogURL)
        let chapters = recovered.0
        guard !chapters.isEmpty else { throw NovelError.message("目录为空或章节链接被隐藏，不能继续下载。") }
        let hiddenCount = recovered.1
        var novel = Novel(title: title, author: author, summary: summary, cover: cover.flatMap(URL.init(string:)), url: url, chapters: chapters, hiddenChapterCount: hiddenCount)
        novel.publisher = try doc.select(".tag-small.orange").first()?.text()
        novel.tags = try doc.select(".book-cell .book-meta span em").map { try $0.text() }
        novel.alias = try doc.select(".backupname .bkname-body.gray").first()?.text()
        novel.publicationStatus = try doc.select(".book-cell .book-meta+.book-meta").first()?.text()
        var currentVolume = "正文"
        for item in try catalog.select(".volume-chapters > li") {
            if item.hasClass("chapter-bar") { currentVolume = try item.text() }
            if item.hasClass("volume-cover"), let img = try item.select("img").first() {
                let raw = try img.attr("data-src").isEmpty ? img.attr("src") : img.attr("data-src")
                if !raw.contains("book-cover-no"), let cover = URL(string: raw, relativeTo: catalogURL)?.absoluteURL { novel.volumeCovers[currentVolume] = cover }
            }
        }
        return novel
    }

    static func parseCatalog(_ doc: Document, wenku: Bool) throws -> [Chapter] {
        var volume = "正文"
        var result: [Chapter] = []
        var seen = Set<URL>()
        for element in try doc.select(wenku ? "table td" : ".volume-chapters > li") {
            if element.hasClass(wenku ? "vcss" : "chapter-bar") { volume = try element.text(); continue }
            if !wenku && !element.hasClass("jsChapter") { continue }
            guard let a = try element.select("a").first() else { continue }
            let href = try a.attr("abs:href")
            guard let url = URL(string: href), ["https", "http"].contains(url.scheme ?? "") else {
                continue
            }
            if seen.insert(url).inserted { result.append(Chapter(title: try a.text(), volume: volume, url: url)) }
        }
        if wenku {
            let volumes = result.reduce(into: [String]()) { if !$0.contains($1.volume) { $0.append($1.volume) } }
            return volumes.flatMap { volume in result.filter { $0.volume == volume && $0.title == "插图" } + result.filter { $0.volume == volume && $0.title != "插图" } }
        }
        return result
    }

    private struct CatalogEntry {
        let title: String
        let volume: String
        var url: URL?
    }

    // Preserve every catalog row, then recover missing addresses from adjacent chapter navigation.
    private func recoverCatalog(_ doc: Document, base: URL) async throws -> ([Chapter], Int) {
        var entries: [CatalogEntry] = []
        var volume = "正文"
        for item in try doc.select(".volume-chapters > li") {
            if item.hasClass("chapter-bar") { volume = try item.text(); continue }
            guard item.hasClass("jsChapter"), let link = try item.select("a").first() else { continue }
            let raw = try link.attr("href")
            let candidate = URL(string: raw, relativeTo: base)?.absoluteURL
            let url = !raw.isEmpty && !raw.lowercased().hasPrefix("javascript") && candidate?.host == base.host && candidate?.path.hasSuffix(".html") == true ? candidate : nil
            entries.append(CatalogEntry(title: try link.text(), volume: volume, url: url))
        }
        var cache: [URL: Document] = [:]
        func page(_ url: URL) async throws -> Document {
            if let cached = cache[url] { return cached }
            let result = try await document(url); cache[url] = result; return result
        }
        func navigation(_ doc: Document, current: URL, previous: Bool) throws -> (URL, Bool)? {
            let selector = previous ? "#footlink a.prevlink" : "#footlink a.nextlink"
            guard let link = try doc.select(selector).first() else { return nil }
            let label = try link.text()
            if label.contains("目录") || label.contains("目錄") { return nil }
            let key = previous ? "url_previous" : "url_next"
            let href = try doc.outerHtml().capture(key + #"\s*:\s*['"]([^'"]+)"#) ?? link.attr("href")
            guard let url = URL(string: href, relativeTo: current)?.absoluteURL,
                  url.host == base.host, url.path.hasPrefix(base.path.replacingOccurrences(of: "catalog", with: "")), url.path.hasSuffix(".html") else { return nil }
            return (url, ["上一页", "上一頁", "下一页", "下一頁"].contains(label))
        }
        // Repeat to support runs of consecutive hidden links, without guessing numeric chapter IDs.
        for _ in 0..<entries.count {
            var changed = false
            for i in entries.indices where entries[i].url == nil {
                try Task.checkCancellation()
                var found: URL?
                do {
                    if i + 1 < entries.count, let next = entries[i+1].url {
                        let doc = try await page(next)
                        if let nav = try navigation(doc, current: next, previous: true), !nav.1 { found = nav.0 }
                    }
                    if found == nil, i > 0, var previous = entries[i-1].url {
                        var visited = Set<URL>()
                        for _ in 0..<20 {
                            guard visited.insert(previous).inserted else { break }
                            let doc = try await page(previous)
                            guard let nav = try navigation(doc, current: previous, previous: false) else { break }
                            if !nav.1 { found = nav.0; break }
                            previous = nav.0
                        }
                    }
                    if let found, !entries.contains(where: { $0.url == found }) {
                        let check = try await page(found)
                        let expected = entries[i].title.filter { !$0.isWhitespace }
                        let actual = (try check.select("#atitle").first()?.text() ?? "").filter { !$0.isWhitespace }
                        guard !actual.isEmpty, actual == expected else { continue }
                        entries[i].url = found; changed = true
                        print("RECOVERED_CHAPTER title=\(entries[i].title) url=\(found)")
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { print("CHAPTER_RECOVERY_FAILED title=\(entries[i].title) reason=\(error.localizedDescription)") }
            }
            if !changed { break }
        }
        return (entries.compactMap { item in item.url.map { Chapter(title: item.title, volume: item.volume, url: $0) } }, entries.filter { $0.url == nil }.count)
    }

    func chapter(_ chapter: Chapter, folder: URL, images: inout [String: String], includeImages: Bool) async throws -> String {
        var page: URL? = chapter.url
        var visited = Set<URL>()
        var output = ""
        while let current = page {
            guard visited.insert(current).inserted, visited.count <= 100 else { throw NovelError.message("检测到章节分页循环。") }
            let doc = try await document(current)
            guard let content = try doc.select("#acontent, .bcontent, #content").first() else { throw NovelError.message("未找到章节正文：\(chapter.title)") }
            try Self.validateChapter(content)
            try content.select("div, script, style, ins, figure, fig, br, .tp, .bd, #contentdp, #contentad").remove()
            if let script = try doc.select("script[src*=chapterlog]").first() {
                guard let scriptURL = URL(string: try script.attr("abs:src")),
                      let idText = try doc.outerHtml().capture(#"chapterid\s*:\s*['"](\d+)"#),
                      let chapterID = Int64(idText) else { throw NovelError.message("正文缺少还原所需的章节编号。") }
                let template: ChapterRestore
                if let cached = restoreCache[scriptURL] { template = cached }
                else {
                    let bytes = try await data(scriptURL, referer: current)
                    template = try ChapterRestore.parse(String(decoding: bytes, as: UTF8.self))
                    restoreCache[scriptURL] = template
                }
                try template.restore(content, chapterID: chapterID)
            }
            for image in try content.select("img") {
                if !includeImages { try image.remove(); continue }
                let raw = try image.attr("data-src").isEmpty ? image.attr("src") : image.attr("data-src")
                guard let url = URL(string: raw, relativeTo: current)?.absoluteURL, ["http", "https"].contains(url.scheme ?? "") else { throw NovelError.message("不支持的插图地址。") }
                let key = url.absoluteString
                let name: String
                if let saved = images[key] { name = saved }
                else {
                    let bytes = try await data(url, referer: current)
                    let ext = Self.imageExtension(bytes)
                    guard let ext else { throw NovelError.message("插图响应不是支持的图片格式。") }
                    name = "image-\(images.count).\(ext)"
                    try bytes.write(to: folder.appendingPathComponent(name))
                    images[key] = name
                }
                try image.attr("src", "images/" + name)
            }
            // Rebuild as valid XHTML instead of inserting HTML void tags into EPUB XML.
            output += try Self.xhtml(content)
            page = nil
            if let next = try doc.select("#footlink a.nextlink").first(), ["下一页", "下一頁"].contains(try next.text()) {
                let html = try doc.outerHtml()
                let fallbackHref = try next.attr("href")
                let href = html.capture(#"url_next\s*:\s*['"]([^'"]+)"#) ?? fallbackHref
                guard let link = URL(string: href, relativeTo: current)?.absoluteURL, link.host == chapter.url.host else { throw NovelError.message("无效的分页链接。") }
                page = link
            }
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NovelError.message("章节正文为空。") }
        return output
    }

    static func validateChapter(_ content: Element) throws {
        let text = try content.text()
        let notices = ["无法完美使用", "無法完美使用", "內容加載失敗", "内容加载失败", "请使用〔Chrome", "Just a moment"]
        guard !notices.contains(where: text.contains), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NovelError.message("源站返回了被截断的正文或浏览器提示，无法生成完整 EPUB。请稍后重试。")
        }
    }

    static func xhtml(_ node: Node) throws -> String {
        if let text = node as? TextNode { return text.getWholeText().xml }
        guard let element = node as? Element else { return "" }
        let tag = element.tagName().lowercased()
        if ["script", "style", "iframe", "object"].contains(tag) { return "" }
        if tag == "img" { return "<img src=\"\(try element.attr("src").xml)\" alt=\"插图\" />" }
        if tag == "br" { return "<br />" }
        let inside = try element.getChildNodes().map { try xhtml($0) }.joined()
        let allowed = ["p", "div", "span", "em", "strong", "b", "i", "h2", "h3", "blockquote"]
        return allowed.contains(tag) ? "<\(tag)>\(inside)</\(tag)>" : inside
    }

    static func imageExtension(_ bytes: Data) -> String? {
        let prefix = Array(bytes.prefix(12))
        if prefix.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if prefix.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if prefix.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if prefix.starts(with: [0x42, 0x4D]) { return "bmp" }
        if prefix.starts(with: [0x52, 0x49, 0x46, 0x46]), prefix.count >= 12, Array(prefix[8..<12]) == [0x57,0x45,0x42,0x50] { return "webp" }
        return nil
    }
}

