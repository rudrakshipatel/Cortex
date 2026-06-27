import SwiftUI

/// Dr. Vix — the DocRiddles fox mascot.
/// If an image asset named "DrVix-<pose>" (e.g. "DrVix-hero") exists in the
/// asset catalog it is used; otherwise an animated vector fox is drawn so the
/// app is always complete and lively. Generated poses can be dropped in later.
struct DrVix: View {
    enum Pose: String {
        case idle, idea, cheer, hero, meditate, avatar
    }
    var pose: Pose = .idle
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let asset = imageAsset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            } else {
                VectorFox(pose: pose)
            }
        }
        .frame(width: size, height: size)
    }

    /// Prefers a pose-specific asset ("DrVix-hero"), then a single shared
    /// "DrVix" asset (used for every pose), otherwise nil → animated vector.
    private var imageAsset: String? {
        if UIImage(named: "DrVix-\(pose.rawValue)") != nil { return "DrVix-\(pose.rawValue)" }
        if UIImage(named: "DrVix") != nil { return "DrVix" }
        return nil
    }
}

// MARK: - Animated vector fallback
private struct VectorFox: View {
    var pose: DrVix.Pose

    private let orange = CX.orange
    private let orangeDeep = Color(hex: 0xE0641F)
    private let cream = Color(hex: 0xFFF3E8)
    private let dark = CX.navy
    private let blush = Color(hex: 0xF6A6B2)

