import Foundation
import NaturalLanguage
import Observation
import Translation

nonisolated enum WorkTitle {
    /// Drops 【…】 promo blocks; keeps the original when nothing else is left.
    static func cleaned(_ title: String) -> String {
        let stripped = title.replacing(/【[^】]*】/, with: " ")
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

/// Translates work titles to Simplified Chinese with Apple's on-device Translation models.
/// The session is driven by `.translationTask(configuration)` attached once at the root view.
@Observable
final class TitleTranslator {
    private(set) var translations: [String: String] = [:]
    private(set) var configuration: TranslationSession.Configuration?
    private var pending: [String] = []
    private var requested: Set<String> = []
    private var running = false
    private var unavailable = false

    func display(_ title: String, translated: Bool) -> String {
        let cleaned = WorkTitle.cleaned(title)
        return translated ? translations[cleaned] ?? cleaned : cleaned
    }
    func request(_ title: String) {
        let cleaned = WorkTitle.cleaned(title)
        guard !unavailable, !requested.contains(cleaned), WorkTitle.isJapanese(cleaned) else { return }
        requested.insert(cleaned); pending.append(cleaned)
        guard !running else { return }
        running = true
        if configuration == nil {
            configuration = .init(source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "zh-Hans"))
        } else {
            configuration?.invalidate()
        }
    }
    func run(_ session: TranslationSession) async {
        defer { running = false }
        while !pending.isEmpty {
            let batch = pending; pending = []
            do {
                // The SDK types are not Sendable; the session is only ever used here, inside its translationTask.
                nonisolated(unsafe) let session = session
                nonisolated(unsafe) let requests = batch.map { TranslationSession.Request(sourceText: $0) }
                let responses = try await session.translations(from: requests)
                for response in responses { translations[response.sourceText] = response.targetText }
            } catch is CancellationError {
                requested.subtract(batch + pending); pending = [] // Retried when the cards appear again.
                return
            } catch {
                // Model download declined or translation unsupported here: keep original titles until relaunch.
                unavailable = true; pending = []
                return
            }
        }
    }
}
