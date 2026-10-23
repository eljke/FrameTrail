import SwiftUI
import FrameTrailCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack { DiscoverView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
                .tabItem { Label("Обзор", systemImage: "sparkles.tv") }.tag(0)
            NavigationStack { LibraryView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }.tag(1)
            NavigationStack { JournalView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
                .tabItem { Label("Дневник", systemImage: "text.book.closed") }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .id(library.activeAccountID)
        .alert("FrameTrail", isPresented: Binding(get: { model.alertMessage != nil || library.lastError != nil }, set: { if !$0 { model.alertMessage = nil; library.dismissError() } })) {
            Button("Понятно") { model.alertMessage = nil; library.dismissError() }
        } message: { Text(model.alertMessage ?? library.lastError ?? "") }
    }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var results: [MediaTitle] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var manualEntry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("У каждой истории\nесть послевкусие.")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                    Text("Вспомни важное. Разберись в сюжете.\nОбсуди то, что осталось с тобой.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }.padding(.top, 12)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if let recent = library.entries.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                        NavigationLink(value: recent.title) {
                            HStack(spacing: 16) {
                                PosterView(title: recent.title, width: 65)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ПРОДОЛЖИТЬ ИСТОРИЮ").font(.caption2.bold()).tracking(1.2).foregroundStyle(Theme.accent)
                                    Text(recent.title.title).font(.headline)
                                    Text(recent.progress.finished ? "Вернуться к обсуждению" : "Вспомнить просмотренное").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Theme.accent)
                            }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                    SectionCaption(eyebrow: "Найди свою историю", title: "Начни с названия")
                    if !model.featured.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(model.featured) { title in NavigationLink(value: title) { TitleCard(title: title) }.buttonStyle(.plain) }
                            }
                        }
                    }
                    InfoCard(symbol: "iphone.gen3", title: "Разговор остаётся на iPhone", text: "Ответы генерирует локальная модель Apple. Для поиска и загрузки материалов нужен интернет.")
                    Button { manualEntry = true } label: { Label("Добавить своё произведение", systemImage: "plus.circle") }
                        .accessibilityIdentifier("addManualTitle")
                } else {
                    if isSearching { ProgressView("Ищем истории…").frame(maxWidth: .infinity).padding() }
                    if let error { ErrorNotice(message: error) }
                    if !isSearching && results.isEmpty && error == nil {
                        EmptyState(symbol: "magnifyingglass", title: "Ничего не найдено", text: "Попробуй оригинальное название. Для расширенного каталога можно подключить TMDB в настройках.")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(results) { title in NavigationLink(value: title) { TitleCard(title: title) }.buttonStyle(.plain) }
                    }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("FrameTrail")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Фильм или сериал")
        .sheet(isPresented: $manualEntry) { ManualTitleView() }
        .task(id: model.catalogRevision) { await model.loadFeatured() }
        .task(id: query + model.catalogRevision.uuidString) {
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !search.isEmpty else { results = []; error = nil; isSearching = false; return }
            isSearching = true
            error = nil
            do {
                try await Task.sleep(for: .milliseconds(350))
                let found = try await model.catalog.search(query: search)
                try Task.checkCancellation()
                results = found
                isSearching = false
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isSearching = false
            }
        }
    }
}

struct ManualTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var name = ""
    @State private var kind = MediaKind.movie

    var body: some View {
        NavigationStack {
            Form {
                Section("Произведение") {
                    TextField("Название", text: $name).accessibilityIdentifier("manualTitleName")
                    Picker("Тип", selection: $kind) {
                        Text("Фильм").tag(MediaKind.movie)
                        Text("Сериал").tag(MediaKind.series)
                    }.accessibilityIdentifier("manualTitleKind")
                }
                Section { Text("Добавь собственные материалы в карточке произведения. До отметки «Досмотрел» полный сюжет фильма не используется в ответах.").font(.footnote) }
            }
            .navigationTitle("Своя история")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        let id = UUID().uuidString
                        library.add(MediaTitle(id: "local:" + id, title: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)), kind: kind, provider: "local", providerID: id))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("confirmManualTitle")
                }
            }
        }
    }
}
