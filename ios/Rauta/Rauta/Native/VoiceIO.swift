import AVFoundation
import Foundation
import Observation
import Speech

/// Short, deliberate dictation. Audio stays in a temporary file only until
/// SpeechAnalyzer has transcribed it, then the file is removed.
@MainActor @Observable
final class VoiceIO {
    static let shared = VoiceIO()

    enum State { case idle, requesting, recording, transcribing }
    private(set) var state: State = .idle
    private(set) var error: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private let speaker = AVSpeechSynthesizer()

    private init() {}

    func start() async {
        guard state == .idle else { return }
        error = nil
        state = .requesting
        let id = UUID()
        operationID = id
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard operationID == id else { return }
        guard microphone else { error = "Microphone access is off. Enable it in Settings."; state = .idle; return }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard operationID == id else { return }
        guard speech else { error = "Speech access is off. Enable it in Settings."; state = .idle; return }
        guard SpeechTranscriber.isAvailable else {
            error = "On-device speech transcription isn't available for this language."
            state = .idle
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rauta-dictation-\(UUID().uuidString).caf")
        do {
            try WorkoutAudio.beginVoice()
            let next = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ])
            next.isMeteringEnabled = true
            guard next.record() else { throw VoiceError.recording }
            recorder = next
            recordingURL = url
            state = .recording
        } catch {
            WorkoutAudio.endVoice()
            try? FileManager.default.removeItem(at: url)
            self.error = "I couldn't start recording. Try again."
            state = .idle
        }
    }

    func stop() async -> String? {
        guard state == .recording, let url = recordingURL else { return nil }
        let id = operationID
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        WorkoutAudio.endVoice()
        state = .transcribing
        defer {
            try? FileManager.default.removeItem(at: url)
            if operationID == id { state = .idle }
        }
        do {
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? .current
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let modules: [any SpeechModule] = [transcriber]
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: modules)
            let audioFile = try AVAudioFile(forReading: url)
            let output = Task { () throws -> [String] in
                var segments: [String] = []
                for try await result in transcriber.results where result.isFinal {
                    segments.append(String(result.text.characters))
                }
                return segments
            }
            do {
                try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)
                _ = try await analyzer.analyzeSequence(from: audioFile)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await output.value.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard operationID == id else { return nil }
                if text.isEmpty { error = "I didn't catch that. Try speaking again." }
                return text.isEmpty ? nil : text
            } catch {
                output.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } catch {
            self.error = "I couldn't transcribe that recording. Try again."
            return nil
        }
    }

    /// How loud the microphone is right now, from 0 (silence) to 1, for the
    /// listening indicator. Read on every frame while recording.
    func level() -> Double {
        guard let recorder, state == .recording else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        // -50 dB and below reads as silence; speech sits around -30 to -10.
        return max(0, min(1, (decibels + 50) / 45))
    }

    func cancel() {
        operationID = UUID()
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        if state == .recording { WorkoutAudio.endVoice() }
        state = .idle
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(utterance)
    }
}

private enum VoiceError: Error { case recording }
