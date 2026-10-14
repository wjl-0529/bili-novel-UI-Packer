import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        TabView(selection: $model.activeTab) {
            NavigationStack { ImportView(model: model) }.tabItem { Label("导入", systemImage: "plus.circle") }.tag(0)
            NavigationStack { ExportProgressView(model: model) }.tabItem { Label("打包", systemImage: "shippingbox") }.tag(1)
            NavigationStack { LibraryView(model: model) }.tabItem { Label("书库", systemImage: "books.vertical") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }.tint(.indigo)
    }
}

struct ImportView: View {
    @ObservedObject var model: AppModel
    @State private var showBook = false
    @State private var source = BookSource.linovelib
    @State private var bookID = ""
    @State private var useID = true
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "book.pages.fill").font(.system(size: 38)).foregroundStyle(.indigo).padding(.bottom, 6)
                    Text("把喜欢的故事\n留在身边。").font(.largeTitle.bold())
                    Text("导入小说，选择章节，收藏为 EPUB。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 18)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                Picker("导入方式", selection: $useID) {
                    Text("书籍编号").tag(true)
                    Text("完整链接").tag(false)
                }.pickerStyle(.segmented)
                if useID {
                    Picker("小说站点", selection: $source) {
                        ForEach(BookSource.allCases) { site in Text(site.rawValue).tag(site) }
                    }
                    TextField("输入书籍编号，例如 5428", text: $bookID).keyboardType(.numberPad).accessibilityIdentifier("bookID")
                    if let url = source.bookURL(bookID) { Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                } else {
                    TextField("粘贴详情页链接", text: $model.link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("novelLink")
                }
                Button {
                    if useID, let url = source.bookURL(bookID) { model.link = url.absoluteString }
                    Task { await model.load(); showBook = model.novel != nil }
                } label: {
                    HStack { Label("查找书籍", systemImage: "magnifyingglass"); Spacer(); if model.isLoading { ProgressView() } }
                }.disabled(model.isLoading || (useID ? source.bookURL(bookID) == nil : model.link.isEmpty)).accessibilityIdentifier("loadNovel")
            } header: { Text("导入书籍") } footer: { Text("编号对应所选站点：例如 1.html，只需输入 1。") }
            Section {
                TextField("输入小说名称", text: $model.searchText).submitLabel(.search).onSubmit { Task { await model.search(source: source) } }
                Button("搜索") { Task { await model.search(source: source) } }.disabled(model.isLoading || model.searchText.isEmpty)
                ForEach(model.searchResults, id: \.self) { url in
                    Button { model.link = url.absoluteString; Task { await model.load(); showBook = model.novel != nil } } label: { Label(url.lastPathComponent, systemImage: "book.closed") }
                }
            } header: { Text("书名搜索") } footer: { Text("支持哔哩轻小说和轻小说文库。网站访问限制可能影响搜索与下载。") }
            Section("批量书籍") {
                TextEditor(text: $model.batchInput).frame(minHeight: 80).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("每本手动选择章节", isOn: $model.batchManual)
                Button("开始批量处理") { model.startBatch() }.disabled(model.isLoading || model.isBatchRunning || model.batchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !model.batchRemaining.isEmpty { Text("剩余 \(model.batchRemaining.count) 本").font(.caption).foregroundStyle(.secondary) }
            }
            if let failure = model.failure {
                Section("读取未完成") { Text(failure).font(.footnote).textSelection(.enabled).foregroundStyle(.red) }
            }
        }.navigationTitle("导入小说")
        .onChange(of: model.novel?.url) { _, url in if url != nil { showBook = true } }
        .navigationDestination(isPresented: $showBook) { if let novel = model.novel { BookDetailView(model: model, novel: novel) } }
    }
}

struct BookDetailView: View {
    @ObservedObject var model: AppModel
    let novel: Novel
    @State private var images = true
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    AsyncImage(url: novel.cover) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.indigo.opacity(0.12)).overlay(Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(.indigo)) }
                        .frame(width: 116,height: 160).clipShape(.rect(cornerRadius: 12)).shadow(color: .black.opacity(0.12), radius: 14,y: 8)
                    Text(novel.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(novel.author).font(.subheadline).foregroundStyle(.secondary)
                    Text("可下载 \(novel.chapters.count) 章").font(.caption).foregroundStyle(.indigo)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if !novel.summary.isEmpty { Section("简介") { Text(novel.summary).font(.subheadline).foregroundStyle(.secondary) } }
            Section("打包内容") {
                NavigationLink { ChapterPickerView(model: model, novel: novel) } label: {
                    HStack { Label("选择章节", systemImage: "list.bullet"); Spacer(); Text("\(model.selected.count) 章").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("chapterPicker")
                Toggle("包含插图", isOn: $images)
                Toggle("合并分卷为一个 EPUB", isOn: $model.combineVolumes)
                Toggle("正文添加章节标题", isOn: $model.addChapterTitles)
            }
            if novel.hiddenChapterCount > 0 {
                Section("未恢复章节") {
                    Text("已尝试邻章导航，以下章节地址仍不可用，未加入本次打包。").font(.footnote).foregroundStyle(.secondary)
                    ForEach(novel.unresolvedChapters, id: \.self) { title in Label(title, systemImage: "exclamationmark.triangle").font(.footnote) }
                }
            }
            Section { Link("查看原站", destination: novel.url) }
        }.navigationTitle("书籍详情").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.startExport(includeImages: images)
            } label: { Label("打包为 EPUB", systemImage: "shippingbox").frame(maxWidth: .infinity).padding(.vertical,8) }
            .buttonStyle(.glassProminent).disabled(model.selected.isEmpty || model.isLoading).padding(.horizontal,20).padding(.vertical,12)
        }
    }
}

