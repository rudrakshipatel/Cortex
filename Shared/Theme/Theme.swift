import SwiftUI

/// Cortex design system — palette lifted from DocRiddles.com
/// Teal brand + orange CTA on a mint→peach gradient, navy stat bars.
enum CX {

    // MARK: Legal links (open the hosted pages)
    static let termsURL   = URL(string: "https://www.cortexcases.com/terms")!
    static let privacyURL = URL(string: "https://www.cortexcases.com/privacy")!

    // MARK: Core palette
    static let teal       = Color(hex: 0x16C2B0)   // brand / category
    static let tealDark   = Color(hex: 0x0FA899)
    static let tealSoft   = Color(hex: 0xD7F3EF)   // tinted fills
    static let orange     = Color(hex: 0xF5803E)   // primary CTA
    static let orangeDark = Color(hex: 0xE56A28)
    static let orangeSoft = Color(hex: 0xFCE7D6)
    static let navy       = Color(hex: 0x15233B)   // headings / stat bars
    static let navySoft   = Color(hex: 0x4A5A74)   // secondary text
    static let gold       = Color(hex: 0xF5B72E)   // stat numbers / XP

    // MARK: Surfaces
    static let bgTop      = Color(hex: 0xDCF4ED)   // mint
    static let bgBottom   = Color(hex: 0xFDEFE0)   // peach
    static let card       = Color.white
    static let hairline   = Color(hex: 0xE6E9F0)

    // MARK: Gradients
    static var appBackground: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom],
                       startPoint: .top, endPoint: .bottom)
    }
    static var orangeButton: LinearGradient {
        LinearGradient(colors: [orange, orangeDark],
                       startPoint: .top, endPoint: .bottom)
    }
    static var tealButton: LinearGradient {
        LinearGradient(colors: [teal, tealDark],
                       startPoint: .top, endPoint: .bottom)
    }
    /// Marks an active Pro subscriber (the "PRO" badge in the top bar).
    static var goldButton: LinearGradient {
        LinearGradient(colors: [gold, Color(hex: 0xD9971A)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var navyBar: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x1B3357), Color(hex: 0x10203A)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Type — rounded, friendly (matches DocRiddles)
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue:  Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Background wrapper
struct AppBackground<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            CX.appBackground.ignoresSafeArea()
            content
        }
    }
}
