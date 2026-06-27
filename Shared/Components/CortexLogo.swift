import SwiftUI

/// Cortex brand logo — a teal squircle "neural mark" with an orange insight
/// spark, paired with the rounded navy wordmark. Built entirely in SwiftUI so
/// it scales crisply at any size and matches the DocRiddles palette.
struct CortexLogo: View {
    enum Layout { case horizontal, stacked, markOnly }

    var layout: Layout = .horizontal
    /// Size of the square mark; the wordmark scales relative to it.
    var size: CGFloat = 64
    var showTagline: Bool = false

    var body: some View {
        switch layout {
        case .markOnly:
            mark
        case .horizontal:
            HStack(spacing: size * 0.28) {
                mark
                wordmark
            }
        case .stacked:
            VStack(spacing: size * 0.22) {
                mark
                wordmark
            }
        }
    }

    // MARK: Mark — Dr. Vix fox-doctor app icon in a teal squircle
    private var mark: some View {
        Image("CortexMark")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: size * 0.02)
            )
            .shadow(color: CX.teal.opacity(0.35), radius: size * 0.16, y: size * 0.10)
    }

    // MARK: Wordmark
    private var wordmark: some View {
        VStack(alignment: layout == .stacked ? .center : .leading, spacing: size * 0.04) {
            Text("Cortex")
                .font(.system(size: size * 0.56, weight: .heavy, design: .rounded))
                .foregroundStyle(CX.navy)
                .kerning(-size * 0.01)
            if showTagline {
                Text("THINK LIKE A DOCTOR")
                    .font(.system(size: size * 0.14, weight: .bold, design: .rounded))
                    .foregroundStyle(CX.teal)
                    .kerning(size * 0.03)
            }
        }
    }
}

#Preview {
    AppBackground {
        VStack(spacing: 40) {
            CortexLogo(layout: .horizontal, size: 64)
            CortexLogo(layout: .stacked, size: 88, showTagline: true)
            CortexLogo(layout: .markOnly, size: 72)
        }
    }
}
