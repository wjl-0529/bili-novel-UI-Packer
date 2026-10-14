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
    @Published var activeTab = 0
    @Published var exportStatus = ""
    @Published var exportTitle = ""
    @Published var exportSource = ""
    @Published var exportTotal = 0
    @Published var exportImages = 0
    @Published var exportBytes = 0
    @Published var exportFileBytes = 0
    @Published var exportIncludesImages = true
    @Published var exportStarted: Date?
    @Published var exportEnded: Date?
    @Published var exportEvents: [ExportEvent] = []
    @Published var isExporting = false
    private var exportTask: Task<Void, Never>?
    func startExport(includeImages: Bool) {
        guard !isLoading, exportTask == nil else { return }
        activeTab = 1
        exportTask = Task { await export(includeImages: includeImages) }
    }
    func cancelExport() { exportTask?.cancel() }
    private func record(_ message: String) { exportStatus = message; exportEvents.append(ExportEvent(message: message)) }
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
        guard !isLoading else { return }
        failure = nil; isLoading = true; status = "读取书籍和目录…"; novel = nil; selected.removeAll(); defer { isLoading = false }
        do { let result = try await service.load(link); novel = result; selected = Set(result.chapters.map(\.id)); status = "已找到 \(result.chapters.count) 个章节" }
        catch { status = error.localizedDescription; failure = status }
    }

    func export(includeImages: Bool) async {
        guard let novel else { return }
        let chapters = novel.chapters.filter { selected.contains($0.id) }
        guard !chapters.isEmpty else { status = "至少选择一个章节"; return }
        exportTitle = novel.title; exportSource = novel.url.host ?? ""
        exportTotal = chapters.count; exportIncludesImages = includeImages
        exportImages = 0; exportBytes = 0; exportFileBytes = 0
        exportStarted = Date(); exportEnded = nil; exportEvents = []; currentChapter = ""
        isExporting = true
        record("开始打包，共 \(chapters.count) 章")
        defer { isExporting = false; exportEnded = Date(); exportTask = nil }
        shareURL = nil; failure = nil; completedChapters = 0; isLoading = true; progress = 0; status = "正在下载章节…"; defer { isLoading = false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images"); try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        do {
            var imageMap: [String: String] = [:]; var bodies: [String] = []
            for (index, chapter) in chapters.enumerated() {
                currentChapter = chapter.title; exportStatus = "正在下载：" + chapter.title; status = "正在下载 \(index + 1)/\(chapters.count)"
                let body = try await service.chapter(chapter, folder: images, images: &imageMap, includeImages: includeImages)
                exportBytes += body.utf8.count; exportImages = imageMap.count
                record("已完成：" + chapter.title)
                bodies.append(EPUBBuilder.page(title: chapter.title, body: body)); completedChapters = index + 1; progress = Double(index + 1) / Double(chapters.count)
            }
            try Task.checkCancellation()
            status = "正在生成 EPUB…"; record(status)
            let oebps = root.appendingPathComponent("OEBPS"); for (index, body) in bodies.enumerated() { try Data(body.utf8).write(to: oebps.appendingPathComponent("chapter-\(index).xhtml")) }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Novel-\(UUID().uuidString).epub"); try? FileManager.default.removeItem(at: out); try EPUBBuilder.build(novel: novel, chapters: chapters, folder: root, destination: out)
            exportFileBytes = (try out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            record("EPUB 生成完成")
            shareURL = out; status = "导出完成，共 \(chapters.count) 章"; save(novel: novel, url: out, count: chapters.count)
        } catch is CancellationError {
            status = "已取消打包"; record(status)
        } catch { status = error.localizedDescription; failure = status; record("失败：" + status) }
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


