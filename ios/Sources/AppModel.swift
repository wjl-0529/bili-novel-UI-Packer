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
        isLoading = true; status = "读取书籍和目录…"; novel = nil; selected.removeAll(); shareURL = nil; defer { isLoading = false }
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
    @StateObject private var model = AppModel()
    @State private var images = true
    @State private var chapterQuery = ""
    @State private var operation: Task<Void, Never>?
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("轻小说 · 1.1.0", systemImage: "book.pages.fill").font(.title.bold())
                            Text("发现故事 · 挑选章节 · 离线珍藏").foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                        input
                        if let novel = model.novel { detail(novel); catalog(novel) }
                        if !model.isLoading && model.novel == nil {
                            ContentUnavailableView("从一本书开始", systemImage: "books.vertical", description: Text("输入书名搜索，或粘贴小说详情页链接。支持哔哩轻小说与轻小说文库。"))
                        }
                        Label(model.status, systemImage: model.isLoading ? "hourglass" : "info.circle").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("发现")
                .safeAreaInset(edge: .bottom) {
                    if model.novel != nil { exportBar }
                }
            }.tabItem { Label("发现", systemImage: "magnifyingglass") }
            LibraryView(model: model).tabItem { Label("书库", systemImage: "books.vertical") }
        }.tint(.blue)
    }
    private var input: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("查找小说").font(.headline)
            HStack {
                TextField("输入书名", text: $model.searchText).submitLabel(.search).onSubmit { startSearch() }
                Button(action: startSearch) { Image(systemName: "magnifyingglass").padding(4) }.buttonStyle(.glass).accessibilityLabel("搜索小说")
            }.padding(12).background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            ForEach(model.searchResults, id: \.self) { url in
                Button { model.link = url.absoluteString; startLoad() } label: {
                    HStack { Image(systemName: "book.closed"); Text(url.lastPathComponent).font(.subheadline); Spacer(); Image(systemName: "chevron.right") }.padding(.vertical, 8)
                }
            }
            Divider()
            Label("通过链接导入", systemImage: "link").font(.subheadline.bold())
            TextField("https://…/novel/123.html", text: $model.link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).padding(12).background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            Button(action: startLoad) { Label("读取书籍与目录", systemImage: "arrow.down.doc").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
        }.padding(18).background(.background, in: .rect(cornerRadius: 22)).disabled(model.isLoading)
    }
    private func startSearch() { operation = Task { await model.search() } }
    private func startLoad() { operation = Task { await model.load() } }
    private func detail(_ novel: Novel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: novel.cover) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius: 12).fill(.blue.opacity(0.12)).overlay(Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(.blue)) }.frame(width: 84, height: 116).clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    Text(novel.title).font(.title2.bold())
                    Text(novel.author).foregroundStyle(.secondary)
                    Label("\(novel.chapters.count) 章", systemImage: "list.bullet").font(.caption)
                    Link("查看原站", destination: novel.url).font(.caption)
                }
            }
            if !novel.summary.isEmpty { Text(novel.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(6) }
            if novel.hiddenChapterCount > 0 { Label("原站隐藏了 \(novel.hiddenChapterCount) 个章节链接，这些章节尚未加入下载目录。", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
            Toggle("包含插图", isOn: $images).disabled(model.isLoading)
        }.padding(18).background(.background, in: .rect(cornerRadius: 22))
    }
    private func catalog(_ novel: Novel) -> some View {
        let volumes = novel.chapters.reduce(into: [String]()) { if !$0.contains($1.volume) { $0.append($1.volume) } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack { Text("选择章节").font(.title3.bold()); Spacer(); Text("已选 \(model.selected.count)").font(.caption).foregroundStyle(.secondary) }
            TextField("筛选章节标题", text: $chapterQuery).padding(12).background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            GlassEffectContainer {
                HStack {
                    Button("全选") { model.selected = Set(novel.chapters.map(\.id)) }
                    Button("清空") { model.selected.removeAll() }
                    Button("反选") { model.selected = Set(novel.chapters.map(\.id)).subtracting(model.selected) }
                }.buttonStyle(.glass)
            }
            ForEach(volumes, id: \.self) { volume in
                VolumeSelectionView(title: volume, chapters: novel.chapters.filter { $0.volume == volume }, query: chapterQuery, selected: $model.selected)
            }
        }.padding(18).background(.background, in: .rect(cornerRadius: 22)).disabled(model.isLoading)
    }
    private var exportBar: some View {
        VStack(spacing: 10) {
            if model.isLoading { ProgressView(value: model.progress); Text(model.status).font(.caption).lineLimit(2) }
            GlassEffectContainer {
                HStack {
                    if model.isLoading {
                        Button("取消", role: .cancel) { operation?.cancel() }.buttonStyle(.glass)
                    } else {
                        Button { operation = Task { await model.export(includeImages: images) } } label: { Label("打包 \(model.selected.count) 章", systemImage: "shippingbox.fill").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(model.selected.isEmpty)
                        if let url = model.shareURL { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.glass).accessibilityLabel("分享 EPUB") }
                    }
                }
            }
        }.padding(16).background(.bar)
    }
}

struct VolumeSelectionView: View {
    let title: String
    let chapters: [Chapter]
    let query: String
    @Binding var selected: Set<String>
    @State private var expanded = false
    private var visible: [Chapter] { chapters.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { expanded.toggle() } label: {
                    HStack { Image(systemName: expanded ? "chevron.down" : "chevron.right"); Text(title).font(.headline); Text("\(chapters.filter { selected.contains($0.id) }.count)/\(chapters.count)").font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
                Spacer()
                Button(chapters.allSatisfy { selected.contains($0.id) } ? "取消整卷" : "选择整卷") {
                    let ids = Set(chapters.map(\.id)); if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
                }.font(.caption).buttonStyle(.bordered)
            }
            if expanded || !query.isEmpty {
                ForEach(visible) { chapter in
                    Button { if selected.contains(chapter.id) { selected.remove(chapter.id) } else { selected.insert(chapter.id) } } label: {
                        HStack(alignment: .top) { Image(systemName: selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(chapter.id) ? Color.blue : Color.secondary); Text(chapter.title).foregroundStyle(.primary).multilineTextAlignment(.leading); Spacer() }.padding(.vertical, 7)
                    }.buttonStyle(.plain).accessibilityLabel("\(chapter.title)，\(selected.contains(chapter.id) ? "已选择" : "未选择")")
                }
            }
        }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                if model.books.isEmpty { ContentUnavailableView("书库还是空的", systemImage: "books.vertical", description: Text("打包完成的 EPUB 会保存在这里。")) }
                ForEach(model.books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { book in
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed.fill").font(.title).foregroundStyle(.blue).frame(width: 48, height: 64).background(.blue.opacity(0.08), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) { Text(book.title).font(.headline); Text(book.author).font(.subheadline).foregroundStyle(.secondary); Text("\(book.chapterCount) 章 · \(book.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        ShareLink(item: book.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享 \(book.title)")
                    }.padding(.vertical, 6)
                }
            }.navigationTitle("我的书库").searchable(text: $query, prompt: "搜索已下载的小说")
        }
    }
}
