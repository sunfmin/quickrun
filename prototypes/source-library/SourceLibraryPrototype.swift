// ============================================================================
// THROWAWAY PROTOTYPE — Source Library picker state model (PRD #27)
// Run:  swift prototypes/source-library/SourceLibraryPrototype.swift
// Not part of any SwiftPM target — lives outside Sources/ so it isn't compiled
// into the app. Delete (or lift the logic module) once it has answered its
// question. See NOTES.md.
//
// QUESTION
// --------
// Does the "Add from Library" state model feel right when driven by hand?
// Specifically the three decisions in #27's Implementation Decisions:
//   1. Selection spans category switches (tick in 中文词典, switch to 翻译, tick
//      more, then Add commits ALL of them).
//   2. Dedup is by urlTemplate, NOT name — a Source the user RENAMED still shows
//      as already-added and can't be re-added. (Seed below renames 必应词典 to
//      prove this: it still blocks re-add.)
//   3. Add mints a FRESH id and appends via the store; remove a Source then
//      re-add it and watch a NEW id appear.
// ============================================================================

import Foundation

// ===========================================================================
// PORTABLE LOGIC — pure, liftable into QuickRunKit. No I/O, no terminal code.
// This is the bit worth keeping; everything below the next banner is throwaway.
// ===========================================================================

struct Source: Equatable {
    let id: UUID
    var name: String
    var urlTemplate: String
}

struct CatalogEntry: Equatable {
    let name: String
    let urlTemplate: String
    let category: String
}

enum SourceLibrary {
    /// Ordered, de-duplicated category list in catalog order.
    static func categories(_ catalog: [CatalogEntry]) -> [String] {
        var seen = Set<String>(), out = [String]()
        for e in catalog where !seen.contains(e.category) { seen.insert(e.category); out.append(e.category) }
        return out
    }

    static func entries(_ catalog: [CatalogEntry], inCategory cat: String) -> [CatalogEntry] {
        catalog.filter { $0.category == cat }
    }

    /// Dedup key. By urlTemplate so a renamed Source is still recognised.
    static func isPresent(_ e: CatalogEntry, in sources: [Source]) -> Bool {
        sources.contains { $0.urlTemplate == e.urlTemplate }
    }

    /// THE operation. Each selected entry not already present (by urlTemplate)
    /// becomes a fresh Source appended to the user's list. `makeID` is injected
    /// so the real code passes UUID() and a test could pass a counter.
    static func add(_ selected: [CatalogEntry], to sources: [Source], makeID: () -> UUID) -> [Source] {
        var result = sources
        for e in selected where !result.contains(where: { $0.urlTemplate == e.urlTemplate }) {
            result.append(Source(id: makeID(), name: e.name, urlTemplate: e.urlTemplate))
        }
        return result
    }
}

// A representative slice of the #27 catalog — enough to feel category switching
// and cross-category selection. Not the full ~77.
let CATALOG: [CatalogEntry] = [
    .init(name: "Merriam-Webster", urlTemplate: "https://www.merriam-webster.com/dictionary/{q}", category: "英文词典"),
    .init(name: "Cambridge", urlTemplate: "https://dictionary.cambridge.org/dictionary/english/{q}", category: "英文词典"),
    .init(name: "Oxford Learner's", urlTemplate: "https://www.oxfordlearnersdictionaries.com/definition/english/{q}", category: "英文词典"),
    .init(name: "Etymonline", urlTemplate: "https://www.etymonline.com/search?q={q}", category: "英文词典"),

    .init(name: "必应词典", urlTemplate: "https://cn.bing.com/dict/search?q={q}", category: "中文词典"),
    .init(name: "有道词典", urlTemplate: "https://dict.youdao.com/w/{q}", category: "中文词典"),
    .init(name: "汉典", urlTemplate: "https://www.zdic.net/hans/{q}", category: "中文词典"),
    .init(name: "MDBG 汉英", urlTemplate: "https://www.mdbg.net/chinese/dictionary?wdqb={q}", category: "中文词典"),

    .init(name: "Google 翻译", urlTemplate: "https://translate.google.com/?sl=auto&tl=zh-CN&op=translate&text={q}", category: "翻译"),
    .init(name: "Papago", urlTemplate: "https://papago.naver.com/?sk=auto&tk=zh-CN&st={q}", category: "翻译"),
    .init(name: "Yandex 翻译", urlTemplate: "https://translate.yandex.com/?lang=en-zh&text={q}", category: "翻译"),

    .init(name: "Google", urlTemplate: "https://www.google.com/search?q={q}", category: "网页搜索"),
    .init(name: "DuckDuckGo", urlTemplate: "https://duckduckgo.com/?q={q}", category: "网页搜索"),
    .init(name: "Brave Search", urlTemplate: "https://search.brave.com/search?q={q}", category: "网页搜索"),

    .init(name: "MDN Web Docs", urlTemplate: "https://developer.mozilla.org/en-US/search?q={q}", category: "开发"),
    .init(name: "pkg.go.dev", urlTemplate: "https://pkg.go.dev/search?q={q}", category: "开发"),
    .init(name: "crates.io", urlTemplate: "https://crates.io/search?q={q}", category: "开发"),
]

