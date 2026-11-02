import NaturalLanguage
import SwiftUI
import FrameTrailCore

struct LocalizedSourceText: View {
    let text: String
    var aliases: [NameAlias] = []
    @Environment(AppModel.self) private var model
    @State private var translation: String?
    @State private var showOriginal = false
    @State private var requested = false
    @State private var loading = false
    @State private var notice: String?

    private var needsTranslation: Bool {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)
        return model.localeIdentifier == "ru_RU" ? language == .english : language == .russian
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(showOriginal ? text : (translation ?? text)).textSelection(.enabled)
            if loading { ProgressView().controlSize(.small) }
            if translation != nil {
                Button(showOriginal ? L10n.text("Показать перевод") : L10n.text("Оригинал · перевод Apple")) { showOriginal.toggle() }
                    .font(.caption).foregroundStyle(Theme.accent)
            } else if needsTranslation && !loading {
                Button(L10n.text("Оригинал · перевести")) { requested.toggle() }
                    .font(.caption).foregroundStyle(Theme.accent)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(Theme.muted) }
        }
        .task(id: model.localeIdentifier + text + aliases.map { $0.original + $0.russian }.joined() + String(model.sourceTranslationEnabled) + String(requested)) {
            translation = nil; notice = nil; showOriginal = false
            guard needsTranslation, model.sourceTranslationEnabled || requested else { return }
            loading = true
            defer { loading = false }
            await model.assistant.translation.refreshReadiness()
            guard model.assistant.translation.readiness == .installed else {
                notice = L10n.text("Показан оригинал. Для перевода подготовь языки Apple в настройках.")
                return
            }
            do {
                let localized = model.localeIdentifier == "ru_RU"
                    ? try await model.assistant.translation.russianText(text, aliases: aliases)
                    : try await model.assistant.translation.englishTexts([text], aliases: aliases)[0]
                try Task.checkCancellation()
                translation = localized
            } catch is CancellationError {} catch { notice = L10n.text("Перевод недоступен. Показан оригинал.") }
        }
    }
}
