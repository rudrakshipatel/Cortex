import SwiftUI

// MARK: - Primary chunky button — Duolingo-style 3D "push" button
struct CXButton: View {
    var title: String
    var icon: String? = "arrow.right"
    var style: Style = .orange
    var action: () -> Void

    enum Style { case orange, teal, outline }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                if let icon { Image(systemName: icon) }
            }
            .font(CX.heading(18))
            .foregroundStyle(style == .outline ? CX.orange : .white)
        }
        .buttonStyle(PushButtonStyle(face: face, lip: lip, outlined: style == .outline))
    }

    private var face: Color {
        switch style { case .orange: return CX.orange; case .teal: return CX.teal; case .outline: return .white }
    }
    private var lip: Color {
        switch style { case .orange: return CX.orangeDark; case .teal: return CX.tealDark; case .outline: return CX.hairline }
    }
}

/// The signature Duolingo button: a solid face sitting on a darker "lip"; pressing
/// pushes the face down to meet the lip with a snappy spring.
struct PushButtonStyle: ButtonStyle {
    var face: Color
    var lip: Color
    var depth: CGFloat = 5
    var corner: CGFloat = 16
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(face)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(outlined ? CX.orange : .clear, lineWidth: 2)
                    )
            )
            .padding(.bottom, pressed ? 0 : depth)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(lip)
            )
            .offset(y: pressed ? depth : 0)
            .animation(.spring(response: 0.15, dampingFraction: 0.72), value: pressed)
    }
}

/// Bouncy scale-down used for cards and secondary buttons.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Celebration helpers (Duolingo-style)

/// A one-shot confetti burst. Drop it as an overlay when something is solved.
struct ConfettiBurst: View {
    private struct Piece: Identifiable {
        let id = UUID(); let angle: Double; let dist: CGFloat
        let color: Color; let rot: Double; let size: CGFloat
    }
    private let pieces: [Piece]
    @State private var go = false

    init(count: Int = 44) {
        let colors: [Color] = [CX.orange, CX.teal, CX.gold,
                               Color(hex: 0xF08AB0), Color(hex: 0x9B7BE0), Color(hex: 0x5AA9E6)]
        pieces = (0..<count).map { i in
            Piece(angle: .random(in: 0..<360), dist: .random(in: 70...240),
                  color: colors[i % colors.count], rot: .random(in: 0..<360),
                  size: .random(in: 7...13))
        }
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { p in
                RoundedRectangle(cornerRadius: 2).fill(p.color)
                    .frame(width: p.size, height: p.size * 1.4)
                    .rotationEffect(.degrees(p.rot + (go ? 260 : 0)))
                    .offset(x: go ? CGFloat(cos(p.angle * .pi / 180)) * p.dist : 0,
                            y: go ? CGFloat(sin(p.angle * .pi / 180)) * p.dist + 280 : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.5)) { go = true } }
        .allowsHitTesting(false)
    }
}

/// A springy pop-in entrance for celebratory elements.
struct BounceIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.55)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(delay)) { shown = true }
            }
    }
}
extension View {
    func bounceIn(delay: Double = 0) -> some View { modifier(BounceIn(delay: delay)) }
}

// MARK: - White rounded card
struct CXCard<Content: View>: View {
    var padding: CGFloat = 18
    var borderColor: Color = CX.hairline
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(CX.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .shadow(color: CX.navy.opacity(0.05), radius: 10, y: 5)
    }
}

// MARK: - Small pill (XP, streak, mode)
struct CXPill: View {
    var systemImage: String? = nil
    var emoji: String? = nil
    var text: String
    var fill: Color = .white
    var foreground: Color = CX.navy
    var border: Color = CX.hairline
    var body: some View {
        HStack(spacing: 6) {
            if let emoji { Text(emoji) }
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(CX.label(15))
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(fill, in: Capsule())
        .overlay(Capsule().stroke(border, lineWidth: 1.5))
    }
}

// MARK: - Section heading
struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(CX.heading(22))
            .foregroundStyle(CX.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mentor insight card (Dr. Vix)
struct MentorCard: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DrVix(pose: .idea, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text("MENTOR INSIGHT")
                    .font(CX.label(11))
                    .foregroundStyle(CX.orange)
                Text(text)
                    .font(CX.body(15))
                    .foregroundStyle(CX.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CX.tealSoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CX.teal.opacity(0.4), lineWidth: 1.5)
        )
    }
}

