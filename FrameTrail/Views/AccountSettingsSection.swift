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
                Label(session.email ?? "Аккаунт FrameTrail", systemImage: "person.crop.circle.fill")
                if let sync = model.sync {
                    Label(sync.status, systemImage: sync.isSyncing ? "arrow.triangle.2.circlepath" : "icloud")
                        .font(.footnote).accessibilityIdentifier("syncStatus")
                    if let date = sync.lastSyncedAt {
                        LabeledContent("Последняя синхронизация") { Text(date, style: .relative) }.font(.caption)
                    }
                    Button("Синхронизировать сейчас") { Task { await sync.syncNow(library: library) } }
                        .disabled(busy || sync.isSyncing)
                    if !sync.conflicts.isEmpty {
                        NavigationLink("Выбрать версии: \(sync.conflicts.count)") { SyncConflictsView(sync: sync) }
                    }
                    if sync.isSyncing { ProgressView() }
                }
                Button("Выйти из FrameTrail") {
                    Task { busy = true; await model.signOutFrameTrail(library: library); busy = false }
                }.disabled(busy || model.sync?.isSyncing == true)
                DisclosureGroup("Сменить пароль") {
                    SecureField("Новый пароль · от 8 символов", text: $newPassword).textContentType(.newPassword)
                    Button("Обновить пароль") {
                        Task {
                            busy = true
                            error = nil
                            do {
                                guard let auth = model.cloudAuth else { throw SupabaseAuthError.notConfigured }
                                try await auth.updatePassword(password: newPassword)
                                newPassword = ""
                                notice = "Пароль изменён."
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(busy || newPassword.count < 8)
                }.disabled(busy)
                Button("Удалить аккаунт и облачные данные", role: .destructive) { confirmDeletion = true }
                    .disabled(busy || model.sync?.isSyncing == true)
            } else {
                Label("Гостевая библиотека", systemImage: "person.crop.circle")
                Picker("Аккаунт FrameTrail", selection: $createAccount) {
                    Text("Вход").tag(false)
                    Text("Регистрация").tag(true)
                }.pickerStyle(.segmented).disabled(busy)
                TextField("Email", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy)
                    .accessibilityIdentifier("accountEmail")
                SecureField(createAccount ? "Пароль · от 8 символов" : "Пароль", text: $password)
                    .textContentType(createAccount ? .newPassword : .password).disabled(busy)
                    .accessibilityIdentifier("accountPassword")
                Button(createAccount ? "Создать аккаунт" : "Войти в FrameTrail") { Task { await submit() } }
                    .disabled(busy || model.cloudAuth == nil || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (createAccount && password.count < 8))
                    .accessibilityIdentifier("accountSubmit")
                if busy { ProgressView("Подключаю аккаунт…") }
                Text("Закрытая бета: письма подтверждения доступны участникам проекта Supabase. После подтверждения вернись сюда и войди с паролем. Гостевые записи можно перенести через экспорт и импорт библиотеки.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("В аккаунте синхронизируются карточки, прогресс и личные итоги с оценками. Диалоги, тексты источников и описания серий остаются на устройстве. Локальный кэш позволяет пользоваться библиотекой без интернета; статистика считается по данным активного аккаунта.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { ErrorNotice(message: error) }
            if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.accent) }
        } header: { Text("Аккаунт FrameTrail") }
        .confirmationDialog("Удалить аккаунт навсегда? Облачная библиотека и её кэш на этом устройстве будут удалены. Диалоги и материалы на других устройствах не удаляются удалённо.", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Удалить аккаунт навсегда", role: .destructive) {
                Task {
                    busy = true
                    error = nil
                    do { try await model.deleteFrameTrailAccount(library: library); notice = "Аккаунт удалён." }
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
            if signedIn { notice = "Аккаунт подключён." }
            else {
                createAccount = false
                notice = "Проверь почту и подтверди email, затем войди. Если адрес уже зарегистрирован, используй существующий пароль."
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
                Text("Одна история изменилась на разных устройствах. Выбери, какую версию сохранить. Выбор целиком заменит прогресс и личные итоги этой истории; источники и обсуждения не загружаются в облако.")
                    .font(.footnote)
            }
            ForEach(sync.conflicts) { conflict in
                Section {
                    Text(conflict.local?.title.title ?? conflict.remote?.payload?.title.title ?? conflict.mediaID).font(.headline)
                    Text("На устройстве: " + summary(library.cloudItems().first { $0.id == conflict.mediaID }))
                    Text("В облаке: " + summary(conflict.remote?.payload))
                    if [.concurrentChanges, .initialDivergence].contains(conflict.reason), conflict.remote?.isValid == true {
                        Button("Сохранить версию устройства") { Task { await sync.resolve(conflict, keepLocal: true, library: library) } }
                        Button("Принять версию из облака") { Task { await sync.resolve(conflict, keepLocal: false, library: library) } }
                    } else {
                        Text("Нарушена история версий. Сохрани экспорт библиотеки и повтори синхронизацию; автоматическая замена заблокирована.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(sync.isSyncing)
            }
            Section { Text(sync.status).font(.footnote) }
        }.navigationTitle("Версии истории")
    }

    private func summary(_ item: CloudLibraryItem?) -> String {
        guard let item else { return "удалено" }
        return "\(item.progress.finished ? "завершено" : "в процессе"), серий: \(item.progress.watchedEpisodeIDs.count), итогов: \(item.reflections.count)"
    }
}
