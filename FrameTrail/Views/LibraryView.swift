import SwiftUI
import FrameTrailCore

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var filter = 0
    @State private var query = ""
    @State private var manualEntry = false
    @State private var pendingRemoval: LibraryEntry?

    private var entries: [LibraryEntry] {
        library.entries.filter {
            (filter == 0 || (filter == 1 && !$0.progress.finished && !$0.progress.watchedEpisodeIDs.isEmpty) || (filter == 2 && $0.progress.finished) || (filter == 3 && !$0.progress.finished && $0.progress.watchedEpisodeIDs.isEmpty)) &&
            (query.isEmpty || model.displayTitle($0.title).title.localizedCaseInsensitiveContains(query) || $0.title.title.localizedCaseInsensitiveContains(query) || $0.title.originalTitle?.localizedCaseInsensitiveContains(query) == true)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker(L10n.text("Показать"), selection: $filter) {
                    Text(L10n.text("Все")).tag(0)
                    Text(L10n.text("В планах")).tag(3)
                    Text(L10n.text("Смотрю")).tag(1)
                    Text(L10n.text("Досмотрел")).tag(2)
                }.pickerStyle(.segmented)
                if entries.isEmpty {
                    EmptyState(symbol: "books.vertical", title: L10n.text("Библиотека пока пуста"), text: L10n.text("Найди фильм в обзоре или добавь свой. Прогресс, материалы и обсуждения сохранятся на устройстве."))
                    Button { manualEntry = true } label: { Label(L10n.text("Добавить фильм или сериал"), systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).foregroundStyle(Theme.background).accessibilityIdentifier("libraryAddTitle")
                }
                LazyVStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.title) {
                            HStack(spacing: 14) {
                                PosterView(title: entry.title, width: 65)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(model.displayTitle(entry.title).title).font(.headline).foregroundStyle(.white)
                                    Label(entry.progress.finished ? L10n.text("Досмотрено") : (entry.progress.watchedEpisodeIDs.isEmpty ? L10n.text("В планах") : L10n.text("Просмотрено серий: %@", String(describing: entry.progress.watchedEpisodeIDs.count))), systemImage: entry.progress.finished ? "checkmark.circle.fill" : "play.circle")
                                        .font(.caption).foregroundStyle(Theme.accent)
                                    Text(L10n.text("Обсуждений: %@ · Итогов: %@", String(describing: entry.chat.filter { $0.role == .assistant }.count), String(describing: entry.reflections.count)))
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button(L10n.text("Удалить из библиотеки"), role: .destructive) { pendingRemoval = entry } }
                        .task(id: model.catalogRevision) { await model.localizeTitle(entry.title) }
                    }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(L10n.text("Библиотека")).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.text("Поиск в библиотеке"))
        .toolbar { Button { manualEntry = true } label: { Image(systemName: "plus") }.accessibilityLabel(L10n.text("Добавить фильм или сериал")) }
        .sheet(isPresented: $manualEntry) { ManualTitleView() }
        .confirmationDialog(L10n.text("Удалить историю, её обсуждение и заметки?"), isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button(L10n.text("Удалить"), role: .destructive) { if let entry = pendingRemoval { library.remove(entry.id) }; pendingRemoval = nil }
        }
    }
}

struct JournalView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model

    private var records: [(entry: LibraryEntry, reflection: Reflection)] {
        library.entries.flatMap { entry in entry.reflections.map { (entry: entry, reflection: $0) } }
            .sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisclosureGroup(L10n.text("Статистика")) { LibraryStatisticsView(entries: library.entries).padding(.top, 12) }
                if records.isEmpty {
                    EmptyState(symbol: "text.book.closed", title: L10n.text("Пока нет отзывов"), text: L10n.text("После просмотра открой «Итог» в карточке фильма или сериала. Сохрани впечатления, вопросы и оценку."))
                }
                ForEach(records, id: \.reflection.id) { record in
                    NavigationLink(value: record.entry.title) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(model.displayTitle(record.entry.title).title).font(.headline)
                                Spacer()
                                if let rating = record.reflection.rating { Label("\(rating)/10", systemImage: "star.fill").font(.caption.bold()).foregroundStyle(Theme.accent) }
                            }
                            if let season = record.reflection.episodeSeason, let number = record.reflection.episodeNumber {
                                Text(L10n.text("Сезон %@ · Серия %@", String(describing: season), String(describing: number))).font(.caption).foregroundStyle(Theme.accent)
                            } else if let season = record.reflection.seasonNumber {
                                Text(L10n.text("Сезон %@", String(describing: season))).font(.caption).foregroundStyle(Theme.accent)
                            }
                            if !record.reflection.summary.isEmpty { Text(record.reflection.summary).font(.subheadline).lineLimit(5).foregroundStyle(Theme.muted) }
                            if let liked = record.reflection.allLiked.first { Text("+ " + liked).font(.caption).lineLimit(2).foregroundStyle(Theme.muted) }
                            if let disliked = record.reflection.allDisliked.first { Text("− " + disliked).font(.caption).lineLimit(2).foregroundStyle(Theme.muted) }
                            Text(record.reflection.createdAt, style: .date).font(.caption2).foregroundStyle(Theme.muted)
                        }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(L10n.text("Дневник")).navigationBarTitleDisplayMode(.inline)
    }
}
