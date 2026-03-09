import SwiftUI

struct SignalBars: View {
    var signalLevel: Float
    var isActive:    Bool
    var liveText:    String
    var isRefining:  Bool    = false
    var notchMode:   Bool    = false
    var notchVisible: Bool   = false
    var onStop:   (() -> Void)?
    var onCancel: (() -> Void)?

    private let barCount      = 24
    private let notchBarCount = 16
    @State private var phases:    [Double] = (0..<24).map { Double($0) * 0.4 }
    @State private var animTimer: Timer?
    @State private var appeared  = false

    private let cornerRadius:             CGFloat = 22
    private let notchTopCornerRadius:     CGFloat = 8
    private let notchBottomCornerRadius:  CGFloat = 10

    var body: some View {
        Group {
            if notchMode {
                notchBody
            } else {
                pillBody
            }
        }
        .onAppear {
            startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true
            }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
    }

    private var pillBody: some View {
        HStack(spacing: 8) {
            cancelButton
                .opacity(isRefining ? 0 : 1)

            ZStack {
                waveformBars.opacity(isRefining ? 0 : 1)
                ProcessingDot(travel: pillBarTravel).opacity(isRefining ? 1 : 0)
            }

            stopButton
                .opacity(isRefining ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.25), value: isRefining)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(appeared ? 1.0 : 0.5, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.1), value: appeared)
    }

    private var notchBody: some View {
        ZStack {
            if notchVisible {
                notchExpandedContent
                    .transition(.opacity)
            } else {
                notchIdleBars
                    .transition(.opacity)
            }
        }
        .frame(width: notchContentWidth, height: notchVisible ? 32 : 24)
        .background(
            NotchShape(
                topCornerRadius: notchTopCornerRadius,
                bottomCornerRadius: notchVisible ? notchBottomCornerRadius : 6
            )
            .fill(.black)
        )
        .clipShape(
            NotchShape(
                topCornerRadius: notchTopCornerRadius,
                bottomCornerRadius: notchVisible ? notchBottomCornerRadius : 6
            )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: notchVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notchExpandedContent: some View {
        HStack(spacing: 0) {
            cancelButton
                .padding(.leading, 12)
                .opacity(isRefining ? 0 : 1)

            Spacer(minLength: 6)

            ZStack {
                notchWaveformBars.opacity(isRefining ? 0 : 1)
                ProcessingDot(travel: notchBarTravel).opacity(isRefining ? 1 : 0)
            }

            Spacer(minLength: 6)

            stopButton
                .padding(.trailing, 12)
                .opacity(isRefining ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.25), value: isRefining)
    }

    private var notchIdleBars: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.35))
                    .frame(width: 2, height: notchIdleBarHeight(for: index))
            }
        }
    }

    private func notchIdleBarHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [4, 8, 12, 6, 9]
        let phase = phases[min(index * 4, barCount - 1)]
        let sine = (sin(phase) + 1) / 2
        return heights[index] + 2 * CGFloat(sine)
    }

    private var notchContentWidth: CGFloat {
        notchVisible ? 280 : 64
    }


    private var cancelButton: some View {
        Button(action: { onCancel?() }) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button(action: { onStop?() }) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white)
                .frame(width: 8, height: 8)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.red.opacity(0.8)))
        }
        .buttonStyle(.plain)
    }


    private var waveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 2.5, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: signalLevel)
            }
        }
        .frame(height: 24)
    }

    private var notchWaveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<notchBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 2.5, height: notchBarHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: signalLevel)
            }
        }
        .frame(height: 20)
    }


    // (barCount bars × 2.5pt) + (barCount-1 gaps × 2.5pt) = (barCount*2 - 1) * 2.5
    private var pillBarTravel:  CGFloat { CGFloat(barCount      * 2 - 1) * 2.5 / 2 - 4 }
    private var notchBarTravel: CGFloat { CGFloat(notchBarCount * 2 - 1) * 2.5 / 2 - 4 }


    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(signalLevel)
        let phase = phases[index]
        let sine  = (sin(phase) + 1) / 2
        let minH: CGFloat = 3
        let maxH: CGFloat = 22

        if isActive {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.7 + 0.3)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.15) * CGFloat(sine)
        }
    }

    private func notchBarHeight(for index: Int) -> CGFloat {
        let level = min(CGFloat(signalLevel) * 1.6, 1.0)
        let phaseIndex = Int(Double(index) * Double(barCount - 1) / Double(notchBarCount - 1))
        let phase = phases[phaseIndex]
        let sine  = (sin(phase) + 1) / 2
        let minH: CGFloat = 4
        let maxH: CGFloat = 18

        if isActive {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.5 + 0.5)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.15) * CGFloat(sine)
        }
    }



    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                let speed: Double = isActive ? 0.18 : 0.05
                for i in 0..<barCount {
                    phases[i] += speed + Double(i) * 0.008
                }
            }
        }
        if let timer = animTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }
}


private struct ProcessingDot: View {
    let travel: CGFloat
    private let period: Double = 1.4

    var body: some View {
        TimelineView(.animation) { context in
            let t     = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: period) / period) * 2 * Double.pi
            let progress = CGFloat(abs(sin(angle)))
            let offsetX  = CGFloat(-cos(angle)) * travel
            let scale    = 0.55 + 0.75 * progress
            let opacity  = 0.35 + 0.60 * Double(progress)

            Circle()
                .fill(.white.opacity(opacity))
                .frame(width: 7, height: 7)
                .scaleEffect(scale, anchor: .center)
                .offset(x: offsetX)
        }
    }
}


struct NotchShape: Shape {
    var topCornerRadius:    CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 16) {
        self.topCornerRadius    = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
