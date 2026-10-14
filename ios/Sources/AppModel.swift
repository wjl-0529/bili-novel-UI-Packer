import Foundation
import SwiftUI
import UIKit

@main struct BiliNovelApp: App { var body: some Scene { WindowGroup { ContentView() } } }

@MainActor final class AppModel: ObservableObject {
    @Published var link = ""
    @Published var novel: Novel?
    @Published var selected = Set<String>()
    @Published var books: [LibraryBook] = []
    @Published var isLoading = false
    @Published var isLookupActive = false
    @Published var progress: Double = 0
    @Published var status = "粘贴小说详情页链接开始"
    @Published var shareURL: URL?
    @Published var failure: String?
    @Published var currentChapter = ""
    @Published var completedChapters = 0
    @Published var searchText = ""
    @Published var searchResults: [URL] = []
    @Published var activeTab = 0
    @Published var outputURLs: [URL] = []
    @Published var combineVolumes = false
    @Published var addChapterTitles = false
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
        guard !isLoading, !isBatchRunning, exportTask == nil else { return }
        activeTab = 1
        exportTask = Task { await export(includeImages: includeImages) }
    }
    func cancelExport() { exportTask?.cancel() }
    private func record(_ message: String) { exportStatus = message; exportEvents.append(ExportEvent(message: message)) }
    @Published var batchInput = ""
    @Published var batchManual = false
    @Published var batchRemaining: [String] = []
    @Published var isBatchRunning = false
    func startBatch() {
        guard !isLoading, exportTask == nil else { return }
        let links = batchInput.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !links.isEmpty else { return }
        for link in links {
            do { _ = try NovelService.supportedURL(link) }
            catch { failure = error.localizedDescription; return }
        }
        batchRemaining = links
        exportTask = Task { await runBatch() }
    }
    private func runBatch() async {
        isBatchRunning = true
        defer { isBatchRunning = false; exportTask = nil }
        while !batchRemaining.isEmpty {
            if Task.isCancelled { batchRemaining = []; return }
            link = batchRemaining.removeFirst()
            await load()
            guard novel != nil else { batchRemaining = []; return }
            if batchManual { activeTab = 0; return }
            activeTab = 1; combineVolumes = false; addChapterTitles = false
            await export(includeImages: true)
            if failure != nil || Task.isCancelled { batchRemaining = []; return }
        }
    }
    func continueBatch() { guard !isLoading else { return }; exportTask = Task { await runBatch() } }
    private let service: NovelService
    init(service: NovelService = NovelService()) {
        self.service = service
        let index = LibraryBook.directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([LibraryBook].self, from: data) { books = saved }
    }

    private var lookupTask: Task<Void, Never>?
    func startLookup() {
        guard !isLoading, lookupTask == nil else { return }
        lookupTask = Task { await load(); lookupTask = nil }
    }
    func startSearch(source: BookSource) {
        guard !isLoading, lookupTask == nil else { return }
        lookupTask = Task { await search(source: source); lookupTask = nil }
    }
    func cancelLookup() { lookupTask?.cancel() }
    func search(source: BookSource = .linovelib) async {
        guard !isLoading else { return }
        failure = nil
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请输入书名"; return }
        let query = searchText
        let reader = service
        isLoading = true; isLookupActive = true; status = "正在搜索（最多等待 30 秒）…"; defer { isLoading = false; isLookupActive = false }
        do {
            searchResults = try await withThrowingTaskGroup(of: [URL].self) { group in
                group.addTask { try await reader.search(query, source: source) }
                group.addTask { try await Task.sleep(for: .seconds(30)); throw NovelError.message("搜索超时。源站可能拒绝访问，请改用书籍编号或粘贴完整链接。") }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            status = searchResults.isEmpty ? "没有找到结果" : "找到 \(searchResults.count) 个结果"
        } catch is CancellationError { status = "已取消搜索" }
        catch { status = "搜索失败：\(error.localizedDescription)"; failure = status }
    }

    func load() async {
        guard !isLoading else { return }
        failure = nil; isLoading = true; isLookupActive = true; status = "读取书籍和目录…"; novel = nil; selected.removeAll(); defer { isLoading = false; isLookupActive = false }
        let input = link
        let reader = service
        do {
            let result = try await withThrowingTaskGroup(of: Novel.self) { group in
                group.addTask { try await reader.load(input, progress: { message in await MainActor.run { self.status = message } }) }
                group.addTask { try await Task.sleep(for: .seconds(600)); throw NovelError.message("读取超时。源站可能拒绝访问，请改用书籍编号或粘贴可打开的链接。") }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            novel = result; selected = Set(result.chapters.map(\.id)); status = "已找到 \(result.chapters.count) 个章节"
        } catch is CancellationError { status = "已取消读取" }
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
        defer { isExporting = false; exportEnded = Date(); if !isBatchRunning { exportTask = nil } }
        outputURLs = []; shareURL = nil; failure = nil; completedChapters = 0; isLoading = true; progress = 0; status = "正在下载章节…"; defer { isLoading = false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images"); try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        do {
            var imageMap: [String: String] = [:]; var bodies: [String] = []
            for (index, chapter) in chapters.enumerated() {
                currentChapter = chapter.title; exportStatus = "正在下载：" + chapter.title; status = "正在下载 \(index + 1)/\(chapters.count)"
                let body = try await service.chapter(chapter, folder: images, images: &imageMap, includeImages: includeImages)
                for warning in await service.takeWarnings() { record(warning) }
                exportBytes += body.utf8.count; exportImages = imageMap.count
                record("已完成：" + chapter.title)
                bodies.append(EPUBBuilder.page(title: chapter.title, body: body, addTitle: addChapterTitles)); completedChapters = index + 1; progress = Double(index + 1) / Double(chapters.count)
            }
            try Task.checkCancellation()
            status = "正在生成 EPUB…"; record(status)
            let volumes = chapters.reduce(into: [String]()) { if !$0.contains($1.volume) { $0.append($1.volume) } }
            let groups = combineVolumes ? [chapters] : volumes.map { volume in chapters.filter { $0.volume == volume } }
            for group in groups {
                try Task.checkCancellation()
                var book = novel
                if !combineVolumes, let volume = group.first?.volume { book = Novel(title: novel.title + " " + volume, author: novel.author, summary: novel.summary, cover: novel.volumeCovers[volume] ?? novel.cover, url: novel.url, chapters: group, publisher: novel.publisher, tags: novel.tags, seriesTitle: novel.title) }
                let package = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: package) }
                let target = package.appendingPathComponent("OEBPS/images")
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                for (index,item) in group.enumerated() {
                    guard let originalIndex = chapters.firstIndex(of: item) else { continue }
                    try Data(bodies[originalIndex].utf8).write(to: package.appendingPathComponent("OEBPS/chapter-\(index).xhtml"))
                }
                let groupMarkup = group.compactMap { item in chapters.firstIndex(of: item).map { bodies[$0] } }.joined()
                let groupImages = imageMap.values.filter { groupMarkup.contains("images/" + $0) }
                for name in groupImages { try FileManager.default.copyItem(at: images.appendingPathComponent(name), to: target.appendingPathComponent(name)) }
                if let cover = book.cover {
                    do {
                        let bytes = try await service.data(cover, referer: book.url)
                        if let ext = NovelService.imageExtension(bytes) { try bytes.write(to: target.appendingPathComponent("cover." + ext)) }
                    } catch is CancellationError { throw CancellationError() }
                    catch { record("封面下载失败：" + error.localizedDescription) }
                }
                if !(try FileManager.default.contentsOfDirectory(atPath: target.path)).contains(where: { $0.hasPrefix("cover.") }) {
                    let names = groupImages.sorted()
                    let portrait = names.first { name in
                        guard let image = UIImage(contentsOfFile: target.appendingPathComponent(name).path) else { return false }
                        return image.size.width < image.size.height
                    } ?? names.first
                    if let name = portrait { try FileManager.default.copyItem(at: target.appendingPathComponent(name), to: target.appendingPathComponent("cover." + URL(fileURLWithPath: name).pathExtension)) }
                }
                let filename = book.title.replacingOccurrences(of: #"[/:*?"<>|\\]"#, with: " ", options: .regularExpression).prefix(100)
                let outputFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
                let out = outputFolder.appendingPathComponent(String(filename) + ".epub")
                try EPUBBuilder.build(novel: book, chapters: group, folder: package, destination: out)
                exportFileBytes += (try out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                outputURLs.append(out); shareURL = out
                save(novel: book, url: out, count: group.count)
                record("已生成：" + out.lastPathComponent)
            }
            status = "导出完成，共 \(chapters.count) 章、\(outputURLs.count) 个 EPUB"; record(status)
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

