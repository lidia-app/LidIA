import SwiftUI

/// Animated audio waveform bars for recording indicators.
/// Renders 5 vertical bars that dance at different frequencies when active.
struct AudioWaveformView: View {
    var isActive: Bool
    var isPaused: Bool = false
    var barCount: Int = 5
    var color: Color = .red
    var style: WaveformStyle = .standard

    enum WaveformStyle {
        case standard   // Opaque colored bars
        case glass      // Translucent with gradient
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || isPaused)) { timeline in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    barView(index: index, date: timeline.date)
                }
            }
        }
    }

    private var spacing: CGFloat {
        barCount <= 5 ? 2.5 : 2
    }

    private var barWidth: CGFloat {
        barCount <= 5 ? 3 : 2.5
    }

    @ViewBuilder
    private func barView(index: Int, date: Date) -> some View {
        let height = barHeight(index: index, date: date)
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barFill)
            .frame(width: barWidth, height: height)
            .animation(.easeInOut(duration: 0.12), value: height)
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        let maxHeight: CGFloat = 16
        let minHeight: CGFloat = 3

        guard isActive else { return minHeight }

        if isPaused {
            // Static mid-height bars when paused
            let pausedHeights: [CGFloat] = [0.3, 0.5, 0.4, 0.55, 0.35]
            let h = pausedHeights[index % pausedHeights.count]
            return minHeight + (maxHeight - minHeight) * h
        }

        // Each bar oscillates at a different frequency + phase
        let time = date.timeIntervalSinceReferenceDate
        let frequencies: [Double] = [2.3, 3.1, 1.7, 2.8, 2.0, 3.5, 1.9]
        let phases: [Double] = [0, 1.2, 0.6, 2.1, 1.5, 0.3, 2.7]

        let freq = frequencies[index % frequencies.count]
        let phase = phases[index % phases.count]

        // Combine two sine waves for organic movement
        let wave1 = sin(time * freq * .pi + phase)
        let wave2 = sin(time * freq * 0.7 * .pi + phase + 1.3) * 0.4
        let normalized = (wave1 + wave2 + 1.4) / 2.8 // 0...1 range

        return minHeight + (maxHeight - minHeight) * normalized
    }

    @MainActor
    private var barFill: some ShapeStyle {
        switch style {
        case .standard:
            return AnyShapeStyle(color)
        case .glass:
            return AnyShapeStyle(
                color.opacity(0.8).gradient
            )
        }
    }
}

// MARK: - Compact variant for sidebar / menu bar

extension AudioWaveformView {
    /// Small waveform for tight spaces (sidebar recording indicator, menu bar)
    static func compact(isActive: Bool, isPaused: Bool = false) -> some View {
        AudioWaveformView(
            isActive: isActive,
            isPaused: isPaused,
            barCount: 4,
            color: .red,
            style: .standard
        )
        .frame(width: 18, height: 14)
    }
}