    // Animation state
    @State private var bob = false
    @State private var breathe = false
    @State private var earTwitch = false
    @State private var tailWag = false
    @State private var accent = false
    @State private var eyeOpen: CGFloat = 1
    private let blink = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    private var eyesClosed: Bool { pose == .meditate }
    private var bobAmount: CGFloat { pose == .cheer ? 0.05 : 0.022 }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                accentBehind(s)
                tail(s)
                head(s)
                accentFront(s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: bob ? -s * bobAmount : s * bobAmount)
            .scaleEffect(breathe ? 1.015 : 0.985)
            .onAppear { start() }
            .onReceive(blink) { _ in doBlink() }
        }
    }

    // MARK: Animations
    private func start() {
        let floatDur = pose == .meditate ? 3.4 : (pose == .cheer ? 0.5 : 2.1)
        withAnimation(.easeInOut(duration: floatDur).repeatForever(autoreverses: true)) { bob = true }
        withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) { breathe = true }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { tailWag = true }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { earTwitch = true }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { accent = true }
        if eyesClosed { eyeOpen = 0.1 }
    }

    private func doBlink() {
        guard !eyesClosed else { return }
        withAnimation(.easeInOut(duration: 0.09)) { eyeOpen = 0.08 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.13)) { eyeOpen = 1 }
        }
    }

    // MARK: Tail (wags)
    private func tail(_ s: CGFloat) -> some View {
        ZStack {
            Capsule().fill(orange).frame(width: s * 0.22, height: s * 0.46)
            Capsule().fill(cream).frame(width: s * 0.15, height: s * 0.18).offset(y: s * 0.15)
        }
        .rotationEffect(.degrees(tailWag ? -16 : -34), anchor: .top)
        .offset(x: -s * 0.30, y: s * 0.20)
    }

    // MARK: Head
    private func head(_ s: CGFloat) -> some View {
        ZStack {
            ears(s)

            Ellipse().fill(orange).frame(width: s * 0.80, height: s * 0.72)
                .shadow(color: dark.opacity(0.08), radius: s * 0.03, y: s * 0.02)

            // White muzzle
            Ellipse().fill(cream).frame(width: s * 0.52, height: s * 0.46).offset(y: s * 0.10)

            // Blush cheeks
            ForEach([-1.0, 1.0], id: \.self) { d in
                Circle().fill(blush.opacity(0.5)).frame(width: s * 0.11, height: s * 0.11)
                    .offset(x: d * s * 0.21, y: s * 0.09)
            }

            eyes(s)

            // Nose
            NoseShape().fill(dark)
                .frame(width: s * 0.12, height: s * 0.09).offset(y: s * 0.085)

            // Mouth
            Smile().stroke(dark, style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round))
                .frame(width: s * 0.14, height: s * 0.08).offset(y: s * 0.2)

            // Stethoscope — the "Doc" in DocRiddles
            Image(systemName: "stethoscope")
                .font(.system(size: s * 0.18, weight: .bold))
                .foregroundStyle(CX.teal)
                .offset(y: s * 0.33)
        }
    }

    private func ears(_ s: CGFloat) -> some View {
        ForEach([-1.0, 1.0], id: \.self) { d in
            ZStack {
                Triangle().fill(orange).frame(width: s * 0.30, height: s * 0.34)
                Triangle().fill(blush.opacity(0.85)).frame(width: s * 0.13, height: s * 0.17)
                    .offset(y: s * 0.02)
            }
            .rotationEffect(.degrees(d * (earTwitch ? 15 : 20)), anchor: .bottom)
            .offset(x: d * s * 0.23, y: -s * 0.30)
        }
    }

    private func eyes(_ s: CGFloat) -> some View {
        HStack(spacing: s * 0.17) { eye(s); eye(s) }
            .offset(y: -s * 0.03)
    }

    @ViewBuilder private func eye(_ s: CGFloat) -> some View {
        if eyesClosed {
            CurveEye(up: false).stroke(dark, style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
                .frame(width: s * 0.13, height: s * 0.06)
        } else if pose == .cheer {
            CurveEye(up: true).stroke(dark, style: StrokeStyle(lineWidth: s * 0.026, lineCap: .round))
                .frame(width: s * 0.13, height: s * 0.08)
        } else {
            ZStack {
                Circle().fill(.white).frame(width: s * 0.16, height: s * 0.16)
                Circle().fill(dark).frame(width: s * 0.095, height: s * 0.095)
                Circle().fill(.white).frame(width: s * 0.032, height: s * 0.032)
                    .offset(x: s * 0.022, y: -s * 0.022)
            }
            .scaleEffect(x: 1, y: eyeOpen, anchor: .center)
        }
    }

    // MARK: Pose accents
    @ViewBuilder private func accentBehind(_ s: CGFloat) -> some View {
        if pose == .hero {
            Capsule().fill(orangeDeep)
                .frame(width: s * 0.7, height: s * 0.5)
                .rotationEffect(.degrees(accent ? 16 : 26))
                .offset(x: s * 0.18, y: s * 0.24)
                .opacity(0.9)
        }
    }

    @ViewBuilder private func accentFront(_ s: CGFloat) -> some View {
        switch pose {
        case .idea:
            Image(systemName: "lightbulb.fill")
                .font(.system(size: s * 0.2))
                .foregroundStyle(CX.gold)
                .offset(y: -s * 0.52)
                .scaleEffect(accent ? 1.15 : 0.92)
                .shadow(color: CX.gold.opacity(accent ? 0.7 : 0.15), radius: s * (accent ? 0.07 : 0.02))
        case .cheer:
            ForEach(0..<3, id: \.self) { i in
                let xs: [CGFloat] = [-0.42, 0.42, 0.0]
                let ys: [CGFloat] = [-0.28, -0.18, -0.52]
                Image(systemName: "sparkle")
                    .font(.system(size: s * 0.13))
                    .foregroundStyle(CX.gold)
                    .offset(x: xs[i] * s, y: ys[i] * s)
                    .opacity(accent ? 1 : 0.3)
                    .scaleEffect(accent ? 1 : 0.5)
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Shapes
private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
private struct NoseShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
private struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
/// Curved eye — `up` makes a happy ∩, otherwise a relaxed ∪ (closed/calm).
private struct CurveEye: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: up ? r.maxY : r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: up ? r.maxY : r.minY),
                       control: CGPoint(x: r.midX, y: up ? r.minY : r.maxY))
        return p
    }
}
