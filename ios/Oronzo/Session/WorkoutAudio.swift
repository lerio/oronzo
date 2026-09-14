import AVFoundation
import Foundation
import UIKit

/// Everything you hear and feel during a session, plus the silent loop that keeps the app
/// running while the phone is in a pocket.
@MainActor
final class WorkoutAudio {

    private var keepAlive: AVAudioPlayer?
    private var transitionCue: AVAudioPlayer?
    private var tickCue: AVAudioPlayer?

    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)

    /// Activates the audio session and starts the silent loop.
    ///
    /// The loop is what keeps the process alive once the phone is pocketed: iOS suspends an
    /// app with no background mode, and a suspended app cannot fire cues. The *countdown*
    /// does not depend on it — the engine works from absolute end dates, so a suspension
    /// resolves correctly on the next tick whether or not this holds.
    ///
    /// `.playback` is deliberate: it ignores the ring/silent switch, which is what you want
    /// from a workout timer. `.mixWithOthers` keeps it from stopping your music.
    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        keepAlive = player(for: Tone.silence(seconds: 1), loops: true)
        keepAlive?.play()

        transitionCue = player(for: Tone.beep(frequency: 880, seconds: 0.18), loops: false)
        tickCue = player(for: Tone.beep(frequency: 660, seconds: 0.07, amplitude: 0.25), loops: false)

        notification.prepare()
        impact.prepare()
    }

    func stop() {
        keepAlive?.stop()
        keepAlive = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// One interval ended and the next began.
    func playTransition() {
        notification.notificationOccurred(.success)
        play(transitionCue)
    }

    /// Each of the last three seconds of a timed interval.
    func playCountdownTick() {
        impact.impactOccurred()
        play(tickCue)
    }

    func playFinish() {
        notification.notificationOccurred(.success)
        play(transitionCue)
    }

    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for data: Data, loops: Bool) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        player.numberOfLoops = loops ? -1 : 0
        player.prepareToPlay()
        return player
    }
}

/// Generates the two tones the session needs, rather than shipping audio files.
///
/// A minimal 16-bit mono PCM WAV writer is about thirty lines, and it means there is no
/// asset to keep in sync with the bundle — the silence and the beeps are built at launch.
private enum Tone {

    private static let sampleRate = 44_100

    /// A one-second buffer of zeros. Played on a loop it keeps the audio session (and
    /// therefore the app) alive.
    static func silence(seconds: Double) -> Data {
        wav(samples: [Int16](repeating: 0, count: Int(Double(sampleRate) * seconds)))
    }

    static func beep(frequency: Double, seconds: Double, amplitude: Double = 0.4) -> Data {
        let count = Int(Double(sampleRate) * seconds)
        // A short fade at each end stops the tone clicking.
        let fade = min(count / 4, sampleRate / 200)
        var samples = [Int16](repeating: 0, count: count)

        for index in 0..<count {
            var envelope = 1.0
            if index < fade { envelope = Double(index) / Double(fade) }
            if index >= count - fade { envelope = Double(count - index) / Double(fade) }

            let wave = sin(2 * .pi * frequency * Double(index) / Double(sampleRate))
            samples[index] = Int16(max(-1, min(1, wave * amplitude * envelope)) * 32_767)
        }

        return wav(samples: samples)
    }

    private static func wav(samples: [Int16]) -> Data {
        var data = Data()
        let payload = samples.count * 2

        func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + payload)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)                       // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(payload))
        for sample in samples { u16(UInt16(bitPattern: sample)) }

        return data
    }
}
