import Foundation

/// One ready-to-use entry in the built-in Source Library: a display name, a URL
/// template (the same `{q}` placeholder a Source uses), and the category it is
/// grouped under in the picker. `category` is library-only metadata — it is not
/// carried onto the `Source` the user ends up with.
public struct CatalogEntry: Equatable {
    public let name: String
    public let urlTemplate: String
    public let category: String

    public init(name: String, urlTemplate: String, category: String) {
        self.name = name
        self.urlTemplate = urlTemplate
        self.category = category
    }
}

/// The built-in, curated catalog of Sources the user can add from, plus the pure
/// operation that turns chosen entries into Sources. Bundled in the binary — the
/// single source of truth, no network (see PRD #27). Grows by editing `catalog`
/// and cutting a release.
public enum SourceLibrary {
    /// Categories in catalog order, de-duplicated.
    public static var categories: [String] {
        var seen = Set<String>(), ordered = [String]()
        for entry in catalog where !seen.contains(entry.category) {
            seen.insert(entry.category)
            ordered.append(entry.category)
        }
        return ordered
    }

    /// Entries belonging to `category`, in catalog order.
    public static func entries(in category: String) -> [CatalogEntry] {
        catalog.filter { $0.category == category }
    }

    /// Whether `entry` is already among `sources`. Keyed by `urlTemplate`, not
    /// name, so a Source the user renamed still counts as present.
    public static func isPresent(_ entry: CatalogEntry, in sources: [Source]) -> Bool {
        sources.contains { $0.urlTemplate == entry.urlTemplate }
    }

    /// Fresh Sources for the `entries` not already present (dedup by
    /// `urlTemplate`, including duplicates within `entries`). Each gets a new id
    /// from `makeID`. The order of `entries` is preserved.
    public static func newSources(
        for entries: [CatalogEntry],
        existing: [Source],
        makeID: () -> UUID = UUID.init
    ) -> [Source] {
        var present = Set(existing.map(\.urlTemplate))
        var minted = [Source]()
        for entry in entries where !present.contains(entry.urlTemplate) {
            present.insert(entry.urlTemplate)
            minted.append(Source(id: makeID(), name: entry.name, urlTemplate: entry.urlTemplate))
        }
        return minted
    }

    /// `sources` with the deduped, freshly-minted Sources for `entries` appended.
    public static func add(
        _ entries: [CatalogEntry],
        to sources: [Source],
        makeID: () -> UUID = UUID.init
    ) -> [Source] {
        sources + newSources(for: entries, existing: sources, makeID: makeID)
    }

    // MARK: - The catalog

