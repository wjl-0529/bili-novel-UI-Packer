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
    private let service = NovelService()
    init() {
        let index = LibraryBook.directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([LibraryBook].self, from: data) { books = saved }
    }

    func load() async {
        isLoading = true; status = "读取书籍和目录…"; defer { isLoading = false }
        do { let result = try await service.load(link); novel = result; selected = Set(result.chapters.map(\.id)); status = "已找到 \(result.chapters.count) 个章节" }
        catch { status = error.localizedDescription }
    }

    func export(includeImages: Bool) async {
        guard let novel else { return }
        let chapters = novel.chapters.filter { selected.contains($0.id) }
        guard !chapters.isEmpty else { status = "至少选择一个章节"; return }
        isLoading = true; progress = 0; status = "正在下载章节…"; defer { isLoading = false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("OEBPS/images"); try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        do {
            var imageMap: [String: String] = [:]; var bodies: [String] = []
            for (index, chapter) in chapters.enumerated() {
                let body = try await service.chapter(chapter, folder: images, images: &imageMap, includeImages: includeImages)
                bodies.append(EPUBBuilder.page(title: chapter.title, body: body)); progress = Double(index + 1) / Double(chapters.count)
            }
            let oebps = root.appendingPathComponent("OEBPS"); for (index, body) in bodies.enumerated() { try Data(body.utf8).write(to: oebps.appendingPathComponent("chapter-\(index).xhtml")) }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("Novel-\(UUID().uuidString).epub"); try? FileManager.default.removeItem(at: out); try EPUBBuilder.build(novel: novel, chapters: chapters, folder: root, destination: out)
            shareURL = out; status = "导出完成，共 \(chapters.count) 章"; save(novel: novel, url: out, count: chapters.count)
        } catch { status = error.localizedDescription }
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

struct ContentView: View {
    @StateObject private var model = AppModel(); @State private var images = true
    var body: some View {
        TabView {
            NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) { Text("轻小说打包器").font(.largeTitle.bold()); Text("原生 SwiftUI · iOS 27 Liquid Glass").foregroundStyle(.secondary); input; if let novel = model.novel { book(novel) }; Text(model.status).font(.footnote).foregroundStyle(.secondary) }.padding(20) }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("主页") }.tabItem { Label("打包", systemImage: "shippingbox") }
            LibraryView(books: model.books).tabItem { Label("书库", systemImage: "books.vertical") }
        }.tint(.blue)
    }
    var input: some View { VStack(alignment: .leading, spacing: 12) { TextField("粘贴 bilinovel / linovelib / wenku8 链接", text: $model.link).textInputAutocapitalization(.never).keyboardType(.URL).padding(14).background(.thinMaterial, in: .rect(cornerRadius: 16)); Button { Task { await model.load() } } label: { Label(model.isLoading ? "处理中…" : "读取小说", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(model.isLoading) }.card() }
    func book(_ novel: Novel) -> some View { VStack(alignment: .leading, spacing: 14) { Text(novel.title).font(.title2.bold()); Text("作者：\(novel.author)").foregroundStyle(.secondary); Toggle("下载插图", isOn: $images); HStack { Button("全选") { model.selected = Set(novel.chapters.map(\.id)) }; Button("清空") { model.selected.removeAll() } }.buttonStyle(.glass); Text("章节 \(model.selected.count)/\(novel.chapters.count)").font(.headline); ForEach(novel.chapters) { chapter in Toggle(chapter.title, isOn: Binding(get: { model.selected.contains(chapter.id) }, set: { if $0 { model.selected.insert(chapter.id) } else { model.selected.remove(chapter.id) } })) }.toggleStyle(.switch); if model.isLoading { ProgressView(value: model.progress) }; Button { Task { await model.export(includeImages: images) } } label: { Label("导出 EPUB", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(model.isLoading); if let share = model.shareURL { ShareLink(item: share) { Label("分享 EPUB", systemImage: "shareplay") }.frame(maxWidth: .infinity) } }.card() }
}
struct LibraryView: View { let books: [LibraryBook]; var body: some View { NavigationStack { List(books) { book in VStack(alignment: .leading) { Text(book.title).font(.headline); Text("\(book.chapterCount) 章 · \(book.author)").font(.caption).foregroundStyle(.secondary); ShareLink(item: book.url) { Label("分享", systemImage: "square.and.arrow.up") } } }.navigationTitle("书库") } }
private extension View { func card() -> some View { padding(18).background { if #available(iOS 26, *) { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 24)) } else { RoundedRectangle(cornerRadius: 24).fill(.background) } } } }
