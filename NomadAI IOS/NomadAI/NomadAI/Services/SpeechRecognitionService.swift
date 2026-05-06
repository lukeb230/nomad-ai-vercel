//
//  SpeechRecognitionService.swift
//  Wraps Speech.framework + AVAudioEngine for the mic button in Search.
//
//  One @Observable singleton. Tap-to-start, tap-to-stop. Live transcript
//  flows out via `transcript`; SearchView mirrors it into `aiInput`. On-device
//  recognition when available (offline + private); falls back to server.
//

import Foundation
import OSLog
import AVFoundation
import Speech

private let speechLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "speech")

@Observable
final class SpeechRecognitionService: NSObject {
    static let shared = SpeechRecognitionService()

    private(set) var isListening: Bool = false
    private(set) var transcript: String = ""
    private(set) var error: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// Requests permissions if needed and starts a fresh recognition session.
    /// Returns false if mic or speech recognition is denied.
    @discardableResult
    func startListening() async -> Bool {
        guard !isListening else { return true }

        // 1. Speech recognition permission
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            await MainActor.run { self.error = "Speech recognition not allowed" }
            speechLog.notice("speech auth denied: \(String(describing: speechAuth))")
            return false
        }

        // 2. Microphone permission
        let micAllowed: Bool
        if #available(iOS 17.0, *) {
            micAllowed = await AVAudioApplication.requestRecordPermission()
        } else {
            micAllowed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        guard micAllowed else {
            await MainActor.run { self.error = "Microphone access not allowed" }
            speechLog.notice("mic permission denied")
            return false
        }

        // 3. Audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            await MainActor.run { self.error = "Audio session error: \(error.localizedDescription)" }
            speechLog.error("audio session error: \(error.localizedDescription)")
            return false
        }

        // 4. Recognition request + tap on input
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            await MainActor.run { self.error = "Audio engine error: \(error.localizedDescription)" }
            speechLog.error("audio engine error: \(error.localizedDescription)")
            return false
        }

        await MainActor.run {
            self.transcript = ""
            self.error = nil
            self.isListening = true
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.transcript = text }
            }
            if let err {
                speechLog.error("recognition error: \(err.localizedDescription)")
                self.stopListeningInternal()
            }
        }

        speechLog.notice("listening started")
        return true
    }

    func stopListening() {
        stopListeningInternal()
    }

    private func stopListeningInternal() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Task { @MainActor in self.isListening = false }
    }
}