// ===========================================================================
// THROWAWAY TUI SHELL — drives the pure module by hand. Delete with the file.
// ===========================================================================

// In-memory store. Seeded to mirror first-run defaults — BUT 必应词典 is renamed
// to prove dedup is by urlTemplate, not name: it still shows as added.
var sources: [Source] = [
    Source(id: UUID(), name: "必应词典 (我改的名字)", urlTemplate: "https://cn.bing.com/dict/search?q={q}"),
    Source(id: UUID(), name: "有道词典", urlTemplate: "https://dict.youdao.com/w/{q}"),
    Source(id: UUID(), name: "Google", urlTemplate: "https://www.google.com/search?q={q}"),
]

let cats = SourceLibrary.categories(CATALOG)
var catIdx = 0
var selected = Set<String>()   // keyed by urlTemplate (the dedup key)
var msg = "选 source 加入。注意 必应词典 已经显示为 added —— 即使被改了名。"

let B = "\u{001B}[1m", D = "\u{001B}[2m", R = "\u{001B}[0m"
let GRN = "\u{001B}[32m", YEL = "\u{001B}[33m"
func clear() { print("\u{001B}[2J\u{001B}[H", terminator: "") }
func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(4)) }
func host(_ t: String) -> String {
    t.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "{q}", with: "…").prefix(34).description
}

func render() {
    clear()
    print("\(B)=== Source Library prototype ===\(R) \(D)(throwaway · PRD #27)\(R)\n")

    print("\(B)YOUR SOURCES (\(sources.count))\(R)")
    for (i, s) in sources.enumerated() {
        print("  \(B)\(i + 1)\(R)  \(s.name.padding(toLength: 20, withPad: " ", startingAt: 0))  \(D)\(host(s.urlTemplate))  id:\(shortID(s.id))\(R)")
    }
    print("")

    // sidebar
    let bar = cats.enumerated().map { (i, c) in i == catIdx ? "\(B)[\(c)]\(R)" : "\(D)\(c)\(R)" }.joined(separator: "  ")
    print("\(B)LIBRARY\(R)   选中 selected: \(GRN)\(selected.count)\(R)")
    print("  \(bar)\n")

    // entries of current category
    let cat = cats[catIdx]
    for (i, e) in SourceLibrary.entries(CATALOG, inCategory: cat).enumerated() {
        let present = SourceLibrary.isPresent(e, in: sources)
        let mark: String
        if present { mark = "\(D)·\(R)" }
        else if selected.contains(e.urlTemplate) { mark = "\(GRN)✓\(R)" }
        else { mark = " " }
        let tail = present ? "  \(D)(added)\(R)" : ""
        let name = present ? "\(D)\(e.name)\(R)" : e.name
        print("  \(B)\(i + 1)\(R) [\(mark)] \(name)\(tail)")
    }

    print("\n\(YEL)\(msg)\(R)")
    print("\(D)[n]ext/[p]rev category   [1-9] toggle entry   [a]dd selected   [dN] remove source N   [q]uit\(R)")
    print("> ", terminator: "")
}

func toggle(_ n: Int) {
    let es = SourceLibrary.entries(CATALOG, inCategory: cats[catIdx])
    guard n >= 1, n <= es.count else { msg = "没有第 \(n) 项"; return }
    let e = es[n - 1]
    if SourceLibrary.isPresent(e, in: sources) { msg = "「\(e.name)」已加入，不能重复选（按 urlTemplate 去重）"; return }
    if selected.contains(e.urlTemplate) { selected.remove(e.urlTemplate) } else { selected.insert(e.urlTemplate) }
    msg = "切换分类，选中状态保留 —— 跨分类一起加。"
}

func addSelected() {
    let picks = CATALOG.filter { selected.contains($0.urlTemplate) }
    guard !picks.isEmpty else { msg = "没选任何 source"; return }
    let before = sources.count
    sources = SourceLibrary.add(picks, to: sources, makeID: { UUID() })
    let added = sources.count - before
    selected.removeAll()
    msg = "加入 \(added) 个。它们现在显示为 added，选中已清空。"
}

func removeSource(_ n: Int) {
    guard n >= 1, n <= sources.count else { msg = "没有第 \(n) 行"; return }
    let s = sources.remove(at: n - 1)
    msg = "删了「\(s.name)」。它的 catalog 条目又变成可加 —— 再加会拿到新的 id。"
}

render()
while let line = readLine() {
    let cmd = line.trimmingCharacters(in: .whitespaces).lowercased()
    switch cmd {
    case "q", "quit": clear(); print("bye."); exit(0)
    case "n": catIdx = (catIdx + 1) % cats.count; msg = "→ \(cats[catIdx])"
    case "p": catIdx = (catIdx - 1 + cats.count) % cats.count; msg = "→ \(cats[catIdx])"
    case "a": addSelected()
    default:
        if cmd.hasPrefix("d"), let n = Int(cmd.dropFirst()) { removeSource(n) }
        else if let n = Int(cmd) { toggle(n) }
        else { msg = "不认识：\(cmd)" }
    }
    render()
}