    /// Verified `{q}` templates (see PRD #27 — researched and visually checked).
    /// Edit here to grow the library; a unit test guards that every template
    /// builds a valid URL.
    public static let catalog: [CatalogEntry] = [
        // ── 英文词典 ───────────────────────────────────────────────────────────
        e("Merriam-Webster", "https://www.merriam-webster.com/dictionary/{q}", "英文词典"),
        e("Cambridge", "https://dictionary.cambridge.org/dictionary/english/{q}", "英文词典"),
        e("Oxford Learner's", "https://www.oxfordlearnersdictionaries.com/definition/english/{q}", "英文词典"),
        e("Collins", "https://www.collinsdictionary.com/dictionary/english/{q}", "英文词典"),
        e("Dictionary.com", "https://www.dictionary.com/browse/{q}", "英文词典"),
        e("Thesaurus.com", "https://www.thesaurus.com/browse/{q}", "英文词典"),
        e("Wordnik", "https://www.wordnik.com/words/{q}", "英文词典"),
        e("Vocabulary.com", "https://www.vocabulary.com/dictionary/{q}", "英文词典"),
        e("Urban Dictionary", "https://www.urbandictionary.com/define.php?term={q}", "英文词典"),
        e("Wiktionary (EN)", "https://en.wiktionary.org/wiki/{q}", "英文词典"),
        e("The Free Dictionary", "https://www.thefreedictionary.com/{q}", "英文词典"),
        e("Longman (LDOCE)", "https://www.ldoceonline.com/dictionary/{q}", "英文词典"),
        e("Etymonline", "https://www.etymonline.com/search?q={q}", "英文词典"),
        e("WordReference", "https://www.wordreference.com/definition/{q}", "英文词典"),

        // ── 中文词典 ───────────────────────────────────────────────────────────
        e("有道词典", "https://dict.youdao.com/w/{q}", "中文词典"),
        e("必应词典", "https://cn.bing.com/dict/search?q={q}", "中文词典"),
        e("百度汉语", "https://hanyu.baidu.com/s?wd={q}", "中文词典"),
        e("汉典", "https://www.zdic.net/hans/{q}", "中文词典"),
        e("海词词典", "https://dict.cn/{q}", "中文词典"),
        e("MDBG 汉英", "https://www.mdbg.net/chinese/dictionary?wdqb={q}", "中文词典"),
        e("萌典（繁體）", "https://www.moedict.tw/{q}", "中文词典"),
        e("教育部國語辭典簡編本", "https://dict.concised.moe.edu.tw/search.jsp?md=1&word={q}", "中文词典"),

        // ── 日文词典 ───────────────────────────────────────────────────────────
        e("Jisho", "https://jisho.org/search/{q}", "日文词典"),
        e("Weblio 英和/和英", "https://ejje.weblio.jp/content/{q}", "日文词典"),
        e("Weblio 国語", "https://www.weblio.jp/content/{q}", "日文词典"),
        e("英辞郎 on the WEB", "https://eow.alc.co.jp/search?q={q}", "日文词典"),
        e("Tangorin", "https://tangorin.com/words?search={q}", "日文词典"),
        e("Kotobank", "https://kotobank.jp/word/{q}", "日文词典"),

        // ── 韩文词典 ───────────────────────────────────────────────────────────
        e("Naver 사전", "https://dict.naver.com/search.dict?query={q}", "韩文词典"),
        e("Daum 사전", "https://dic.daum.net/search.do?q={q}", "韩文词典"),

        // ── 多语对译 ───────────────────────────────────────────────────────────
        e("Linguee", "https://www.linguee.com/english-german/search?source=auto&query={q}", "多语对译"),
        e("Glosbe", "https://glosbe.com/en/de/{q}", "多语对译"),
        e("Reverso Context", "https://context.reverso.net/translation/english-french/{q}", "多语对译"),
        e("PONS", "https://en.pons.com/translate/english-german/{q}", "多语对译"),
        e("Leo", "https://dict.leo.org/german-english/{q}", "多语对译"),
        e("Larousse (FR)", "https://www.larousse.fr/dictionnaires/francais/{q}", "多语对译"),
        e("DWDS (DE)", "https://www.dwds.de/wb/{q}", "多语对译"),
        e("Treccani (IT)", "https://www.treccani.it/vocabolario/{q}/", "多语对译"),
        e("RAE / DLE (ES)", "https://dle.rae.es/{q}", "多语对译"),

        // ── 翻译 ───────────────────────────────────────────────────────────────
        e("Google 翻译", "https://translate.google.com/?sl=auto&tl=zh-CN&op=translate&text={q}", "翻译"),
        e("DeepL", "https://www.deepl.com/translator#en/zh/{q}", "翻译"),
        e("Bing 翻译", "https://www.bing.com/translator/?from=en&to=zh-Hans&text={q}", "翻译"),
        e("百度翻译", "https://fanyi.baidu.com/#auto/zh/{q}", "翻译"),
        e("Papago", "https://papago.naver.com/?sk=auto&tk=zh-CN&st={q}", "翻译"),
        e("Yandex 翻译", "https://translate.yandex.com/?lang=en-zh&text={q}", "翻译"),

        // ── 网页搜索 ───────────────────────────────────────────────────────────
        e("Google", "https://www.google.com/search?q={q}", "网页搜索"),
        e("Bing", "https://www.bing.com/search?q={q}", "网页搜索"),
        e("DuckDuckGo", "https://duckduckgo.com/?q={q}", "网页搜索"),
        e("Brave Search", "https://search.brave.com/search?q={q}", "网页搜索"),
        e("百度", "https://www.baidu.com/s?wd={q}", "网页搜索"),
        e("Yandex", "https://yandex.com/search/?text={q}", "网页搜索"),
        e("Startpage", "https://www.startpage.com/sp/search?query={q}", "网页搜索"),
        e("Ecosia", "https://www.ecosia.org/search?q={q}", "网页搜索"),
        e("Perplexity", "https://www.perplexity.ai/search?q={q}", "网页搜索"),
        e("Kagi", "https://kagi.com/search?q={q}", "网页搜索"),
        e("Google Scholar", "https://scholar.google.com/scholar?q={q}", "网页搜索"),

        // ── 百科参考 ───────────────────────────────────────────────────────────
        e("Wikipedia (EN)", "https://en.wikipedia.org/wiki/{q}", "百科参考"),
        e("Wikipedia（中文）", "https://zh.wikipedia.org/wiki/{q}", "百科参考"),
        e("百度百科", "https://baike.baidu.com/item/{q}", "百科参考"),
        e("Britannica", "https://www.britannica.com/search?query={q}", "百科参考"),
        e("Wolfram Alpha", "https://www.wolframalpha.com/input?i={q}", "百科参考"),
        e("Quora", "https://www.quora.com/search?q={q}", "百科参考"),

        // ── 开发技术 ───────────────────────────────────────────────────────────
        e("MDN Web Docs", "https://developer.mozilla.org/en-US/search?q={q}", "开发技术"),
        e("GitHub 代码", "https://github.com/search?q={q}&type=code", "开发技术"),
        e("GitHub 仓库", "https://github.com/search?q={q}&type=repositories", "开发技术"),
        e("npm", "https://www.npmjs.com/search?q={q}", "开发技术"),
        e("pkg.go.dev", "https://pkg.go.dev/search?q={q}", "开发技术"),
        e("PyPI", "https://pypi.org/search/?q={q}", "开发技术"),
        e("crates.io", "https://crates.io/search?q={q}", "开发技术"),
        e("Stack Overflow", "https://stackoverflow.com/search?q={q}", "开发技术"),
        e("DevDocs", "https://devdocs.io/#q={q}", "开发技术"),
        e("Can I Use", "https://caniuse.com/?search={q}", "开发技术"),
        e("Docker Hub", "https://hub.docker.com/search?q={q}", "开发技术"),

        // ── 媒体其他 ───────────────────────────────────────────────────────────
        e("YouTube", "https://www.youtube.com/results?search_query={q}", "媒体其他"),
        e("IMDb", "https://www.imdb.com/find/?q={q}", "媒体其他"),
        e("Amazon", "https://www.amazon.com/s?k={q}", "媒体其他"),
        e("Google 地图", "https://www.google.com/maps/search/{q}", "媒体其他"),
        e("Google 图片", "https://www.google.com/search?tbm=isch&q={q}", "媒体其他"),
        e("Reddit", "https://www.reddit.com/search/?q={q}", "媒体其他"),
        e("X (Twitter)", "https://x.com/search?q={q}", "媒体其他"),
        e("知乎", "https://www.zhihu.com/search?type=content&q={q}", "媒体其他"),
    ]

    /// Terse constructor used only to keep the catalog table readable.
    private static func e(_ name: String, _ urlTemplate: String, _ category: String) -> CatalogEntry {
        CatalogEntry(name: name, urlTemplate: urlTemplate, category: category)
    }
}
