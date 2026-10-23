import SwiftUI

struct StorageView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmMaterials = false
    @State private var imageBytes = 0
    @State private var releasedBytes = 0
    @State private var cleanups = 0
    @State private var error: String?

    private var totalBytes: Int { library.bytesOnDisk + imageBytes }
    private var cacheFraction: Double { Double(imageBytes) / Double(max(1, totalBytes)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Theme.card, lineWidth: 12)
                        Circle().trim(from: 0, to: max(0.015, 1 - cacheFraction))
                            .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 8) {
                            Image(systemName: cleanups == 0 ? "internaldrive" : "checkmark.circle")
                                .font(.title).foregroundStyle(Theme.accent)
                                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : cleanups)
                            Text(size(totalBytes)).font(.title2.bold()).contentTransition(.numericText())
                            Text(L10n.text("библиотеки и кэш")).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }.frame(width: 210, height: 210).padding(12)
                    if cleanups > 0 {
                        Text(releasedBytes > 0 ? L10n.text("Освобождено %@", String(describing: size(releasedBytes))) : L10n.text("Кэш очищен"))
                            .font(.subheadline.bold()).foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("cacheCleanupResult")
                    }
                }.frame(maxWidth: .infinity)
                VStack(spacing: 18) {
                    LabeledContent(L10n.text("Библиотеки на устройстве"), value: size(library.bytesOnDisk))
                    LabeledContent(L10n.text("Кэш изображений"), value: size(imageBytes))
                    LabeledContent(L10n.text("Материалы текущего аккаунта"), value: "≈ " + size(library.downloadedMaterialBytes))
                }.font(.subheadline).padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                Button { clean(includeMaterials: false) } label: {
                    Label(L10n.text("Очистить кэш изображений"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("clearImageCache")
                Button(L10n.text("Удалить загруженные материалы"), role: .destructive) { confirmMaterials = true }
                    .frame(maxWidth: .infinity).accessibilityIdentifier("clearSourceCache")
                Text(L10n.text("Оценки, впечатления и прогресс сохраняются.")).font(.subheadline.bold())
                Text(L10n.text("Кэш изображений ограничен 16 МиБ на диске и 8 МиБ в оперативной памяти. Библиотека каждого аккаунта — до 10 МиБ. Размер материалов показан приблизительно; они входят в библиотеку, а не добавляются к ней."))
                    .font(.footnote).foregroundStyle(Theme.muted)
                Text(L10n.text("Удаление материалов убирает аннотации серий, загруженные пересказы и импортированные тексты текущего аккаунта. Их можно загрузить заново; свои исходные файлы сохрани отдельно. Обсуждения и выбранные варианты впечатлений останутся. Модель Apple и пакеты перевода управляются iOS и не входят в эти размеры."))
                    .font(.footnote).foregroundStyle(Theme.muted)
                if let error { ErrorNotice(message: error) }
            }.padding(24)
        }
        .background(Theme.background).navigationTitle(L10n.text("Память")).navigationBarTitleDisplayMode(.inline)
        .onAppear { imageBytes = URLCache.shared.currentDiskUsage }
        .sensoryFeedback(.success, trigger: cleanups)
        .confirmationDialog(L10n.text("Удалить тексты, пересказы и список серий текущего аккаунта? Оценки, впечатления и прогресс останутся."), isPresented: $confirmMaterials, titleVisibility: .visible) {
            Button(L10n.text("Удалить материалы и очистить кэш"), role: .destructive) { clean(includeMaterials: true) }
        }
    }

    private func clean(includeMaterials: Bool) {
        let before = totalBytes
        if includeMaterials {
            library.clearDownloadedMaterials()
            if let failure = library.lastError { error = failure; return }
        }
        URLCache.shared.removeAllCachedResponses()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.7)) {
            imageBytes = URLCache.shared.currentDiskUsage
            releasedBytes = max(0, before - totalBytes)
            cleanups += 1
            error = nil
        }
    }

    private func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
