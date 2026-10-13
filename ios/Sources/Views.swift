import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        TabView {
            NavigationStack { ImportView(model: model) }.tabItem { Label("导入", systemImage: "plus.circle") }
            NavigationStack { LibraryView(model: model) }.tabItem { Label("书库", systemImage: "books.vertical") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }
        }.tint(.indigo)
    }
}

struct ImportView: View {
    @ObservedObject var model: AppModel
    @State private var showBook = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "book.pages.fill").font(.system(size: 38)).foregroundStyle(.indigo).padding(.bottom, 6)
                    Text("把喜欢的故事\n留在身边。").font(.largeTitle.bold())
                    Text("导入小说，选择章节，收藏为 EPUB。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 18)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section("小说链接") {
                TextField("粘贴详情页链接", text: $model.link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("novelLink")
                Button {
                    Task { await model.load(); showBook = model.novel != nil }
                } label: {
                    HStack { Label("读取小说", systemImage: "arrow.down.doc"); Spacer(); if model.isLoading { ProgressView() } }
                }.disabled(model.isLoading || model.link.isEmpty).accessibilityIdentifier("loadNovel")
            }
            Section("书名搜索") {
                TextField("输入小说名称", text: $model.searchText).submitLabel(.search).onSubmit { Task { await model.search() } }
                Button("搜索") { Task { await model.search() } }.disabled(model.isLoading || model.searchText.isEmpty)
                ForEach(model.searchResults, id: .self) { url in
                    Button { model.link = url.absoluteString; Task { await model.load(); showBook = model.novel != nil } } label: { Label(url.lastPathComponent, systemImage: "book.closed") }
                }
            } footer: { Text("支持哔哩轻小说和轻小说文库。网站访问限制可能影响搜索与下载。") }
            if let failure = model.failure {
                Section("读取未完成") { Text(failure).font(.footnote).textSelection(.enabled).foregroundStyle(.red) }
            }
        }.navigationTitle("导入小说")
        .navigationDestination(isPresented: $showBook) { if let novel = model.novel { BookDetailView(model: model, novel: novel) } }
    }
}

struct BookDetailView: View {
    @ObservedObject var model: AppModel
    let novel: Novel
    @State private var images = true
    @State private var showProgress = false
    @State private var operation: Task<Void,Never>?
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    AsyncImage(url: novel.cover) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.indigo.opacity(0.12)).overlay(Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(.indigo)) }
                        .frame(width: 116,height: 160).clipShape(.rect(cornerRadius: 12)).shadow(color: .black.opacity(0.12), radius: 14,y: 8)
                    Text(novel.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(novel.author).font(.subheadline).foregroundStyle(.secondary)
                    Text("可下载 (novel.chapters.count) 章").font(.caption).foregroundStyle(.indigo)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if !novel.summary.isEmpty { Section("简介") { Text(novel.summary).font(.subheadline).foregroundStyle(.secondary) } }
            Section("打包内容") {
                NavigationLink { ChapterPickerView(model: model, novel: novel) } label: {
                    HStack { Label("选择章节", systemImage: "list.bullet"); Spacer(); Text("(model.selected.count) 章").foregroundStyle(.secondary) }
                }
                Toggle("包含插图", isOn: $images)
            }
            if novel.hiddenChapterCount > 0 { Section { Label("有 (novel.hiddenChapterCount) 个章节链接未公开，暂未加入目录。", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary) } }
            Section { Link("查看原站", destination: novel.url) }
        }.navigationTitle("书籍详情").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showProgress = true
                operation = Task { await model.export(includeImages: images) }
            } label: { Label("打包为 EPUB", systemImage: "shippingbox").frame(maxWidth: .infinity).padding(.vertical,8) }
            .buttonStyle(.glassProminent).disabled(model.selected.isEmpty || model.isLoading).padding(.horizontal,20).padding(.vertical,12)
        }
        .sheet(isPresented: $showProgress) { ExportProgressView(model: model, cancel: { operation?.cancel() }).interactiveDismissDisabled(model.isLoading) }
    }
}

