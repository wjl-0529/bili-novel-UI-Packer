import Foundation
import WebKit
import UIKit

@MainActor enum RenderedChapter {
    private static func evaluate(_ view: WKWebView, script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
            }
        }
    }
    static func load(_ url: URL) async throws -> String {
        let view = WKWebView(frame: CGRect(x: 0,y: 0,width: 390,height: 844))
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        view.alpha = 0.01
        window?.addSubview(view)
        view.load(URLRequest(url: url))
        defer { view.stopLoading(); view.removeFromSuperview() }
        var previous = ""; var stable = 0
        for _ in 0..<90 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            guard let result = try? await evaluate(view, script: "JSON.stringify({ready:document.readyState,text:(document.querySelector('#acontent, .bcontent')||{}).innerText||'',html:document.documentElement.outerHTML})"),
                  let json = result as? String, let bytes = json.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: bytes) as? [String:String] else { continue }
            let text = value["text"] ?? ""
            let invalid = ["无法完美使用", "內容加載失敗", "内容加载失败", "请使用〔Chrome", "Just a moment"]
            if value["ready"] == "complete", text.count > 100, !invalid.contains(where: text.contains) {
                stable = text == previous ? stable+1 : 0
                if stable >= 3, let html = value["html"] { return html }
            }
            previous = text
        }
        throw NovelError.message("正文未完成加载，站点可能要求浏览器验证或暂时不可用。未生成 EPUB。")
    }
}
