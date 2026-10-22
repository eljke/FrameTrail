import SwiftUI
import FrameTrailCore

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var filter = 0
    @State private var query = ""
    @State private var manualEntry = false
    @State private var pendingRemoval: LibraryEntry?

    private var entries: [LibraryEntry] {
        library.entries.filter {
            (filter == 0 || (filter == 1 ? !$0.progress.finished : $0.progress.finished)) &&
            (query.isEmpty || $0.title.title.localizedCaseInsensitiveContains(query))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCaption(eyebrow: "Твой след в историях", title: "Библиотека")
                Picker("Показать", selection: $filter) {
                    Text("Все").tag(0)
                    Text("Смотрю").tag(1)
                    Text("Досмотрел").tag(2)
                }.pickerStyle(.segmented)
                if entries.isEmpty {
                    EmptyState(symbol: "books.vertical", title: "Здесь будут твои истории", text: "Найди фильм в обзоре или добавь свой. Прогресс, материалы и обсуждения сохранятся на устройстве.")
                    Button { manualEntry = true } label: { Label("Добавить историю", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("libraryAddTitle")
                }
                LazyVStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.title) {
                            HStack(spacing: 14) {
                                PosterView(title: entry.title, width: 65)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.title.title).font(.headline).foregroundStyle(.white)
                                    Label(entry.progress.finished ? "Досмотрено" : (entry.progress.watchedEpisodeIDs.isEmpty ? "В планах" : "Просмотрено серий: \(entry.progress.watchedEpisodeIDs.count)"), systemImage: entry.progress.finished ? "checkmark.circle.fill" : "play.circle")
                                        .font(.caption).foregroundStyle(Theme.accent)
                                    Text("Обсуждений: \(entry.chat.filter { $0.role == .assistant }.count) · Итогов: \(entry.reflections.count)")
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Удалить из библиотеки", role: .destructive) { pendingRemoval = entry } }
                    }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Библиотека").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск в библиотеке")
        .toolbar { Button { manualEntry = true } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить историю") }
        .sheet(isPresented: $manualEntry) { ManualTitleView() }
        .confirmationDialog("Удалить историю, её обсуждение и заметки?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let entry = pendingRemoval { library.remove(entry.id) }; pendingRemoval = nil }
        }
    }
}

struct JournalView: View {
    @Environment(LibraryStore.self) private var library

    private var records: [(entry: LibraryEntry, reflection: Reflection)] {
        library.entries.flatMap { entry in entry.reflections.map { (entry: entry, reflection: $0) } }
            .sorted { $0.reflection.createdAt > $1.reflection.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCaption(eyebrow: "То, что осталось с тобой", title: "Дневник просмотра")
                LibraryStatisticsView(entries: library.entries)
                if records.isEmpty {
                    EmptyState(symbol: "text.book.closed", title: "Истории заканчиваются. Мысли остаются.", text: "После просмотра открой «Итог» в карточке фильма или сериала. Сохрани впечатления, вопросы и оценку.")
                }
                ForEach(records, id: \.reflection.id) { record in
                    NavigationLink(value: record.entry.title) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(record.entry.title.title).font(.headline)
                                Spacer()
                                if let rating = record.reflection.rating { Label("\(rating)/10", systemImage: "star.fill").font(.caption.bold()).foregroundStyle(Theme.accent) }
                            }
                            if !record.reflection.summary.isEmpty { Text(record.reflection.summary).font(.subheadline).lineLimit(5).foregroundStyle(Theme.muted) }
                            Text(record.reflection.createdAt, style: .date).font(.caption2).foregroundStyle(Theme.muted)
                        }.padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Дневник").navigationBarTitleDisplayMode(.inline)
    }
}
