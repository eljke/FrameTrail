import SwiftUI
import SafariServices
import UniformTypeIdentifiers
import FrameTrailCore
import Translation

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var apiToken = ""
    @State private var busy = false
    @State private var authorization: AuthorizationPage?
    @State private var awaitingApproval = false
    @State private var error: String?
    @State private var notice: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument = LibraryDocument(data: Data())
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var preparationStep = 0

    private var modelStatus: AssistantAvailability { model.assistant.availability(localeIdentifier: model.localeIdentifier) }

    private static var versionLabel: String {
        let bundle = Bundle.main
        let release = bundle.url(forResource: "VERSION", withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
        let version = release ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return L10n.text("%@ · сборка %@", String(describing: version), String(describing: build))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "film.stack.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FrameTrail").font(.title2.bold())
                        Text(Self.versionLabel).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("appVersion")
                    }
                }.padding(.vertical, 8)
            }
            Section {
                Picker(L10n.text("Язык приложения"), selection: $model.localeIdentifier) {
                    Text(L10n.text("Русский")).tag("ru_RU")
                    Text("English").tag("en_US")
                }.accessibilityIdentifier("appLanguage")
            }
            Section {
                NavigationLink {
                    Form { AccountSettingsSection() }.navigationTitle(L10n.text("Аккаунт FrameTrail"))
                } label: { Label(L10n.text("Аккаунт FrameTrail"), systemImage: "person.crop.circle") }
                NavigationLink {
                    Form { assistantSettings }.navigationTitle("Apple Intelligence")
                } label: { Label("Apple Intelligence", systemImage: "sparkles") }
                NavigationLink {
                    Form { catalogSettings }.navigationTitle(L10n.text("TMDB и каталоги"))
                } label: { Label(L10n.text("TMDB и каталоги"), systemImage: "film.stack") }
            }
            Section {
                NavigationLink { StorageView() } label: { Label(L10n.text("Память"), systemImage: "internaldrive") }
                    .accessibilityIdentifier("storageSettings")
                NavigationLink {
                    Form { backupSettings }.navigationTitle(L10n.text("Резервная копия"))
                } label: { Label(L10n.text("Резервная копия"), systemImage: "externaldrive") }
            }
            Section {
                NavigationLink { QuickGuideView() } label: { Label(L10n.text("Краткий гид"), systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("openQuickGuide")
                NavigationLink {
                    Form { aboutSettings }.navigationTitle(L10n.text("О приложении"))
                } label: { Label(L10n.text("О приложении"), systemImage: "info.circle") }
                Link(destination: URL(string: "https://github.com/eljke/FrameTrail/issues")!) {
                    Label(L10n.text("Сообщить об ошибке"), systemImage: "ladybug")
                }
            }
            if let error { Section { ErrorNotice(message: error) } }
            if let notice { Section { Text(notice).font(.footnote).foregroundStyle(Theme.accent) } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(L10n.text("Настройки")).navigationBarTitleDisplayMode(.inline)
        .task { await model.assistant.refreshAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.assistant.refreshAvailability() } }
        }
        .translationTask(translationConfiguration) { session in await prepareTranslation(using: session) }
        .sheet(item: $authorization, onDismiss: {
            if awaitingApproval { Task { await finishLogin() } }
        }) { SafariPage(url: $0.url).ignoresSafeArea() }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "FrameTrail-library") { result in
            if case .failure(let failure) = result { error = L10n.error(failure) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (attributes.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try library.importData(data)
                notice = L10n.text("Библиотека восстановлена. Новые записи объединены с текущими по дате изменения.")
                error = nil
            } catch { self.error = L10n.error(error) }
        }
    }

    private var assistantSettings: some View {
        Group {
            Section {
                Label(modelStatus.isAvailable ? L10n.text("Локальная модель готова") : L10n.text("Модель недоступна"), systemImage: modelStatus.isAvailable ? "checkmark.shield" : "exclamationmark.circle")
                Text(modelStatus.message).font(.footnote).foregroundStyle(.secondary)
                if model.assistant.usesRussianTranslation {
                    Text(model.assistant.translation.message).font(.footnote).foregroundStyle(.secondary)
                    if model.assistant.translation.readiness == .downloadRequired {
                        Button(L10n.text("Подготовить русский перевод")) { beginTranslationPreparation() }.disabled(busy)
                    }
                    if preparationStep > 0 { ProgressView(L10n.text("Подготавливаю языки Apple…")) }
                }
                Text(L10n.text("Если модель не поддерживает русский напрямую, вопрос и разрешённые источники переводятся на английский, ответ — обратно на русский. Всё выполняется на iPhone. Языки перевода загружаются отдельно, занимают системное место и доступны другим приложениям. Перевод может неточно передать имена и смысл; оригиналы источников сохранены."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L10n.text("Помощник на устройстве")) }
        }
    }

    private var catalogSettings: some View {
        Group {
            Section {
                if let account = model.account {
                    Label(account.displayName ?? account.username, systemImage: "person.crop.circle.fill")
                    Text("TMDB · @\(account.username)").font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("Импортировать список TMDB")) { Task { await importWatchlist() } }.disabled(busy)
                    Button(L10n.text("Отключить TMDB"), role: .destructive) { Task { busy = true; await model.signOut(library: library); busy = false } }.disabled(busy)
                } else {
                    Label(L10n.text("Импорт из TMDB"), systemImage: "list.and.film")
                    Button(L10n.text("Войти через TMDB")) { Task { await beginLogin() } }.disabled(busy || !model.hasCatalogToken)
                    if awaitingApproval {
                        Button(L10n.text("Я подтвердил вход в TMDB")) { Task { await finishLogin() } }.disabled(busy)
                        Button(L10n.text("Отменить вход"), role: .cancel) {
                            awaitingApproval = false
                            Task { await model.auth.cancelAuthorization() }
                        }.disabled(busy)
                    }
                }
                Text(L10n.text("TMDB — дополнительное подключение для импорта списка просмотра. Оно не меняет аккаунт FrameTrail или активную библиотеку."))
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView() }
            } header: { Text(L10n.text("Подключение TMDB")) }
            Section {
                Label(model.hasCatalogToken ? L10n.text("TMDB подключён") : L10n.text("Работают TVmaze и Wikidata"), systemImage: model.hasCatalogToken ? "checkmark.circle" : "globe")
                SecureField("TMDB API Read Access Token", text: $apiToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(apiToken.isEmpty ? L10n.text("Удалить токен TMDB") : L10n.text("Сохранить токен")) { Task { await saveToken() } }
                    .disabled(busy || (apiToken.isEmpty && !model.hasCatalogToken))
                Link(L10n.text("Получить токен в настройках TMDB"), destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                Text(L10n.text("Нужен API Read Access Token, а не пароль. Он открывает каталог TMDB и вход в аккаунт. Без него поиск фильмов и сериалов остаётся доступен через другие источники."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L10n.text("Расширенный каталог")) }
        }
    }

    private var backupSettings: some View {
        Group {
            Section {
                Button(L10n.text("Экспортировать библиотеку")) {
                    do { exportDocument = LibraryDocument(data: try library.exportData()); exporting = true }
                    catch { self.error = L10n.error(error) }
                }
                Button(L10n.text("Импортировать резервную копию")) { importing = true }
            } header: { Text(L10n.text("Данные и место")) }
        }
    }

    private var aboutSettings: some View {
        Group {
            Section {
                Label(L10n.text("Диалоги обрабатываются на iPhone"), systemImage: "iphone.gen3")
                Label(L10n.text("Без рекламы и аналитических SDK"), systemImage: "hand.raised")
                Text(L10n.text("Поисковые запросы отправляются выбранным каталогам. При входе в FrameTrail карточки, прогресс и личные итоги хранятся в Supabase. Текст обсуждения обрабатывается локально. Подключение TMDB подтверждается на его сайте."))
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink(L10n.text("Источники и лицензии")) { AttributionView() }
                Link(L10n.text("Исходный код и сообщения об ошибках"), destination: URL(string: "https://github.com/eljke/FrameTrail")!)
            } header: { Text(L10n.text("О приложении")) }
        }
    }

    private func saveToken() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.auth.setTMDBReadToken(apiToken.isEmpty ? nil : apiToken)
            try await model.refreshAccountState(library: library)
            model.catalogDidChange()
            apiToken = ""
            awaitingApproval = false
            authorization = nil
            notice = model.hasCatalogToken ? L10n.text("Токен сохранён в Keychain.") : L10n.text("Токен удалён.")
        } catch {
            self.error = L10n.error(error)
            do { try await model.refreshAccountState(library: library) }
            catch { self.error = L10n.error(error) }
        }
    }

    private func beginTranslationPreparation() {
        busy = true
        error = nil
        preparationStep = 1
        translationConfiguration = .init(source: Locale.Language(identifier: "ru"), target: Locale.Language(identifier: "en"))
    }

    private func prepareTranslation(using session: TranslationSession) async {
        let step = preparationStep
        guard step > 0 else { return }
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            if step == 1 {
                preparationStep = 2
                translationConfiguration = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ru"))
                return
            }
            await model.assistant.refreshAvailability()
            if model.assistant.translation.readiness == .installed {
                model.localeIdentifier = "ru_RU"
                notice = L10n.text("Русский перевод готов. Вопросы и ответы обрабатываются локально.")
            }
            preparationStep = 0
            translationConfiguration = nil
            busy = false
        } catch {
            self.error = L10n.error(error)
            await model.assistant.refreshAvailability()
            preparationStep = 0
            translationConfiguration = nil
            busy = false
        }
    }

    private func beginLogin() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let url = try await model.auth.beginAuthorization()
            authorization = AuthorizationPage(url: url)
            awaitingApproval = true
        } catch { self.error = L10n.error(error) }
    }

    private func finishLogin() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.finishAuthorization(library: library)
            awaitingApproval = false
            notice = L10n.text("TMDB подключён. Можно импортировать список просмотра.")
        } catch ServiceError.http(401) {
            self.error = L10n.text("TMDB пока не подтвердил вход. Одобри доступ на сайте и нажми «Я подтвердил вход» или начни заново.")
        } catch is CancellationError {
        } catch { self.error = L10n.error(error) }
    }

    private func importWatchlist() async {
        busy = true
        error = nil
        defer { busy = false }
        let accountID = library.activeAccountID
        do {
            let titles = try await model.auth.watchlist()
            guard accountID == library.activeAccountID else { return }
            let added = try library.addTitles(titles)
            notice = L10n.text("Добавлено: %@, получено: %@. Существующие записи сохранены. Импорт ограничен первыми 10 страницами каждого типа.", String(describing: added), String(describing: titles.count))
        } catch { self.error = L10n.error(error) }
    }
}

