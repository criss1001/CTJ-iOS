import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var nes = NESSystem()
    @State private var timer: Timer?
    @State private var gameStarted = false
    @State private var toast: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("GameBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                HStack(spacing: 16) {
                    JoystickView { mask, pressed in nes.setButton(mask, pressed: pressed) }
                    screenPanel.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        actionButtons
                        startSelectRow
                        restartBall
                    }
                }
                .padding(16)

                stateButton("LOAD") {
                    showResult(nes.loadState() ? "LOADED" : "NO SAVE")
                }
                .position(x: max(82, geo.size.width * 0.16), y: 28)

                stateButton("SAVE") {
                    showResult(nes.saveState() ? "SAVED" : "SAVE FAILED")
                }
                .position(x: min(geo.size.width - 82, geo.size.width * 0.84), y: 28)

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 10)
                    }
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { autoStart() }
    }

    private var screenPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 10)

            if let img = nes.image {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(256.0 / 240.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(6)
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(256.0 / 240.0, contentMode: .fit)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            modernButton("B", .pink).simultaneousGesture(pressGesture(NESButton.B))
            modernButton("A", .blue).simultaneousGesture(pressGesture(NESButton.A))
        }
    }

    private func modernButton(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(color.opacity(0.55)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            )
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
    }

    private var startSelectRow: some View {
        HStack(spacing: 10) {
            modernPill("SELECT").simultaneousGesture(pressGesture(NESButton.Select))
            modernPill("START").simultaneousGesture(pressGesture(NESButton.Start))
        }
    }

    private func modernPill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 70, height: 30)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func stateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 58, height: 27)
                .background(Color.black.opacity(0.62), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var restartBall: some View {
        Button {
            nes.restartGame()
            showResult("RESTARTED")
        } label: {
            Text("⚽️")
                .font(.system(size: 34))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Restart Game")
    }

    private func pressGesture(_ mask: UInt8) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in nes.setButton(mask, pressed: true) }
            .onEnded { _ in nes.setButton(mask, pressed: false) }
    }

    private func showResult(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private func autoStart() {
        guard !gameStarted else { return }
        guard let url = Bundle.main.url(forResource: "game", withExtension: "nes"),
              let data = try? Data(contentsOf: url) else { return }
        if nes.loadROM(data: [UInt8](data)) {
            gameStarted = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0988, repeats: true) { _ in
                nes.runFrame()
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }
}
