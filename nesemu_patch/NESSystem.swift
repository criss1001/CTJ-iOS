import Foundation
import CoreGraphics
import AVFoundation

final class NESSystem: ObservableObject {
    let bus = Bus()
    var cpu: CPU6502!
    let ppu = PPU2C02()
    let apu = APU()
    var cart: Cartridge?
    private var loadedROMData: [UInt8]?
    private var masterClock: UInt64 = 0

    @Published var image: CGImage?

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    init() {
        cpu = CPU6502(bus: bus)
        bus.ppu = ppu
        bus.apu = apu
        setupAudio()
    }

    func loadROM(data: [UInt8]) -> Bool {
        guard let cart = Cartridge(data: data) else { return false }
        loadedROMData = data
        self.cart = cart
        bus.cart = cart
        ppu.cart = cart
        cpu.reset()
        ppu.reset()
        masterClock = 0
        return true
    }

    func restartGame() {
        guard let data = loadedROMData else { return }
        bus.ram = [UInt8](repeating: 0, count: 2048)
        bus.controller1 = 0
        bus.controller1Shift = 0
        bus.controller1Strobe = false
        _ = loadROM(data: data)
    }

    private struct SaveStateFile: Codable {
        let version: Int
        let cpu: CPU6502.SaveState
        let bus: Bus.SaveState
        let ppu: PPU2C02.SaveState
        let cartridge: Cartridge.SaveState
    }

    private var saveStateURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("quickstate.json")
    }

    @discardableResult
    func saveState() -> Bool {
        guard let cart, let url = saveStateURL else { return false }
        let state = SaveStateFile(version: 1, cpu: cpu.makeSaveState(), bus: bus.makeSaveState(), ppu: ppu.makeSaveState(), cartridge: cart.makeSaveState())
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func loadState() -> Bool {
        guard let cart, let url = saveStateURL else { return false }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(SaveStateFile.self, from: data)
            guard state.version == 1 else { return false }
            bus.applySaveState(state.bus)
            cart.applySaveState(state.cartridge)
            ppu.applySaveState(state.ppu)
            cpu.applySaveState(state.cpu)
            updateImage()
            return true
        } catch {
            return false
        }
    }

    func runFrame() {
        ppu.frameComplete = false
        while !ppu.frameComplete {
            let nmiFired = ppu.clock()
            if ppu.cycle % 3 == 0 {
                cpu.step()
                apu.clockCPUCycle()
            }
            if nmiFired { cpu.nmi() }
            if let cart = cart, cart.irqPending { cpu.irq() }
        }
        updateImage()
    }

    func setButton(_ mask: UInt8, pressed: Bool) {
        if pressed { bus.controller1 |= mask }
        else { bus.controller1 &= ~mask }
    }

    private func updateImage() {
        let width = 256, height = 240
        let data = Data(ppu.framebuffer)
        guard let provider = CGDataProvider(data: data as CFData) else { return }
        image = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private func setupAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredSampleRate(48000)
        try? session.setPreferredIOBufferDuration(0.010)
        try? session.setActive(true)

        let hardwareRate = session.sampleRate > 0 ? session.sampleRate : 48000
        let format = AVAudioFormat(standardFormatWithSampleRate: hardwareRate, channels: 1)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                let bufPtr = UnsafeMutableBufferPointer<Float>(buffer)
                for frame in 0..<Int(frameCount) {
                    bufPtr[frame] = self.apu.sampleBuffer.popOrHold()
                }
            }
            return noErr
        }
        sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        try? audioEngine.start()
    }
}

enum NESButton {
    static let A: UInt8 = 1 << 0
    static let B: UInt8 = 1 << 1
    static let Select: UInt8 = 1 << 2
    static let Start: UInt8 = 1 << 3
    static let Up: UInt8 = 1 << 4
    static let Down: UInt8 = 1 << 5
    static let Left: UInt8 = 1 << 6
    static let Right: UInt8 = 1 << 7
}
