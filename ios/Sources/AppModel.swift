import Foundation
import SwiftUI

@main struct BiliNovelApp: App { var body: some Scene { WindowGroup { ContentView() } } }

@MainActor final class AppModel: ObservableObject {
    @Published var link = ""
    @Published var novel: Novel?
    @Published var selected = Set<String>()
    @Published var books: [LibraryBook] = []
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var status = "粘贴小说详情页链接开始"
    @Published var shareURL: URL?
    @Published var failure: String?
    @Published var currentChapter = ""
    @Published var completedChapters = 0
    @Published var searchText = ""
    @Published var searchResults: [URL] = []
    private let service = NovelService()
    init() {
        let index = LibraryBook.directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([LibraryBook].self, from: data) { books = saved }
    }

    func search() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { status = "请输入书名"; return }
        isLoading = true; defer { isLoading = false }; do { searchResults = try await service.search(searchText); status = searchResults.isEmpty ? "没有找到结果" : "找到 \(searchResults.count) 个结果" } catch { status = "搜索失败：\(error.localizedDescription)" }
    }

    func load() async {
        failure = nil; isLoading = true; status = "读取书籍和目录…"; novel = nil; selected.removeAll(); shareURL = nil; defer { isLoading = false }
        do { let result = try await service.load(link); novel = result; selected = Set(result.chapters.map(\.id)); status = "已找到 \(result.chapters.count) 个章节" }
        catch { status = error.localizedDescription; failure = status }
    }

    func export(includeImages: Bool) async {
        guard let novel else { return }
        let chapters = novel.chapters.filter { selected.contains($0.id) }
        guard !chapters.isEmpty else { status = "至少选择一个章节"; return }
        shareURL = nil; failure = nil; completedChapters = 0; isLoading = true; progress = 0; status = "正在下载章节…"; defer { isLoading = false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images"); try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        do {
            var imageMap: [String: String] = [:]; var bodies: [String] = []
            for (index, chapter) in chapters.enumerated() {
                currentChapter = chapter.title; status = "正在下载 \(index + 1)/\(chapters.count)"
                let body = try await service.chapter(chapter, folder: images, images: &imageMap, includeImages: includeImages)
                bodies.append(EPUBBuilder.page(title: chapter.title, body: body)); completedChapters = index + 1; progress = Double(index + 1) / Double(chapters.count)
            }
            let oebps = root.appendingPathComponent("OEBPS"); for (index, body) in bodies.enumerated() { try Data(body.utf8).write(to: oebps.appendingPathComponent("chapter-\(index).xhtml")) }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Novel-\(UUID().uuidString).epub"); try? FileManager.default.removeItem(at: out); try EPUBBuilder.build(novel: novel, chapters: chapters, folder: root, destination: out)
            shareURL = out; status = "导出完成，共 \(chapters.count) 章"; save(novel: novel, url: out, count: chapters.count)
        } catch { status = error.localizedDescription; failure = status }
    }
    func save(novel: Novel, url: URL, count: Int) {
        do {
            let filename = UUID().uuidString + ".epub"
            try FileManager.default.copyItem(at: url, to: LibraryBook.directory.appendingPathComponent(filename))
            let item = LibraryBook(id: UUID(), title: novel.title, author: novel.author, filename: filename, date: Date(), chapterCount: count)
            books.insert(item, at: 0)
            try JSONEncoder().encode(books).write(to: LibraryBook.directory.appendingPathComponent("library.json"), options: .atomic)
        } catch { status = "导出成功，但保存书库失败：\(error.localizedDescription)" }
    }
}

