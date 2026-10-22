import SwiftUI
import SafariServices
import UniformTypeIdentifiers
import FrameTrailCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @State private var apiToken = ""
    @State private var busy = false
    @State private var authorization: AuthorizationPage?
    @State private var awaitingApproval = false
    @State private var error: String?
    @State private var notice: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument = LibraryDocument(data: Data())
    @State private var clearMaterials = false

    private var modelStatus: AssistantAvailability { model.assistant.availability(localeIdentifier: model.localeIdentifier) }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "film.stack.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FrameTrail").font(.title2.bold())
                        Text("1.0.0 · Beta 1").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("appVersion")
                    }
                }.padding(.vertical, 8)
            }
            Section {
                Label(modelStatus.isAvailable ? "Локальная модель готова" : "Модель недоступна", systemImage: modelStatus.isAvailable ? "checkmark.shield" : "exclamationmark.circle")
                Text(modelStatus.message).font(.footnote).foregroundStyle(.secondary)
                Picker("Язык ответов", selection: $model.localeIdentifier) {
                    Text("English").tag("en_US")
                    Text("Русский").tag("ru_RU").disabled(!model.assistant.supports(locale: Locale(identifier: "ru_RU")))
                }
                Text("Поддержку русского определяет установленная модель Apple. Если язык недоступен, ответы на нём не генерируются. Облачной подмены модели нет.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Помощник на устройстве") }
            Section {
                if let account = model.account {
                    Label(account.displayName ?? account.username, systemImage: "person.crop.circle.fill")
                    Text("TMDB · @\(account.username)").font(.caption).foregroundStyle(.secondary)
                    Button("Импортировать список TMDB") { Task { await importWatchlist() } }.disabled(busy)
                    Button("Выйти из аккаунта", role: .destructive) { Task { busy = true; await model.signOut(library: library); busy = false } }.disabled(busy)
                } else {
                    Label("Гостевая библиотека", systemImage: "person.crop.circle")
                    Button("Войти через TMDB") { Task { await beginLogin() } }.disabled(busy || !model.hasCatalogToken)
                    if awaitingApproval {
                        Button("Я подтвердил вход в TMDB") { Task { await finishLogin() } }.disabled(busy)
                        Button("Отменить вход", role: .cancel) { awaitingApproval = false }
                    }
                }
                Text("Каждый аккаунт имеет отдельную локальную библиотеку. Импорт списка TMDB выполняется по запросу; автоматической облачной синхронизации прогресса и диалогов нет.")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView() }
            } header: { Text("Аккаунт") }
            Section {
                Label(model.hasCatalogToken ? "TMDB подключён" : "Работают TVmaze и каталог iTunes", systemImage: model.hasCatalogToken ? "checkmark.circle" : "globe")
                SecureField("TMDB API Read Access Token", text: $apiToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(apiToken.isEmpty ? "Удалить токен TMDB" : "Сохранить токен") { Task { await saveToken() } }
                    .disabled(busy || (apiToken.isEmpty && !model.hasCatalogToken))
                Link("Получить токен в настройках TMDB", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                Text("Нужен API Read Access Token, а не пароль. Он открывает каталог TMDB и вход в аккаунт. Без него поиск фильмов и сериалов остаётся доступен через другие источники.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Расширенный каталог") }
            Section {
                LabeledContent("Файлы библиотек", value: ByteCountFormatter.string(fromByteCount: Int64(library.bytesOnDisk), countStyle: .file))
                LabeledContent("Историй в аккаунте", value: String(library.entries.count))
                Button("Экспортировать библиотеку") {
                    do { exportDocument = LibraryDocument(data: try library.exportData()); exporting = true }
                    catch { self.error = error.localizedDescription }
                }
                Button("Импортировать резервную копию") { importing = true }
                Button("Очистить загруженные материалы", role: .destructive) { clearMaterials = true }
                Text("Очистка удаляет тексты и список серий. Прогресс, обсуждения и личные итоги сохраняются. Системная модель Apple хранится отдельно и не включена в приложение.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Данные и место") }
            Section {
                Label("Диалоги обрабатываются на iPhone", systemImage: "iphone.gen3")
                Label("Без рекламы и аналитических SDK", systemImage: "hand.raised")
                Text("Поисковые запросы и обращения за материалами отправляются выбранным каталогам. Текст обсуждения не отправляется в облачный ИИ. Авторизация выполняется на сайте TMDB.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("Источники и лицензии") { AttributionView() }
                Link("Исходный код и сообщения об ошибках", destination: URL(string: "https://github.com/eljke/FrameTrail")!)
            } header: { Text("О приложении") }
            if let error { Section { ErrorNotice(message: error) } }
            if let notice { Section { Text(notice).font(.footnote).foregroundStyle(Theme.accent) } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $authorization) { SafariPage(url: $0.url).ignoresSafeArea() }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "FrameTrail-library") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
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
                notice = "Библиотека восстановлена. Новые записи объединены с текущими по дате изменения."
                error = nil
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Удалить загруженные тексты и список серий? Личные записи и прогресс останутся.", isPresented: $clearMaterials, titleVisibility: .visible) {
            Button("Очистить материалы", role: .destructive) {
                library.clearDownloadedMaterials()
                URLCache.shared.removeAllCachedResponses()
            }
        }
    }

    private func saveToken() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.auth.setTMDBReadToken(apiToken.isEmpty ? nil : apiToken)
            try await model.refreshAccountState(library: library)
            apiToken = ""
            awaitingApproval = false
            authorization = nil
            notice = model.hasCatalogToken ? "Токен сохранён в Keychain." : "Токен удалён."
        } catch {
            self.error = error.localizedDescription
            do { try await model.refreshAccountState(library: library) }
            catch { self.error = error.localizedDescription }
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
        } catch { self.error = error.localizedDescription }
    }

    private func finishLogin() async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await model.finishAuthorization(library: library); awaitingApproval = false }
        catch { self.error = error.localizedDescription }
    }

    private func importWatchlist() async {
        busy = true
        error = nil
        defer { busy = false }
        let accountID = library.activeAccountID
        do {
            let titles = try await model.auth.watchlist()
            guard accountID == library.activeAccountID else { return }
            for title in titles { library.add(title) }
            notice = "Обработано историй: \(titles.count). Существующие заметки не заменялись. Импорт ограничен первыми 10 страницами каждого типа."
        } catch { self.error = error.localizedDescription }
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
            Section("Каталоги") {
                Link("TMDB", destination: URL(string: "https://www.themoviedb.org")!)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.").font(.footnote)
                Image("TMDBLogo").resizable().scaledToFit().frame(width: 100, height: 20).accessibilityLabel("TMDB")
                Link("TVmaze · CC BY-SA", destination: URL(string: "https://www.tvmaze.com/api")!)
                Link("iTunes Search API", destination: URL(string: "https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/")!)
            }
            Section("Сюжетные материалы") {
                Text("Материалы Wikipedia распространяются по CC BY-SA 4.0. Пересказ и выбранные фрагменты могут быть сокращены; ссылка на исходную редакцию доступна возле материала. Пользовательские тексты хранятся только в его библиотеке.").font(.footnote)
                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
            }
            Section("Приложение") {
                Text("FrameTrail · MIT License · © 2026 Ilya Kuzmenko").font(.footnote)
                Text("Apple Foundation Models — системная технология Apple. Доступность зависит от устройства, региона, настроек Apple Intelligence и языка.").font(.footnote)
            }
        }.navigationTitle("Источники")
    }
}
