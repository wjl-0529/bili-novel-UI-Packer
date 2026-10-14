import Foundation
import ZIPFoundation

enum EPUBBuilder {
    static func page(title: String, body: String, addTitle: Bool = true) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN"><head><title>\(title.xml)</title><style>body{line-height:1.8}img{max-width:100%;height:auto}p{text-indent:2em}</style></head><body>\(addTitle ? "<h1>" + title.xml + "</h1>" : "")\(body)</body></html>
        """
    }

    static func build(novel: Novel, chapters: [Chapter], folder: URL, destination: URL) throws {
        let fm = FileManager.default
        let oebps = folder.appendingPathComponent("OEBPS")
        try fm.createDirectory(at: folder.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: folder.appendingPathComponent("mimetype"))
        let container = "<?xml version=\"1.0\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
        try Data(container.utf8).write(to: folder.appendingPathComponent("META-INF/container.xml"))
        let volumes = chapters.reduce(into: [String]()) { if !$0.contains($1.volume) { $0.append($1.volume) } }
        let navigation = volumes.map { volume in
            let entries = chapters.enumerated().filter { $0.element.volume == volume }
            let children = entries.map { "<li><a href=\"chapter-\($0.offset).xhtml\">\($0.element.title.xml)</a></li>" }.joined()
            return "<li><span>\(volume.xml)</span><ol>\(children)</ol></li>"
        }.joined()
        let nav = "<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>目录</title></head><body><nav epub:type=\"toc\" id=\"toc\"><h1>目录</h1><ol>\(navigation)</ol></nav></body></html>"
        try Data(nav.utf8).write(to: oebps.appendingPathComponent("nav.xhtml"))
        let ncxPoints = chapters.enumerated().map { "<navPoint id=\"n\($0.offset)\" playOrder=\"\($0.offset+1)\"><navLabel><text>\($0.element.title.xml)</text></navLabel><content src=\"chapter-\($0.offset).xhtml\"/></navPoint>" }.joined()
        let ncx = "<?xml version=\"1.0\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\"><head/><docTitle><text>\(novel.title.xml)</text></docTitle><navMap>\(ncxPoints)</navMap></ncx>"
        try Data(ncx.utf8).write(to: oebps.appendingPathComponent("toc.ncx"))
        let items = chapters.enumerated().map { "<item id=\"c\($0.offset)\" href=\"chapter-\($0.offset).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()
        let images = try fm.contentsOfDirectory(at: oebps.appendingPathComponent("images"), includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let imageItems = images.enumerated().map { index, url in
            let mime = url.pathExtension == "jpg" ? "image/jpeg" : "image/\(url.pathExtension)"
            return "<item id=\"img\(index)\" href=\"images/\(url.lastPathComponent)\" media-type=\"\(mime)\"\(url.lastPathComponent.hasPrefix("cover.") ? " properties=\"cover-image\"" : "")/>"
        }.joined()
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">urn:uuid:\(UUID().uuidString)</dc:identifier><dc:title>\(novel.title.xml)</dc:title><dc:creator>\(novel.author.xml)</dc:creator><dc:language>zh-CN</dc:language><dc:description>\(novel.summary.xml)</dc:description><dc:source>\(novel.url.absoluteString.xml)</dc:source><dc:publisher>\((novel.publisher ?? "").xml)</dc:publisher>\(novel.tags.map { "<dc:subject>" + $0.xml + "</dc:subject>" }.joined())<meta property="dcterms:modified">\(ISO8601DateFormatter().string(from: Date()))</meta></metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(items)\(imageItems)</manifest><spine toc="ncx">\(spine)</spine></package>
        """
        try Data(opf.utf8).write(to: oebps.appendingPathComponent("content.opf"))
        let archive = try Archive(url: destination, accessMode: .create)
        try archive.addEntry(with: "mimetype", relativeTo: folder, compressionMethod: .none)
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { throw NovelError.message("无法枚举 EPUB 文件。") }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true, url.lastPathComponent != "mimetype" {
                let path = String(url.path.dropFirst(folder.path.count + 1))
                try archive.addEntry(with: path, relativeTo: folder, compressionMethod: .deflate)
            }
        }
    }
}

