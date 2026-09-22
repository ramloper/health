import AVFoundation
import Combine
import Foundation

final class GymMetronome: ObservableObject {
    /// One instance for the whole app so BPM and on/off agree between tabs.
    static let shared = GymMetronome()

    @Published var bpm: Int {
        didSet {
            UserDefaults.standard.set(bpm, forKey: "gym.metronome.bpm")
            if isOn { arm() }
        }
    }
    @Published var isOn = false {
        didSet { isOn ? arm() : disarm() }
    }

    private var timer: DispatchSourceTimer?
    private var player: AVAudioPlayer?
    private var audioReady = false

    init() {
        let stored = UserDefaults.standard.integer(forKey: "gym.metronome.bpm")
        bpm = stored == 0 ? 80 : min(180, max(40, stored))
    }

    deinit { disarm() }

    /// Claim the audio session lazily: only an app that is actually clicking should touch it.
    private func prepareAudioIfNeeded() {
        guard !audioReady else { return }
        audioReady = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if let data = Self.clickWAV() {
            player = try? AVAudioPlayer(data: data)
            player?.prepareToPlay()
            player?.volume = 1
        }
    }

    private func arm() {
        prepareAudioIfNeeded()
        disarmTimer()
        let interval = 60.0 / Double(max(40, min(bpm, 180)))
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            self?.player?.pause()
            self?.player?.currentTime = 0
            self?.player?.play()
        }
        source.resume()
        timer = source
    }

    private func disarm() {
        disarmTimer()
        player?.stop()
    }

    private func disarmTimer() {
        timer?.cancel()
        timer = nil
    }

    private static func clickWAV() -> Data? {
        let sampleRate = 22_050
        let duration = 0.03
        let n = Int(Double(sampleRate) * duration)
        var samples = [Int16]()
        samples.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let env = max(0, 1 - t / duration)
            let v = sin(2 * .pi * 1200 * t) * env
            samples.append(Int16(max(-1, min(1, v)) * 24_000))
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let dataSize = UInt32(n * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        u32(36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        data.append(contentsOf: Array("data".utf8))
        u32(dataSize)
        for s in samples {
            var x = s.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        return data
    }
}
