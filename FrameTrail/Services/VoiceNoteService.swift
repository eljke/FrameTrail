import AVFoundation
import Foundation
import Observation
import Speech

@MainActor @Observable
final class VoiceNoteService {
    private(set) var recording = false
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<String, Error>?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AssistantError(message: L10n.text("Разреши доступ к микрофону в настройках iPhone или напиши заметку вручную."))
        }
        try Task.checkCancellation()
        discard()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("viewing-note-\(UUID().uuidString).m4a")
        recordingURL = url
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            guard recorder.record(forDuration: 90) else { throw AssistantError(message: L10n.text("Не удалось начать запись.")) }
            self.recorder = recorder
            recording = true
        } catch { discard(); throw error }
    }

    func transcribe(locale: Locale) async throws -> String {
        recorder?.stop(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = recordingURL, SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AssistantError(message: L10n.text("Локальная расшифровка этого языка недоступна. Заметку можно написать вручную."))
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let results = Task<String, Error> {
            var pieces: [String] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                if result.isFinal { pieces.append(String(result.text.characters)) }
            }
            return String(pieces.joined(separator: " ").prefix(10000))
        }
        resultsTask = results
        do {
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
            else { await analyzer.cancelAndFinishNow() }
            let text = try await results.value
            try Task.checkCancellation()
            discard()
            return text
        } catch { discard(); throw error }
    }

    func discard() {
        recorder?.stop(); recorder = nil; recording = false
        resultsTask?.cancel(); resultsTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
