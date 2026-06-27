import SwiftUI

// MARK: - Shared scaffolding for the Me-page info screens
//
// Privacy Policy, Terms of Use, FAQs and Support are all rendered in-app as
// native scrollable documents (no external website needed). They share one
// header + layout so they stay visually consistent with the rest of Cortex.

/// Contact address used by the Support screen and legal pages.
private let supportEmail = "rudrakshikpatel2007@gmail.com"

/// A titled, dismissable, scrollable container used by every info page.
private struct InfoPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(CX.title(24)).foregroundStyle(CX.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26)).foregroundStyle(CX.navySoft)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                        Text("Cortex • v1.0")
                            .font(CX.label(12)).foregroundStyle(CX.navySoft)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }
}

/// One titled paragraph block inside an info page.
private struct InfoSection: View {
    let heading: String
    let text: String
    var body: some View {
        CXCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading).font(CX.heading(17)).foregroundStyle(CX.navy)
                Text(text).font(CX.body(14)).foregroundStyle(CX.navySoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func lastUpdatedLine() -> some View {
    Text("Last updated: June 2026")
        .font(CX.label(12)).foregroundStyle(CX.navySoft)
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        InfoPage(title: "Privacy Policy") {
            lastUpdatedLine()
            InfoSection(heading: "Overview",
                text: "Cortex is a clinical-reasoning training game. This policy explains what we collect, why, and the choices you have. We collect as little as possible and never sell your data.")
            InfoSection(heading: "What we collect",
                text: "• Account info: if you sign in with Google or Apple, we receive your name and email to identify your account.\n• Gameplay data: your username, XP, streaks, trophies and leaderboard score.\n• Device data: anonymous diagnostics to keep the app stable.")
            InfoSection(heading: "How we use it",
                text: "To run your account, save your progress, show leaderboards, deliver reminders and emergency cases you opt into, and improve the app. We do not use your data for advertising.")
            InfoSection(heading: "Storage & security",
                text: "Data is stored on Supabase, an encrypted cloud backend. Subscriptions are processed by Apple — we never see your card details. Sign-in is handled by Apple and Google; we never see your password.")
            InfoSection(heading: "Your choices",
                text: "You can edit your display name, turn off notifications in iOS Settings, sign out at any time, or request deletion of your account and data by emailing us.")
            InfoSection(heading: "Medical disclaimer",
                text: "Cortex is for education and entertainment only. Nothing in the app is medical advice and it must never be used to diagnose or treat a real patient.")
            InfoSection(heading: "Contact",
                text: "Questions about your privacy? Email \(supportEmail).")
        }
    }
}

// MARK: - Terms of Use

struct TermsOfUseView: View {
    var body: some View {
        InfoPage(title: "Terms of Use") {
            lastUpdatedLine()
            InfoSection(heading: "Acceptance",
                text: "By using Cortex you agree to these terms. If you do not agree, please don't use the app.")
            InfoSection(heading: "The service",
                text: "Cortex is an educational clinical-reasoning game. Cases, diagnoses and treatments are simplified for training and are not a substitute for professional medical judgment, advice, diagnosis or treatment.")
            InfoSection(heading: "Your account",
                text: "You're responsible for activity on your account and for keeping your sign-in secure. Don't impersonate others or upload offensive content to your profile or username.")
            InfoSection(heading: "Subscriptions",
                text: "Cortex Pro is an auto-renewing subscription billed through your Apple ID. It renews unless cancelled at least 24 hours before the period ends. Free trials, if offered, convert to a paid subscription unless cancelled before the trial ends. Manage or cancel anytime in iOS Settings ▸ Apple ID ▸ Subscriptions.")
            InfoSection(heading: "Acceptable use",
                text: "Don't reverse-engineer, abuse, or attempt to disrupt the service, and don't use it for any unlawful purpose.")
            InfoSection(heading: "No warranty",
                text: "Cortex is provided \u{201C}as is\u{201D} without warranties of any kind. We are not liable for any clinical decision made in reliance on the app — it is a learning tool, not a medical device.")
            InfoSection(heading: "Changes",
                text: "We may update these terms as the app evolves. Continued use after an update means you accept the revised terms.")
            InfoSection(heading: "Contact",
                text: "Questions about these terms? Email \(supportEmail).")
        }
    }
}

// MARK: - FAQs

struct FAQsView: View {
    private let faqs: [(String, String)] = [
        ("What is Cortex?",
         "Cortex is a game that trains clinical reasoning. You work up patient cases — order tests, reach a diagnosis, choose treatment — and earn XP, coins and trophies."),
        ("How is my XP scored?",
         "Each case is worth up to 100 XP. You earn the full 100 only for a flawless workup; your score reflects how accurate your tests, diagnosis and treatment were."),
        ("How does energy work?",
         "Energy slowly refills over time — a little every minute, up to a full bar of 100. Each case costs between 5 and 15 energy depending on how well you did: better solves cost less."),
        ("What are streaks?",
         "Play at least one case a day to keep your streak alive. Hitting milestone streaks rewards bonus coins, and a Streak Freeze from the shop can protect you on a day you miss."),
        ("What do coins do?",
         "Coins are earned by solving cases and hitting streak milestones. Spend them in the shop — for example on Streak Freezes."),
        ("What is Cortex Pro?",
         "Pro unlocks the full experience. It's an auto-renewing subscription through your Apple ID and may include a free trial. You can cancel anytime in iOS Settings."),
        ("What are emergency cases?",
         "Occasionally a time-sensitive \u{201C}emergency\u{201D} case appears for a few hours. Solve it while it's live for a special challenge."),
        ("How do I report a problem?",
         "Use \u{201C}Facing a Problem? Contact Us\u{201D} on the Me page, or email \(supportEmail).")
    ]

    var body: some View {
        InfoPage(title: "FAQs") {
            ForEach(faqs, id: \.0) { item in
                FAQRow(question: item.0, answer: item.1)
            }
        }
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var open = false

    var body: some View {
        CXCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Text(question).font(CX.heading(16)).foregroundStyle(CX.navy)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(CX.orange)
                    }
                }.buttonStyle(.plain)
                if open {
                    Text(answer).font(CX.body(14)).foregroundStyle(CX.navySoft)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Support / Contact Us

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    private var mailURL: URL? {
        let subject = "Cortex Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(supportEmail)?subject=\(subject)")
    }

    var body: some View {
        InfoPage(title: "Support") {
            CXCard {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 40)).foregroundStyle(CX.orange)
                    Text("Facing a problem?")
                        .font(CX.heading(18)).foregroundStyle(CX.navy)
                    Text("We'd love to help. Email us and we'll get back to you as soon as we can — usually within a couple of days.")
                        .font(CX.body(14)).foregroundStyle(CX.navySoft)
                        .multilineTextAlignment(.center).lineSpacing(3)
                    Button {
                        if let url = mailURL { openURL(url) }
                    } label: {
                        Text("Email Support").font(CX.heading(17)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PushButtonStyle(face: CX.orange, lip: CX.orangeDark))
                    .padding(.top, 4)
                    Text(supportEmail).font(CX.label(13)).foregroundStyle(CX.teal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            InfoSection(heading: "Before you write",
                text: "Many quick questions are answered in the FAQs on the Me page — give those a look first, they might save you a wait.")
            InfoSection(heading: "Helpful details to include",
                text: "• What you were doing when the problem happened\n• Your username\n• Your device and iOS version\n• A screenshot if you have one")
        }
    }
}
