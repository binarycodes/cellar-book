import AVFoundation
import CoreGraphics
import Observation
import Speech

/// Dictation via Apple's `Speech` framework.
///
/// On-device recognition is requested wherever the device and locale support a
/// local model; where they do not, `SFSpeechRecognizer` falls back to Apple's
/// servers, so the audio can leave the phone. That fallback is accepted
/// deliberately (2026-09-05) — but nothing here may claim otherwise, so the
/// sheet copy and the permission string describe it accurately.
///
/// What this class does guarantee: the audio buffer is never written to disk,
/// the engine is torn down as soon as the transcript is handed back, and the
/// finished text is stored only in the local SwiftData store.
@Observable
@MainActor
final class SpeechTranscriber {
    enum Phase: Equatable { case idle, recording, transcribed, denied(String) }

    private(set) var phase: Phase = .idle
    private(set) var transcript: String = ""
    /// Normalised 0…1 levels driving the waveform. 19 bars, as the design draws.
    private(set) var levels: [CGFloat] = Array(repeating: 0.18, count: 19)
    /// Tenths of a second, so the sheet can render mm:ss.
    private(set) var ticks: Int = 0

    var elapsed: String {
        let secs = ticks / 10
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var timer: Timer?

    // MARK: - Permissions

    /// Both permissions are required before the engine can start; the design
    /// opens the sheet straight into "Listening", so this runs first.
    ///
    /// Returns whether authorization succeeded, and whether the user was
    /// actually prompted — the caller needs the latter, see `start()`.
    func requestAuthorization() async -> (granted: Bool, didPrompt: Bool) {
        let wasDetermined = SFSpeechRecognizer.authorizationStatus() != .notDetermined
            && AVAudioApplication.shared.recordPermission != .undetermined

        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            phase = .denied("Speech recognition is off for Vinnota. Enable it in Settings to dictate a note.")
            return (false, !wasDetermined)
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            phase = .denied("The microphone is off for Vinnota. Enable it in Settings to dictate a note.")
            return (false, !wasDetermined)
        }
        return (true, !wasDetermined)
    }

    // MARK: - Recording

    func start() async {
        reset()

        // `AVAudioEngine.inputNode` initialises AURemoteIO, and in the
        // Simulator that RPC can time out — AudioToolbox then calls abort(),
        // which no Swift error handling can intercept, taking the whole app
        // with it. There is no API to ask whether it will succeed, so the
        // Simulator is refused up front. The device path below is the real one.
        #if targetEnvironment(simulator)
        phase = .denied("Dictation needs a real device — the Simulator cannot open an audio input. Type the note instead.")
        return
        #else

        let auth = await requestAuthorization()
        guard auth.granted else { return }

        // Touching `AVAudioEngine.inputNode` immediately after a fresh
        // microphone grant can outrun CoreAudio's reconfiguration: the
        // AURemoteIO init RPC times out and AudioToolbox calls abort(), which
        // no Swift error handling can intercept. Letting the audio server
        // settle first avoids the abort entirely.
        if auth.didPrompt {
            try? await Task.sleep(for: .milliseconds(400))
        }

        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            phase = .denied("Speech recognition is unavailable for this locale.")
            return
        }
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // No usable input route — an abort from `inputNode` would be
            // unrecoverable, so refuse before reaching it.
            guard session.isInputAvailable else {
                phase = .denied("No microphone is available right now. Type the note instead.")
                teardown()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Prefer the local model; Apple's servers are the fallback where
            // no local model exists for this locale or device.
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.normalisedPower(buffer)
                Task { @MainActor in self?.push(level: level) }
            }

            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || (result?.isFinal ?? false) { self.finish() }
                }
            }

            phase = .recording
            startTimer()

        } catch {
            phase = .denied("Could not start recording: \(error.localizedDescription)")
            teardown()
        }
        #endif
    }

    /// "Stop and transcribe" — ends capture and keeps whatever was recognised.
    func stop() {
        guard phase == .recording else { return }
        finish()
    }

    private func finish() {
        teardown()
        phase = .transcribed
    }

    func reset() {
        teardown()
        phase = .idle
        transcript = ""
        ticks = 0
        levels = Array(repeating: 0.18, count: 19)
    }

    func edit(_ text: String) { transcript = text }

    // MARK: - Internals

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ticks += 1 }
        }
    }

    private func push(level: CGFloat) {
        levels.removeFirst()
        levels.append(max(0.18, min(1.0, level)))
    }

    /// RMS of the buffer, mapped from dBFS onto 0…1.
    private nonisolated static func normalisedPower(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0.18 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.18 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        // −50 dBFS (near silence) … 0 dBFS (clipping)
        return CGFloat(max(0, min(1, (db + 50) / 50)))
    }

    private func teardown() {
        timer?.invalidate(); timer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
