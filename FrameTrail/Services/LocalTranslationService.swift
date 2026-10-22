import Foundation
import NaturalLanguage
import Observation
import Translation

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

    var isSupported: Bool { readiness == .installed || readiness == .downloadRequired }

    var message: String {
        switch readiness {
        case .checking: return "Проверяю языки локального перевода Apple…"
        case .installed: return "Русский через локальный перевод Apple. Вопрос и ответ обрабатываются на iPhone."
        case .downloadRequired: return "Для русского подготовь языки перевода Apple в настройках FrameTrail. Загрузка выполняется с разрешения в системном окне."
        case .unsupported: return "На этом устройстве перевод между русским и английским недоступен. Можно выбрать English."
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

    func englishTexts(_ texts: [String]) async throws -> [String] {
        try Task.checkCancellation()
        let selected = texts.enumerated().filter { Self.needsRussianTranslation($0.element) }
        guard !selected.isEmpty else { return texts }
        try requireInstalled()
        let session = TranslationSession(installedSource: russian, target: english)
        let requests = selected.map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        let responses = try await session.translations(from: requests)
        try Task.checkCancellation()
        var translated = texts
        guard responses.count == requests.count else { throw AssistantError(message: "Перевод Apple вернул неполный результат. Попробуй ещё раз.") }
        for (item, response) in zip(selected, responses) {
            translated[item.offset] = response.targetText
        }
        return translated
    }

    func russianText(_ text: String) async throws -> String {
        try requireInstalled()
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: english, target: russian)
        var segments = Self.translationSegments(text)
        let selected = segments.enumerated().filter { !$0.element.isProtected && !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !selected.isEmpty else { return text }
        let requests = selected.map { TranslationSession.Request(sourceText: $0.element.text, clientIdentifier: String($0.offset)) }
        let responses = try await session.translations(from: requests)
        try Task.checkCancellation()
        guard responses.count == requests.count else { throw AssistantError(message: "Перевод Apple вернул неполный результат. Попробуй ещё раз.") }
        for (item, response) in zip(selected, responses) {
            let leading = item.element.text.prefix(while: \.isWhitespace)
            let trailing = item.element.text.reversed().prefix(while: \.isWhitespace).reversed()
            segments[item.offset].text = String(leading) + response.targetText.trimmingCharacters(in: .whitespacesAndNewlines) + String(trailing)
        }
        return segments.map(\.text).joined()
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
