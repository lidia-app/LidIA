import SwiftUI

struct LiveWaveformView: View {
    @Environment(RecordingSession.self) private var session

    let isActive: Bool

    @State private var samples: [Float] = Array(repeating: 0, count: 60)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let _ = sampleRMS()
            Canvas { context, size in
                let barWidth: CGFloat = 3
                let gap: CGFloat = 2
                let totalBars = Int(size.width / (barWidth + gap))
                let displaySamples = Array(samples.suffix(totalBars))

                for (i, sample) in displaySamples.enumerated() {
                    let normalizedHeight = CGFloat(min(sample * 3, 1.0)) * size.height
                    let height = max(2, normalizedHeight)
                    let x = CGFloat(i) * (barWidth + gap)
                    let y = (size.height - height) / 2

                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(isActive ? .red.opacity(0.8) : .secondary.opacity(0.3))
                    )
                }
            }
        }
    }

    /// Samples the current RMS from RecordingSession each frame.
    /// Called inside TimelineView body so it runs every 50ms.
    @discardableResult
    private func sampleRMS() -> Bool {
        if isActive {
            let rms = session.currentRMS
            // Mutating @State from inside body via TimelineView is fine —
            // TimelineView triggers re-render on schedule, and we append here.
            DispatchQueue.main.async {
                samples.append(rms)
                if samples.count > 120 {
                    samples.removeFirst(samples.count - 120)
                }
            }
        }
        return true
    }
}
