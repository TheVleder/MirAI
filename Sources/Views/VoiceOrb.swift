import SwiftUI

/// Futuristic animated orb that reacts to audio state — pulses while listening,
/// glows while speaking, and breathes softly when idle.
struct VoiceOrb: View {
    let audioState: AudioManager.AudioState
    let audioLevel: Float

    @State private var phase: Double = 0
    @State private var innerPhase: Double = 0

    private var isActive: Bool {
        audioState == .listening || audioState == .speaking
    }

    private var primaryColor: Color {
        switch audioState {
        case .idle: return .cyan.opacity(0.4)
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .cyan
        }
    }

    private var glowColor: Color {
        switch audioState {
        case .idle: return .cyan.opacity(0.1)
        case .listening: return .red.opacity(0.3)
        case .processing: return .orange.opacity(0.2)
        case .speaking: return .cyan.opacity(0.3)
        }
    }

    var body: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        primaryColor.opacity(0.15 - Double(i) * 0.04),
                        lineWidth: 1.5
                    )
                    .frame(
                        width: orbSize + CGFloat(i) * 28 + pulseOffset(ring: i),
                        height: orbSize + CGFloat(i) * 28 + pulseOffset(ring: i)
                    )
                    .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.15 : 1.0)
            }

            // Rotating arc
            Circle()
                .trim(from: 0.0, to: 0.3)
                .stroke(
                    LinearGradient(
                        colors: [primaryColor, primaryColor.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: orbSize + 40, height: orbSize + 40)
                .rotationEffect(.degrees(phase * 360))

            // Counter-rotating arc
            Circle()
                .trim(from: 0.0, to: 0.2)
                .stroke(
                    LinearGradient(
                        colors: [primaryColor.opacity(0.6), primaryColor.opacity(0)],
                        startPoint: .trailing,
                        endPoint: .leading
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: orbSize + 20, height: orbSize + 20)
                .rotationEffect(.degrees(-innerPhase * 360))

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            primaryColor.opacity(0.8),
                            primaryColor.opacity(0.3),
                            primaryColor.opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: orbSize / 2
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(1.0 + CGFloat(audioLevel) * 0.2)

            // Inner bright core
            Circle()
                .fill(primaryColor.opacity(0.9))
                .frame(width: 12, height: 12)
                .blur(radius: 4)
                .scaleEffect(isActive ? 1.3 + CGFloat(audioLevel) * 0.5 : 0.8)

            // State icon
            stateIcon
        }
        .frame(width: 160, height: 160)
        .animation(.easeInOut(duration: 0.3), value: audioState)
        .animation(.spring(response: 0.15), value: audioLevel)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = 1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                innerPhase = 1
            }
        }
    }

    private var orbSize: CGFloat {
        switch audioState {
        case .idle: return 50
        case .listening: return 56
        case .processing: return 48
        case .speaking: return 60
        }
    }

    private func pulseOffset(ring: Int) -> CGFloat {
        guard isActive else { return 0 }
        return CGFloat(audioLevel) * CGFloat(10 + ring * 5)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch audioState {
        case .idle:
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        case .listening:
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .symbolEffect(.variableColor, isActive: true)
        case .processing:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
        case .speaking:
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .symbolEffect(.variableColor, isActive: true)
        }
    }
}
