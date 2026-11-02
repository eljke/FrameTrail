import SwiftUI

struct VoiceNoteView: View {
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @State private var service = VoiceNoteService()
    @State private var transcript = ""
    @State private var busy = false
    @State private var started = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(L10n.text("Скажи, что запомнилось"), systemImage: service.recording ? "waveform" : "mic").font(.headline)
                    Text(L10n.text("До 90 секунд. Расшифровка выполняется на iPhone; для языка может понадобиться загрузка системного пакета. Аудио не синхронизируется и удаляется после расшифровки или закрытия."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView(); Button(L10n.text("Остановить")) { stop() } }
                    else if !started { Button(L10n.text("Начать запись"), systemImage: "mic.fill") { record() } }
                    else { Button(L10n.text("Расшифровать на iPhone"), systemImage: "text.bubble") { transcribe() } }
                }
                Section(L10n.text("Проверь текст")) {
                    TextEditor(text: $transcript).frame(minHeight: 180)
                        .onChange(of: transcript) { _, value in if value.count > 10000 { transcript = String(value.prefix(10000)) } }
                    if !transcript.isEmpty { Button(L10n.text("Добавить к заметке")) { onApply(transcript); dismiss() }.disabled(busy) }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle(L10n.text("Голосовая заметка"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Закрыть")) { dismiss() } } }
            .onChange(of: library.activeAccountID) { _, _ in stop(); dismiss() }
            .onDisappear { stop() }
        }
    }

    private func stop() { task?.cancel(); task = nil; service.discard(); busy = false; started = false }
    private func record() {
        busy = true; error = nil
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil } }
            do { try await service.start(); try Task.checkCancellation(); started = true }
            catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
    private func transcribe() {
        busy = true; error = nil
        let locale = Locale(identifier: model.localeIdentifier)
        task = Task {
            defer { if !Task.isCancelled { busy = false; task = nil; started = false } }
            do {
                transcript = try await service.transcribe(locale: locale)
                if transcript.isEmpty { error = L10n.text("Речь не распознана. Попробуй записать ещё раз или введи текст.") }
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = L10n.error(error) } }
        }
    }
}
