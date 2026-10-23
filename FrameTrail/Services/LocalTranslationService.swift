import Foundation
import NaturalLanguage
import Observation
import Translation
import CryptoKit
import FrameTrailCore

@MainActor
@Observable
final class LocalTranslationService {
    enum Readiness {
        case checking
        case installed
        case downloadRequired
        case unsupported
    }

    private(set) var readiness: Readiness = .checking
    private let russian = Locale.Language(identifier: "ru")
    private let english = Locale.Language(identifier: "en")
    private let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 2 * 1_024 * 1_024
        cache.countLimit = 128
        return cache
    }()

    func clearCache() { cache.removeAllObjects() }

    var isSupported: Bool { readiness == .installed || readiness == .downloadRequired }

    var message: String {
        switch readiness {
        case .checking: return L10n.text("Проверяю языки локального перевода Apple…")
        case .installed: return L10n.text("Русский через локальный перевод Apple. Вопрос и ответ обрабатываются на iPhone.")
        case .downloadRequired: return L10n.text("Для русского подготовь языки перевода Apple в настройках FrameTrail. Загрузка выполняется с разрешения в системном окне.")
        case .unsupported: return L10n.text("На этом устройстве перевод между русским и английским недоступен. Можно выбрать English.")
        }
    }

    func refreshReadiness() async {
        let availability = LanguageAvailability()
        let forward = await availability.status(from: russian, to: english)
        let reverse = await availability.status(from: english, to: russian)
        switch (forward, reverse) {
        case (.installed, .installed): readiness = .installed
        case (.installed, .supported), (.supported, .installed), (.supported, .supported): readiness = .downloadRequired
        default: readiness = .unsupported
        }
    }

    func englishTexts(_ texts: [String], aliases: [NameAlias] = []) async throws -> [String] {
        try Task.checkCancellation()
        let selected = texts.enumerated().filter { Self.needsRussianTranslation($0.element) }
        guard !selected.isEmpty else { return texts }
        try requireInstalled()
        let session = TranslationSession(installedSource: russian, target: english)
        let protected = selected.map { Self.protectedText($0.element, aliases: aliases, toRussian: false) }
        let requests = zip(selected, protected).map { TranslationSession.Request(sourceText: $0.1.text, clientIdentifier: String($0.0.offset)) }
        let responses = try await session.translations(from: requests)
        try Task.checkCancellation()
        var translated = texts
        guard responses.count == requests.count else { throw AssistantError(message: L10n.text("Перевод Apple вернул неполный результат. Попробуй ещё раз.")) }
        var seen: Set<Int> = []
        for response in responses {
            guard let identifier = response.clientIdentifier, let index = Int(identifier),
                  let position = selected.firstIndex(where: { $0.offset == index }), seen.insert(index).inserted,
                  let restored = protected[position].restored(response.targetText) else {
                throw AssistantError(message: L10n.text("Не удалось сохранить имена при переводе. Попробуй английский язык или уточни словарь."))
            }
            translated[index] = restored
        }
        return translated
    }

    func russianText(_ text: String, aliases: [NameAlias] = []) async throws -> String {
        if NLLanguageRecognizer.dominantLanguage(for: text) == .russian { return text }
        let signature = text + String(data: (try? JSONEncoder().encode(aliases)) ?? Data(), encoding: .utf8)!
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined() as NSString
        if let value = cache.object(forKey: key) { return value as String }
        try requireInstalled()
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: english, target: russian)
        let protected = Self.protectedText(text, aliases: aliases, toRussian: true)
        let responses = try await session.translations(from: [TranslationSession.Request(sourceText: protected.text)])
        try Task.checkCancellation()
        guard responses.count == 1, let restored = protected.restored(responses[0].targetText) else {
            throw AssistantError(message: L10n.text("Не удалось сохранить имена при переводе. Попробуй английский язык или уточни словарь."))
        }
        cache.setObject(restored as NSString, forKey: key, cost: restored.utf8.count)
        return restored
    }

    static func detectedNames(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName || tag == .placeName || tag == .organizationName {
                let name = String(text[range])
                if name.range(of: "^[A-Za-z][A-Za-z .’'-]{1,79}$", options: .regularExpression) != nil { names.insert(name) }
            }
            return names.count < 100
        }
        if let expression = try? NSRegularExpression(pattern: "\\b[A-Z]{2,6}\\b") {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { names.insert(String(text[range])) }
            }
        }
        return Array(names.sorted().prefix(100))
    }

    private static func protectedText(_ text: String, aliases: [NameAlias], toRussian: Bool) -> ProtectedTranslationText {
        var names = Dictionary(uniqueKeysWithValues: detectedNames(in: text).map { ($0, $0) })
        for segment in translationSegments(text) where segment.isProtected { names[segment.text] = segment.text }
        for alias in aliases {
            if toRussian { names[alias.original] = alias.russian }
            else { names[alias.russian] = alias.original }
        }
        return ProtectedTranslationText(text: text, names: names)
    }

    private func requireInstalled() throws {
        guard readiness == .installed else { throw AssistantError(message: message) }
    }

    static func needsRussianTranslation(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let language = NLLanguageRecognizer.dominantLanguage(for: text)
        if language == .english { return false }
        return language == .russian || text.range(of: "[\\p{IsCyrillic}]", options: .regularExpression) != nil
    }

    static func translationSegments(_ text: String) -> [(text: String, isProtected: Bool)] {
        guard let expression = try? NSRegularExpression(pattern: "\\[[^\\]\\n]{1,200}\\]|https?://[^\\s<>]+") else { return [(text, false)] }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var segments: [(text: String, isProtected: Bool)] = []
        var start = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            if start < range.lowerBound { segments.append((String(text[start..<range.lowerBound]), false)) }
            segments.append((String(text[range]), true))
            start = range.upperBound
        }
        if start < text.endIndex { segments.append((String(text[start...]), false)) }
        return segments
    }
}