struct ChapterPickerView: View {
    @ObservedObject var model: AppModel
    let novel: Novel
    @State private var query = ""
    var volumes: [String] { novel.chapters.reduce(into: []) { if !$0.contains($1.volume) { $0.append($1.volume) } } }
    var body: some View {
        List {
            ForEach(volumes,id: \.self) { volume in
                let chapters = novel.chapters.filter { $0.volume == volume && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                if !chapters.isEmpty {
                    Section {
                        Button {
                            let ids = Set(chapters.map(\.id)); if ids.isSubset(of: model.selected) { model.selected.subtract(ids) } else { model.selected.formUnion(ids) }
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
        }.navigationTitle("章节 · \(model.selected.count)/\(novel.chapters.count)").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query,prompt: "筛选章节")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("选择全部") { model.selected = Set(novel.chapters.map(\.id)) }
                    Button("取消全部") { model.selected.removeAll() }
                    Button("反向选择") { model.selected = Set(novel.chapters.map(\.id)).subtracting(model.selected) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

struct ExportProgressView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        List {
            if let started = model.exportStarted {
                Section {
                    Label(model.isExporting ? "正在打包" : model.shareURL != nil ? "EPUB 已就绪" : "打包已停止", systemImage: model.isExporting ? "shippingbox" : model.shareURL != nil ? "checkmark.circle.fill" : "pause.circle")
                        .font(.title2.bold()).foregroundStyle(.indigo).padding(.vertical, 8)
                    Text(model.exportTitle).font(.headline)
                    Text(model.exportStatus).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    ProgressView(value: model.progress).tint(.indigo)
                }
                Section("任务详情") {
                    LabeledContent("来源", value: model.exportSource)
                    LabeledContent("章节进度", value: "\(model.completedChapters) / \(model.exportTotal)")
                    if !model.currentChapter.isEmpty { LabeledContent("当前章节", value: model.currentChapter) }
                    LabeledContent("插图", value: model.exportIncludesImages ? "已下载 \(model.exportImages) 张" : "不包含")
                    LabeledContent("正文大小", value: ByteCountFormatter.string(fromByteCount: Int64(model.exportBytes), countStyle: .file))
                    LabeledContent("开始时间") { Text(started, style: .time) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("耗时", value: Duration.seconds(max(0, (model.exportEnded ?? context.date).timeIntervalSince(started))).formatted(.time(pattern: .hourMinuteSecond)))
                    }
                    if model.shareURL != nil { LabeledContent("EPUB 大小", value: ByteCountFormatter.string(fromByteCount: Int64(model.exportFileBytes), countStyle: .file)) }
                }
                Section {
                    ForEach(model.outputURLs, id: \.self) { url in
                        ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up") }
                    }
                    if model.isExporting { Button("取消打包", role: .destructive) { model.cancelExport() } }
                    if !model.isLoading, !model.isBatchRunning, !model.batchRemaining.isEmpty { Button("处理下一本") { model.continueBatch() } }
                    ShareLink(item: model.exportEvents.map { $0.date.formatted() + " " + $0.message }.joined(separator: "\n")) { Label("分享任务日志", systemImage: "doc.text") }
                }
                Section("任务记录") {
                    ForEach(model.exportEvents.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.message).font(.subheadline)
                            Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }
                }
            } else {
                ContentUnavailableView("还没有打包任务", systemImage: "shippingbox", description: Text("导入小说并选择章节后，点击“打包为 EPUB”。进度和结果都会保留在这里。"))
                Text("尚无任务").accessibilityIdentifier("emptyExport")
                Button("去导入小说") { model.activeTab = 0 }
            }
        }.navigationTitle("打包任务")
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
                    VStack(alignment: .leading,spacing: 5) { Text(book.title).font(.headline).lineLimit(2); Text(book.author).font(.caption).foregroundStyle(.secondary); Text("\(book.chapterCount) 章").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    ShareLink(item: book.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享 \(book.title)")
                }.padding(.vertical,6)
            }
        }.navigationTitle("我的书库").searchable(text: $query,prompt: "搜索收藏")
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("关于") { LabeledContent("版本",value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")).accessibilityIdentifier("appVersion"); LabeledContent("构建",value: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")) }
            Section("下载说明") { Text("章节与图片依次下载，避免触发站点限流。请在打包期间保持应用在前台。").font(.footnote).foregroundStyle(.secondary) }
            Section { Link("项目与更新",destination: URL(string: "https://github.com/wjl-0529/bili-novel-UI-Packer")!) }
        }.navigationTitle("设置")
    }
}

