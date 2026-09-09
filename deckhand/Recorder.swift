import AVFoundation
import Foundation
import Observation

/// Records one clip at a time, 16 kHz mono AAC — what the Mac wants to transcribe later.
@MainActor
@Observable
final class Recorder {
    private(set) var isRecording = false
    /// Amplitude, 0...1, for the mark to burn and cycle by. Zero when nothing is recording.
    private(set) var level: Double = 0
    private var recorder: AVAudioRecorder?
    private var metering: Task<Void, Never>?

    /// Starts recording, or reports why it could not.
    func start() async -> String? {
        guard await AVAudioApplication.requestRecordPermission() else {
            return "Microphone access is off for Deckhand"
        }
        do {
            let recorder = try makeRecorder()
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            isRecording = true
            OrientationLock.hold()
            Awake.hold()
            meter()
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

    /// Publishes the input level while recording. AVAudioRecorder reports dBFS; the mark
    /// wants the amplitude that came from, because that is what its curves were fitted to.
    private func meter() {
        metering = Task { [weak self] in
            while !Task.isCancelled, let recorder = self?.recorder {
                recorder.updateMeters()
                self?.level = pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)
                try? await Task.sleep(for: .seconds(0.05))
            }
        }
    }

    /// Stops and throws the clip away. Nothing is transcribed and nothing is sent.
    func discard() {
        guard let clip = stop() else { return }
        try? FileManager.default.removeItem(at: clip)
    }

    /// Stops and hands back the clip, or nil when nothing usable was recorded.
    /// Anything under 0.3 s is a tap, and the transcription engine rejects those.
    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let tooShort = recorder.currentTime < 0.3
        recorder.stop()
        isRecording = false
        OrientationLock.release()
        Awake.release()
        metering?.cancel()
        metering = nil
        level = 0
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if tooShort {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return recorder.url
    }
}