struct ChapterPickerView: View {
    @ObservedObject var model: AppModel
    let novel: Novel
    @State private var query = ""
    var volumes: [String] { novel.chapters.reduce(into: []) { if !$0.contains($1.volume) { $0.append($1.volume) } } }
    var body: some View {
        List {
            ForEach(volumes,id: .self) { volume in
                let chapters = novel.chapters.filter { $0.volume == volume && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                if !chapters.isEmpty {
                    Section {
                        Button {
                            let ids = Set(chapters.map(.id)); if ids.isSubset(of: model.selected) { model.selected.subtract(ids) } else { model.selected.formUnion(ids) }
                        } label: { HStack { Text(volume).font(.subheadline.bold()); Spacer(); Text(chapters.allSatisfy { model.selected.contains($0.id) } ? "取消本卷" : "选择本卷").font(.caption) } }
                        ForEach(chapters) { chapter in
                            Button {
                                if model.selected.contains(chapter.id) { model.selected.remove(chapter.id) } else { model.selected.insert(chapter.id) }
                            } label: {
                                HStack(alignment: .center,spacing: 12) {
                                    Image(systemName: model.selected.contains(chapter.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.selected.contains(chapter.id) ? Color.indigo : Color.secondary)
                                    Text(chapter.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                }.padding(.vertical,3)
                            }.accessibilityValue(model.selected.contains(chapter.id) ? "已选" : "未选")
                        }
                    }
                }
            }
        }.navigationTitle("章节 · (model.selected.count)/(novel.chapters.count)").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query,prompt: "筛选章节")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("选择全部") { model.selected = Set(novel.chapters.map(.id)) }
                    Button("取消全部") { model.selected.removeAll() }
                    Button("反向选择") { model.selected = Set(novel.chapters.map(.id)).subtracting(model.selected) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

struct ExportProgressView: View {
    @ObservedObject var model: AppModel
    let cancel: () -> Void
    @Environment(.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: model.isLoading ? "shippingbox" : model.shareURL != nil ? "checkmark.circle.fill" : "exclamationmark.triangle").font(.system(size: 56)).foregroundStyle(.indigo)
                Text(model.isLoading ? "正在整理故事" : model.shareURL != nil ? "EPUB 已就绪" : "打包未完成").font(.title2.bold())
                if model.isLoading {
                    ProgressView(value: model.progress).tint(.indigo)
                    Text("(model.completedChapters) / (model.selected.count) 章").font(.headline.monospacedDigit())
                    Text(model.currentChapter).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else { ScrollView { Text(model.status).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity) }.frame(maxHeight: 180) }
                Spacer()
                if let url = model.shareURL { ShareLink(item: url) { Label("保存或分享 EPUB",systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.glassProminent) }
                if model.isLoading { Button("取消打包",role: .cancel,action: cancel).buttonStyle(.glass) }
                else { Button("完成") { dismiss() }.buttonStyle(.glass) }
            }.padding(28).navigationTitle("打包任务").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        List {
            if model.books.isEmpty { ContentUnavailableView("收藏从这里开始",systemImage: "books.vertical",description: Text("打包好的小说会自动保存在书库。")) }
            ForEach(model.books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { book in
                HStack(spacing: 14) {
                    Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.indigo).frame(width: 48,height: 64).background(.indigo.opacity(0.08),in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading,spacing: 5) { Text(book.title).font(.headline).lineLimit(2); Text(book.author).font(.caption).foregroundStyle(.secondary); Text("(book.chapterCount) 章").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    ShareLink(item: book.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享 (book.title)")
                }.padding(.vertical,6)
            }
        }.navigationTitle("我的书库").searchable(text: $query,prompt: "搜索收藏")
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("关于") { LabeledContent("版本",value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")); LabeledContent("构建",value: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")) }
            Section("下载说明") { Text("章节与图片依次下载，避免触发站点限流。请在打包期间保持应用在前台。").font(.footnote).foregroundStyle(.secondary) }
            Section { Link("项目与更新",destination: URL(string: "https://github.com/wjl-0529/bili-novel-UI-Packer")!) }
        }.navigationTitle("设置")
    }
}