/// Mentor insight that must be unlocked with XP. Once unlocked for the case it
/// reveals every mentor hint in that case (`session.mentorUnlocked`).
struct MentorInsight: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: CaseSession
    var text: String
    @State private var confirm = false

    var body: some View {
        Group {
            if session.mentorUnlocked {
                MentorCard(text: text)
            } else {
                LockedMentorCard(cost: AppState.mentorCost,
                                 canAfford: app.coins >= AppState.mentorCost) {
                    confirm = true   // ask before spending
                }
            }
        }
        .confirmationDialog("Unlock Mentor Insight?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Unlock for \(AppState.mentorCost) coins") {
                if app.spendCoins(AppState.mentorCost) {
                    withAnimation(.spring(duration: 0.35)) { session.mentorUnlocked = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This spends \(AppState.mentorCost) coins (you have \(app.coins)) to reveal Dr. Vix's hints for this case.")
        }
    }
}

private struct LockedMentorCard: View {
    var cost: Int
    var canAfford: Bool
    var onUnlock: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                DrVix(pose: .idea, size: 46).opacity(0.45).grayscale(0.6)
                Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CX.navySoft)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("MENTOR INSIGHT").font(CX.label(11)).foregroundStyle(CX.orange)
                Text("Spend \(cost) coins to reveal Dr. Vix's hint for this case.")
                    .font(CX.body(14)).foregroundStyle(CX.navySoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onUnlock) {
                    HStack(spacing: 6) {
                        Image(systemName: canAfford ? "dollarsign.circle.fill" : "xmark.circle.fill")
                        Text(canAfford ? "Unlock · \(cost) coins" : "Need \(cost) coins")
                    }
                    .font(CX.label(13)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(canAfford ? AnyShapeStyle(CX.orangeButton) : AnyShapeStyle(CX.navySoft),
                                in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!canAfford)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CX.tealSoft.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CX.teal.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

// MARK: - Page dots
struct PageDots: View {
    var count: Int
    var index: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? CX.orange : CX.navy.opacity(0.18))
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: index)
            }
        }
    }
}

// MARK: - Trophy progress chip
struct TrophyChip: View {
    enum Kind { case bronze, silver, gold
        var color: Color {
            switch self {
            case .bronze: return Color(hex: 0xCD8B5A)
            case .silver: return CX.teal
            case .gold:   return CX.gold
            }
        }
    }
    var kind: Kind
    var value: Int
    var total: Int
    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)/\(total)")
                .font(CX.label(12))
                .foregroundStyle(CX.navySoft)
            Image(systemName: "trophy.fill")
                .font(.system(size: 12))
                .foregroundStyle(kind.color)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(kind.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Rich illustrated case card (hero image + skill/difficulty + teaser)
struct CaseHeroCard: View {
    let clinicalCase: ClinicalCase
    let skill: SkillRank
    var costsEnergy: Bool = true
    var solved: Bool = false
    var kicker: String? = nil
    var solveTitle: String = "Solve the case"
    var onSolve: () -> Void

    var body: some View {
        CXCard(padding: 0) {
            VStack(spacing: 0) {
                heroImage
                    .frame(height: 188).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .topLeading) {
                        if let kicker {
                            Text(kicker).font(CX.label(11)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(10)
                        }
                    }
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skill Level").font(CX.label(12)).foregroundStyle(CX.navySoft)
                            HStack(spacing: 6) {
                                Image(systemName: skill.icon).font(.system(size: 22)).foregroundStyle(skill.color)
                                Text(skill.name).font(CX.heading(18)).foregroundStyle(CX.navy)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("Difficulty Level").font(CX.label(12)).foregroundStyle(CX.navySoft)
                            difficultyPips
                        }
                    }
                    VStack(spacing: 6) {
                        Text(clinicalCase.specialty).font(CX.heading(18)).foregroundStyle(CX.orange)
                            .multilineTextAlignment(.center)
                        Text(clinicalCase.displayTitle).font(CX.title(24)).foregroundStyle(CX.navy)
                            .multilineTextAlignment(.center)
                        Text(clinicalCase.displayTeaser).font(CX.body(16)).foregroundStyle(CX.navySoft)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onSolve) {
                        HStack(spacing: 10) {
                            Image(systemName: solved ? "checkmark.seal.fill" : "play.fill")
                            Text(solved ? "Solved" : solveTitle)
                        }.font(CX.heading(18)).foregroundStyle(.white)
                    }
                    .buttonStyle(PushButtonStyle(face: solved ? CX.navySoft.opacity(0.4) : CX.orange,
                                                 lip: solved ? CX.navySoft.opacity(0.3) : CX.orangeDark))
                    .disabled(solved)
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder private var heroImage: some View {
        let name = clinicalCase.heroImageName
        if UIImage(named: name) != nil {
            // Authored image, or a bundled illustration picked per case.
            Image(name).resizable().scaledToFill()
        } else if UIImage(named: "case-hero-default") != nil {
            Image("case-hero-default").resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [CX.teal, CX.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "cross.case.fill").font(.system(size: 58)).foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var difficultyPips: some View {
        let palette: [Color] = [Color(hex: 0x4CC38A), Color(hex: 0xA7E8C3),
                                Color(hex: 0xF5D87A), Color(hex: 0xF3A6B0), Color(hex: 0xE86A6A)]
        let level = clinicalCase.difficultyLevel
        return HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(palette[i].opacity(i < level ? 1 : 0.3)).frame(width: 20, height: 9)
            }
        }
    }
}
