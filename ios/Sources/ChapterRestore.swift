import Foundation
import JavaScriptCore
import SwiftSoup

struct ChapterRestore {
    let fixed: Int
    let seedMultiplier: Int64
    let seedOffset: Int64
    let a: Int64
    let c: Int64
    let mod: Int64

    // Only numerical expressions are evaluated; downloaded scripts are never executed.
    static func number(_ source: String) -> Int64? {
        let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count < 300,
              clean.range(of: #"^[0-9a-fA-FxX\s()+*/%~^<>\-]+$"#, options: .regularExpression) != nil,
              let context = JSContext(), let result = context.evaluateScript("(" + clean + ")") else { return nil }
        let value = result.toDouble()
        guard context.exception == nil, value.isFinite, abs(value) < 9_007_199_254_740_991 else { return nil }
        return Int64(value)
    }

    static func parse(_ js: String) throws -> ChapterRestore {
        let seedPattern = #"var\s+[_$a-zA-Z0-9]+\s*=\s*[^;]*?Number\s*\(\s*[_$a-zA-Z0-9]+\s*\)\s*,\s*([^,)]+?)\s*\)\s*,\s*([^,)]+?)\s*\)\s*,"#
        let lcgPattern = #"([_$a-zA-Z0-9]+)\s*=\s*[^;]*?\(\s*\1\s*,\s*([^,)]+?)\s*\)\s*,\s*([^,)]+?)\s*\)\s*,\s*([^;)]+?)\s*\)\s*;"#
        if let multiplier = js.capture(seedPattern, group: 1).flatMap(number),
           let offset = js.capture(seedPattern, group: 2).flatMap(number),
           let a = js.capture(lcgPattern, group: 2).flatMap(number),
           let c = js.capture(lcgPattern, group: 3).flatMap(number),
           let mod = js.capture(lcgPattern, group: 4).flatMap(number),
           multiplier > 0, offset >= 0, a > 0, c >= 0, mod > max(a,c) {
            return ChapterRestore(fixed: 20, seedMultiplier: multiplier, seedOffset: offset, a: a, c: c, mod: mod)
        }
        let seedPatternPlain = #"=\s*([^;]*Number\s*\(\s*chapterId\s*\)[^;]*)\s*;"#
        let lcgPatternPlain = #"=\s*(\(\s*([_$a-zA-Z0-9]+)\s*\*[^;]+?\))\s*%\s*([^;]+)\s*;"#
        if let seed = js.capture(seedPatternPlain), let left = js.capture(lcgPatternPlain, group: 1),
           let variable = js.capture(lcgPatternPlain, group: 2), let mod = js.capture(lcgPatternPlain, group: 3).flatMap(number) {
            let normalized = seed.replacingOccurrences(of: #"Number\s*\(\s*chapterId\s*\)"#, with: "chapterId", options: .regularExpression)
            let zero = number(normalized.replacingOccurrences(of: "chapterId", with: "0"))
            let one = number(normalized.replacingOccurrences(of: "chapterId", with: "1"))
            let escaped = NSRegularExpression.escapedPattern(for: variable)
            let c = number(left.replacingOccurrences(of: "\\b" + escaped + "\\b", with: "0", options: .regularExpression))
            let a1 = number(left.replacingOccurrences(of: "\\b" + escaped + "\\b", with: "1", options: .regularExpression))
            if let zero, let one, let c, let a1, mod > max(a1-c,c), a1 > c {
                let fixed = js.capture(#"if\s*\(\s*[_$a-zA-Z0-9]+\s*>\s*(\d+)\s*\)"#).flatMap(Int.init) ?? 20
                return ChapterRestore(fixed: fixed, seedMultiplier: one-zero, seedOffset: zero, a: a1-c, c: c, mod: mod)
            }
        }
        throw NovelError.message("原站正文还原规则已变化，未能解析 chapterlog 参数。")
    }

    func order(count: Int, chapterID: Int64) throws -> [Int] {
        let prefix = min(max(fixed,0),count)
        var tail = Array(prefix..<count)
        let (product, overflow) = chapterID.multipliedReportingOverflow(by: seedMultiplier)
        let (initial, overflow2) = product.addingReportingOverflow(seedOffset)
        guard !overflow, !overflow2, initial >= 0 else { throw NovelError.message("还原参数溢出。") }
        var seed = initial
        if tail.count > 1 {
            for i in stride(from: tail.count-1, through: 1, by: -1) {
                let (value, overflow) = seed.multipliedReportingOverflow(by: a)
                let (sum, overflow2) = value.addingReportingOverflow(c)
                guard !overflow, !overflow2 else { throw NovelError.message("还原参数溢出。") }
                seed = sum % mod
                let j = Int(Double(seed)/Double(mod)*Double(i+1))
                tail.swapAt(i,j)
            }
        }
        return Array(0..<prefix) + tail
    }

    func restore(_ content: Element, chapterID: Int64) throws {
        let nodes = content.getChildNodes()
        var slots: [Int] = []; var paragraphs: [Node] = []
        for (i,node) in nodes.enumerated() {
            if let element = node as? Element, element.tagName() == "p", !((try element.html()).filter { !$0.isWhitespace }).isEmpty { slots.append(i); paragraphs.append(node) }
        }
        let indices = try order(count: paragraphs.count, chapterID: chapterID)
        var restored = paragraphs
        for i in paragraphs.indices { restored[indices[i]] = paragraphs[i] }
        var html = ""
        var slotMap: [Int: Node] = [:]
        for (i,slot) in slots.enumerated() { slotMap[slot] = restored[i] }
        for (i,node) in nodes.enumerated() { html += try (slotMap[i] ?? node).outerHtml() }
        try content.html(html)
    }
}
