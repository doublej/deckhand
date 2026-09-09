import AVFoundation
import Observation

/// Records one clip at a time, 16 kHz mono AAC — what the Mac wants to transcribe later.
@MainActor
@Observable
final class Recorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?

    /// Starts recording, or reports why it could not.
    func start() async -> String? {
        guard await AVAudioApplication.requestRecordPermission() else {
            return "Microphone access is off for Deckhand"
        }
        do {
            let recorder = try makeRecorder()
            recorder.record()
            self.recorder = recorder
            isRecording = true
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makeRecorder() throws -> AVAudioRecorder {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deckhand-\(UUID().uuidString.prefix(8)).m4a")
        return try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ])
    }

    /// Stops and hands back the clip, or nil when nothing usable was recorded.
    /// Anything under 0.3 s is a tap, and the transcription engine rejects those.
    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let tooShort = recorder.currentTime < 0.3
        recorder.stop()
        isRecording = false
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if tooShort {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return recorder.url
    }
}