private struct AuthorizationPage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct AttributionView: View {
    var body: some View {
        List {
            Section(L10n.text("Каталоги")) {
                Link("TMDB", destination: URL(string: "https://www.themoviedb.org")!)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.").font(.footnote)
                Image("TMDBLogo").resizable().scaledToFit().frame(width: 100, height: 73).accessibilityLabel("TMDB")
                Link("TVmaze · CC BY-SA", destination: URL(string: "https://www.tvmaze.com/api")!)
                Link("Wikidata · CC0", destination: URL(string: "https://www.wikidata.org/wiki/Wikidata:Licensing")!)
            }
            Section(L10n.text("Сюжетные материалы")) {
                Text(L10n.text("Материалы Wikipedia распространяются по CC BY-SA 4.0. Пересказ и выбранные фрагменты могут быть сокращены; ссылка на исходную редакцию доступна возле материала. Пользовательские тексты хранятся только в его библиотеке.")).font(.footnote)
                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
            }
            Section(L10n.text("Приложение")) {
                Text("FrameTrail · MIT License · © 2026 Ilya Kuzmenko").font(.footnote)
                Text(L10n.text("Apple Foundation Models — системная технология Apple. Доступность зависит от устройства, региона, настроек Apple Intelligence и языка.")).font(.footnote)
            }
        }.navigationTitle(L10n.text("Источники"))
    }
}
