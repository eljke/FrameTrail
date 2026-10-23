import SwiftUI
import FrameTrailCore
import TipKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab(L10n.text("Библиотека"), systemImage: "books.vertical", value: 1) {
                NavigationStack { LibraryView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
            }
            Tab(L10n.text("Дневник"), systemImage: "text.book.closed", value: 2) {
                NavigationStack { JournalView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
            }
            Tab(L10n.text("Настройки"), systemImage: "slider.horizontal.3", value: 3) {
                NavigationStack { SettingsView() }
            }
            Tab(L10n.text("Поиск"), systemImage: "magnifyingglass", value: 0, role: .search) {
                NavigationStack { DiscoverView().navigationDestination(for: MediaTitle.self) { TitleDetailView(title: $0) } }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .id(library.activeAccountID + model.localeIdentifier)
        .alert("FrameTrail", isPresented: Binding(get: { model.alertMessage != nil || library.lastError != nil }, set: { if !$0 { model.alertMessage = nil; library.dismissError() } })) {
            Button(L10n.text("Понятно")) { model.alertMessage = nil; library.dismissError() }
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
    @State private var quickGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if let recent = library.entries.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                        NavigationLink(value: recent.title) {
                            HStack(spacing: 16) {
                                PosterView(title: recent.title, width: 65)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.text("НЕДАВНО ОТКРЫВАЛИ")).font(.caption2.bold()).tracking(1.2).foregroundStyle(Theme.accent)
                                    Text(recent.title.title).font(.headline)
                                    Text(recent.progress.finished ? L10n.text("Вернуться к обсуждению") : L10n.text("Обсудить просмотренное")).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Theme.accent)
                            }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                    Text(L10n.text("Популярное")).font(.title2.bold())
                    if library.entries.isEmpty && !model.isUITesting {
                        TipView(FirstTitleTip()) { _ in quickGuide = true }
                    }
                    if !model.featured.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(model.featured) { title in NavigationLink(value: title) { TitleCard(title: title) }.buttonStyle(.plain) }
                            }
                        }
                    }
                    Button { manualEntry = true } label: { Label(L10n.text("Добавить вручную"), systemImage: "plus.circle") }
                        .accessibilityIdentifier("addManualTitle")
                } else {
                    if isSearching { ProgressView(L10n.text("Поиск…")).frame(maxWidth: .infinity).padding() }
                    if let error { ErrorNotice(message: error) }
                    if !isSearching && results.isEmpty && error == nil {
                        EmptyState(symbol: "magnifyingglass", title: L10n.text("Ничего не найдено"), text: L10n.text("Попробуй оригинальное название. Для расширенного каталога можно подключить TMDB в настройках."))
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
        .searchable(text: $query, prompt: L10n.text("Фильм или сериал"))
        .sheet(isPresented: $manualEntry) { ManualTitleView() }
        .sheet(isPresented: $quickGuide) { NavigationStack { QuickGuideView() } }
        .onChange(of: library.entries.isEmpty) { _, empty in
            if !empty && !model.isUITesting { FirstTitleTip().invalidate(reason: .actionPerformed) }
        }
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
                Section(L10n.text("Произведение")) {
                    TextField(L10n.text("Название"), text: $name).accessibilityIdentifier("manualTitleName")
                    Picker(L10n.text("Тип"), selection: $kind) {
                        Text(L10n.text("Фильм")).tag(MediaKind.movie)
                        Text(L10n.text("Сериал")).tag(MediaKind.series)
                    }.accessibilityIdentifier("manualTitleKind")
                }
                Section { Text(L10n.text("Добавь собственные материалы в карточке произведения. До отметки «Досмотрел» полный сюжет фильма не используется в ответах.")).font(.footnote) }
            }
            .navigationTitle(L10n.text("Добавить вручную"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Добавить")) {
                        let id = UUID().uuidString
                        library.add(MediaTitle(id: "local:" + id, title: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)), kind: kind, provider: "local", providerID: id))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("confirmManualTitle")
                }
            }
        }
    }
}
