import SwiftUI
import FrameTrailCore

struct AccountSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmDeletion = false
    @State private var newPassword = ""

    var body: some View {
        Section {
            if let session = model.cloudSession {
                Label(session.email ?? L10n.text("Аккаунт FrameTrail"), systemImage: "person.crop.circle.fill")
                if let sync = model.sync {
                    Label(sync.status, systemImage: sync.isSyncing ? "arrow.triangle.2.circlepath" : "icloud")
                        .font(.footnote).accessibilityIdentifier("syncStatus")
                    if let date = sync.lastSyncedAt {
                        LabeledContent(L10n.text("Последняя синхронизация")) { Text(date, style: .relative) }.font(.caption)
                    }
                    Button(L10n.text("Синхронизировать сейчас")) { Task { await sync.syncNow(library: library) } }
                        .disabled(busy || sync.isSyncing)
                    if !sync.conflicts.isEmpty {
                        NavigationLink(L10n.text("Выбрать версии: %@", String(describing: sync.conflicts.count))) { SyncConflictsView(sync: sync) }
                    }
                    if sync.isSyncing { ProgressView() }
                }
                Button(L10n.text("Выйти из FrameTrail")) {
                    Task { busy = true; await model.signOutFrameTrail(library: library); busy = false }
                }.disabled(busy || model.sync?.isSyncing == true)
                DisclosureGroup(L10n.text("Сменить пароль")) {
                    SecureField(L10n.text("Новый пароль · от 8 символов"), text: $newPassword).textContentType(.newPassword)
                    Button(L10n.text("Обновить пароль")) {
                        Task {
                            busy = true
                            error = nil
                            do {
                                guard let auth = model.cloudAuth else { throw SupabaseAuthError.notConfigured }
                                try await auth.updatePassword(password: newPassword)
                                newPassword = ""
                                notice = L10n.text("Пароль изменён.")
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(busy || newPassword.count < 8)
                }.disabled(busy)
                Button(L10n.text("Удалить аккаунт и облачные данные"), role: .destructive) { confirmDeletion = true }
                    .disabled(busy || model.sync?.isSyncing == true)
            } else {
                Label(L10n.text("Гостевая библиотека"), systemImage: "person.crop.circle")
                Picker(L10n.text("Аккаунт FrameTrail"), selection: $createAccount) {
                    Text(L10n.text("Вход")).tag(false)
                    Text(L10n.text("Регистрация")).tag(true)
                }.pickerStyle(.segmented).disabled(busy)
                TextField("Email", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy)
                    .accessibilityIdentifier("accountEmail")
                SecureField(createAccount ? L10n.text("Пароль · от 8 символов") : L10n.text("Пароль"), text: $password)
                    .textContentType(createAccount ? .newPassword : .password).disabled(busy)
                    .accessibilityIdentifier("accountPassword")
                Button(createAccount ? L10n.text("Создать аккаунт") : L10n.text("Войти в FrameTrail")) { Task { await submit() } }
                    .disabled(busy || model.cloudAuth == nil || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (createAccount && password.count < 8))
                    .accessibilityIdentifier("accountSubmit")
                if busy { ProgressView(L10n.text("Подключаю аккаунт…")) }
                Text(L10n.text("Закрытая бета: письма подтверждения доступны участникам проекта Supabase. После подтверждения вернись сюда и войди с паролем. Гостевые записи можно перенести через экспорт и импорт библиотеки."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("В аккаунте синхронизируются карточки, прогресс и личные итоги с оценками. Диалоги, тексты источников и описания серий остаются на устройстве. Локальный кэш позволяет пользоваться библиотекой без интернета; статистика считается по данным активного аккаунта."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { ErrorNotice(message: error) }
            if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.accent) }
        } header: { Text(L10n.text("Аккаунт FrameTrail")) }
        .confirmationDialog(L10n.text("Удалить аккаунт навсегда? Облачная библиотека и её кэш на этом устройстве будут удалены. Диалоги и материалы на других устройствах не удаляются удалённо."), isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button(L10n.text("Удалить аккаунт навсегда"), role: .destructive) {
                Task {
                    busy = true
                    error = nil
                    do { try await model.deleteFrameTrailAccount(library: library); notice = L10n.text("Аккаунт удалён.") }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }
        }
    }

    private func submit() async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            let signedIn = try await model.signInFrameTrail(email: email, password: password, createAccount: createAccount, library: library)
            password = ""
            if signedIn { notice = L10n.text("Аккаунт подключён.") }
            else {
                createAccount = false
                notice = L10n.text("Проверь почту и подтверди email, затем войди. Если адрес уже зарегистрирован, используй существующий пароль.")
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct SyncConflictsView: View {
    @Environment(LibraryStore.self) private var library
    let sync: LibrarySyncCoordinator

    var body: some View {
        List {
            Section {
                Text(L10n.text("Одна история изменилась на разных устройствах. Выбери, какую версию сохранить. Выбор целиком заменит прогресс и личные итоги этой истории; источники и обсуждения не загружаются в облако."))
                    .font(.footnote)
            }
            ForEach(sync.conflicts) { conflict in
                Section {
                    Text(conflict.local?.title.title ?? conflict.remote?.payload?.title.title ?? conflict.mediaID).font(.headline)
                    Text(L10n.text("На устройстве: ") + summary(library.cloudItems().first { $0.id == conflict.mediaID }))
                    Text(L10n.text("В облаке: ") + summary(conflict.remote?.payload))
                    if [.concurrentChanges, .initialDivergence].contains(conflict.reason), conflict.remote?.isValid == true {
                        Button(L10n.text("Сохранить версию устройства")) { Task { await sync.resolve(conflict, keepLocal: true, library: library) } }
                        Button(L10n.text("Принять версию из облака")) { Task { await sync.resolve(conflict, keepLocal: false, library: library) } }
                    } else {
                        Text(L10n.text("Нарушена история версий. Сохрани экспорт библиотеки и повтори синхронизацию; автоматическая замена заблокирована."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(sync.isSyncing)
            }
            Section { Text(sync.status).font(.footnote) }
        }.navigationTitle(L10n.text("Версии истории"))
    }

    private func summary(_ item: CloudLibraryItem?) -> String {
        guard let item else { return L10n.text("удалено") }
        return L10n.text("%@, серий: %@, итогов: %@", String(describing: item.progress.finished ? L10n.text("завершено") : L10n.text("в процессе")), String(describing: item.progress.watchedEpisodeIDs.count), String(describing: item.reflections.count))
    }
}
