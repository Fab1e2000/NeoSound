import Foundation
import NaturalLanguage
import Observation

nonisolated enum WorkTitle {
    /// Drops 【…】, […] and (…) blocks in full- and half-width forms; keeps the original when nothing else is left.
    static func cleaned(_ title: String) -> String {
        let stripped = title.replacing(/【[^】]*】|\[[^\]]*\]|［[^］]*］|\([^)]*\)|（[^）]*）/, with: " ")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? title : stripped
    }
    /// Only Japanese titles are translated; Chinese and other titles stay as they are.
    static func isJapanese(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese, .english, .korean]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .japanese
    }
}

/// DeepSeek chat-completions request/response shapes for batch title translation.
nonisolated enum DeepSeekTitleAPI {
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    static let model = "deepseek-flash"
    static let batchSize = 20
    static let system = """
    你是日本 ASMR 同人音声作品标题的译者，把日语标题译成简体中文，读者是中文 ASMR 圈的听众。
    - 用中文圈内通行的叫法，不要字面直译。参考：耳かき→掏耳，囁き→耳语，添い寝→陪睡，癒し/癒され→治愈，\
    バイノーラル→双耳立体声，耳舐め→舔耳，オノマトペ→拟声，催眠音声→催眠音声，甘々→甜甜的，\
    いちゃあま/イチャラブ→甜蜜恩爱，ダウナー→慵懒系，ヤンデレ→病娇，ツンデレ→傲娇，クーデレ→三无，\
    メスガキ→雌小鬼，ギャル→辣妹，地雷系→地雷系，お姉さん→大姐姐，後輩ちゃん→后辈酱，JK→女高中生，\
    ご奉仕→侍奉，お世話→照顾，おやすみ→晚安，安眠/快眠→助眠。
    - 网络用语、谐音梗、流行语按意思译成中文网络上对应的说法；保留 ♡、♪ 等符号和标点风格。
    - 人名、社团名、角色名保留原文；英文、数字、作品编号原样保留。
    - 译文简短自然，不解释，不加引号。
    输入是 JSON 数组，每项有 id 和 title。只输出 JSON，格式：{"translations":[{"id":0,"title":"译文"}]}，每个 id 都要返回。
    """
    static func request(titles: [String], apiKey: String) throws -> URLRequest {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"; r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let numbered = titles.enumerated().map { ["id": $0.offset, "title": $0.element] as [String: Any] }
        let list = String(decoding: try JSONSerialization.data(withJSONObject: numbered, options: [.sortedKeys]), as: UTF8.self)
        let body: [String: Any] = [
            "model": model,
            "thinking": ["type": "disabled"],
            "response_format": ["type": "json_object"],
            "max_tokens": 4000,
            "messages": [["role": "system", "content": system], ["role": "user", "content": list]],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }
    /// Maps translations back to their source titles. Filtered or truncated replies yield nothing.
    static func parse(_ data: Data, titles: [String]) throws -> [String: String] {
        struct Reply: Decodable { let choices: [Choice] }
        struct Choice: Decodable { let message: Message; let finish_reason: String? }
        struct Message: Decodable { let content: String? }
        struct Output: Decodable { let translations: [Item] }
        struct Item: Decodable { let id: Int; let title: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let choice = reply.choices.first, choice.finish_reason == "stop", let text = choice.message.content else { return [:] }
        let output = try JSONDecoder().decode(Output.self, from: Data(text.utf8))
        var result: [String: String] = [:]
        for item in output.translations where titles.indices.contains(item.id) {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { result[titles[item.id]] = title }
        }
        return result
    }
}

/// Translates Japanese work titles to Simplified Chinese with DeepSeek, caching every result on device.
@Observable
final class TitleTranslator {
    static let keyAccount = "deepseek-api-key"
    private(set) var translations: [String: String] = [:]
    private(set) var hasKey: Bool
    private(set) var lastError: String?
    private var pending: [String] = []
    private var requested: Set<String> = []
    private var running = false
    private let session: URLSession
    private let cacheURL: URL?
    private let readKey: () -> String?

    init(session: URLSession = .shared, cacheURL: URL? = TitleTranslator.defaultCacheURL, readKey: @escaping () -> String? = { TokenVault.read(account: TitleTranslator.keyAccount) }) {
        self.session = session; self.cacheURL = cacheURL; self.readKey = readKey
        hasKey = readKey() != nil
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            translations = cached
        }
    }
    static var defaultCacheURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "title-translations.json")
    }
    func setAPIKey(_ key: String?) throws {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        try TokenVault.save(key?.isEmpty == false ? key : nil, account: Self.keyAccount)
        hasKey = readKey() != nil
        lastError = nil
        requested.removeAll() // Untranslated titles retry with the new key.
    }
    /// `clean: false` keeps brackets, e.g. track names such as 耳かき（左）.
    func display(_ title: String, translated: Bool, clean: Bool = true) -> String {
        let cleaned = clean ? WorkTitle.cleaned(title) : title.trimmingCharacters(in: .whitespacesAndNewlines)
        return translated ? translations[cleaned] ?? cleaned : cleaned
    }
    func request(_ title: String, clean: Bool = true) {
        let cleaned = clean ? WorkTitle.cleaned(title) : title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasKey, translations[cleaned] == nil, !requested.contains(cleaned), WorkTitle.isJapanese(cleaned) else { return }
        requested.insert(cleaned); pending.append(cleaned)
        guard !running else { return }
        running = true
        Task { await drain() }
    }
    private func drain() async {
        defer { running = false }
        try? await Task.sleep(for: .milliseconds(300)) // Let the cards that just appeared join one request.
        while !pending.isEmpty, let key = readKey() {
            let batch = Array(pending.prefix(DeepSeekTitleAPI.batchSize))
            pending.removeFirst(batch.count)
            do {
                let (data, response) = try await session.data(for: DeepSeekTitleAPI.request(titles: batch, apiKey: key))
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    lastError = status == 401 ? "DeepSeek API Key 无效，请在设置中重新填写。" : status == 402 ? "DeepSeek 账户余额不足。" : "翻译服务暂时不可用（\(status)），稍后重试。"
                    if status == 401 { hasKey = false }
                    giveBack(batch); return
                }
                translations.merge(try DeepSeekTitleAPI.parse(data, titles: batch)) { _, new in new }
                lastError = nil
                saveCache()
            } catch {
                lastError = "翻译失败：\(error.localizedDescription)"
                giveBack(batch); return
            }
        }
    }
    /// Unsent and failed titles can be requested again the next time their cards appear.
    private func giveBack(_ batch: [String]) {
        requested.subtract(batch + pending); pending = []
    }
    private func saveCache() {
        guard let cacheURL, let data = try? JSONEncoder().encode(translations) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
